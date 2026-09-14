import XCTest
import CloudKit
@testable import PhotoHandoffKit

final class CloudPhotoRecordTests: XCTestCase {
    private let account = PhotoAccount(container: "iCloud.com.ethdawg.workbench.preview",
        environment: "Production", userRecordName: "_0123456789abcdef0123456789abcdef")

    private func photo(version: Int = 1) -> RemoteHandoffPhoto {
        RemoteHandoffPhoto(version: version, id: UUID(), title: "Synthetic phone photo",
            created: Date(timeIntervalSince1970: 1_700_000_000), sourceDevice: "iPhone",
            digest: String(repeating: "a", count: 64), byteCount: 1234, width: 80, height: 40)
    }

    private func record(_ photo: RemoteHandoffPhoto, owner: String, zone: String = "WorkbenchPhotosV1",
                        type: String = "PhotoV1", id: UUID? = nil) throws -> CKRecord {
        let zoneID = CKRecordZone.ID(zoneName: zone, ownerName: owner)
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: (id ?? photo.id).uuidString, zoneID: zoneID))
        record["metadata"] = try JSONEncoder().encode(photo) as NSData
        return record
    }

    func testCurrentUserZoneResponseRoundTripMatchesExplicitOwnerResponse() throws {
        let photo = photo()
        for owner in [account.userRecordName, CKCurrentUserDefaultName] {
            let original = try record(photo, owner: owner)
            // Real SDK value bridging and secure coding, with no container or network.
            let bytes = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
            let response = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: bytes))
            XCTAssertEqual(response.recordID.zoneID.ownerName, owner)
            XCTAssertEqual(try JSONDecoder().decode(RemoteHandoffPhoto.self,
                from: XCTUnwrap(response["metadata"] as? Data)), photo)
            XCTAssertEqual(try CloudPhotoTransport.decode(response, account: account), photo)
        }
        XCTAssertNotEqual(account.userRecordName, CKCurrentUserDefaultName)
        XCTAssertNoThrow(try account.validate())
    }

    func testCurrentUserAliasIsNotAcceptedAsDurableAccountIdentity() throws {
        let record = try record(photo(), owner: CKCurrentUserDefaultName)
        for owner in [CKCurrentUserDefaultName, "_defaultOwner", ""] {
            let unsafe = PhotoAccount(container: account.container, environment: account.environment, userRecordName: owner)
            XCTAssertThrowsError(try unsafe.validate())
            XCTAssertThrowsError(try CloudPhotoTransport.decode(record, account: unsafe))
        }
    }

    func testOtherOwnerZoneAndRecordTypeRemainRejected() throws {
        let photo = photo()
        let wrongOwner = try record(photo, owner: "_fedcba9876543210fedcba9876543210")
        let wrongZone = try record(photo, owner: CKCurrentUserDefaultName, zone: "OtherPhotosV1")
        let wrongType = try record(photo, owner: CKCurrentUserDefaultName, type: "OtherRecordV1")
        for response in [wrongOwner, wrongZone, wrongType] {
            XCTAssertThrowsError(try CloudPhotoTransport.decode(response, account: account))
        }
    }

    func testDeletionResponsesAcceptCurrentUserAliasButKeepZoneAndOwnerBoundary() throws {
        let photo = photo()
        for owner in [account.userRecordName, CKCurrentUserDefaultName] {
            let response = try record(photo, owner: owner)
            XCTAssertEqual(try CloudPhotoTransport.deletedPhotoID(response.recordID,
                recordType: response.recordType, account: account), photo.id)
        }
        let wrongOwner = try record(photo, owner: "_fedcba9876543210fedcba9876543210")
        let wrongZone = try record(photo, owner: CKCurrentUserDefaultName, zone: "OtherPhotosV1")
        let wrongType = try record(photo, owner: CKCurrentUserDefaultName, type: "OtherRecordV1")
        for response in [wrongOwner, wrongZone, wrongType] {
            XCTAssertThrowsError(try CloudPhotoTransport.deletedPhotoID(response.recordID,
                recordType: response.recordType, account: account))
        }
        let zone = CKRecordZone.ID(zoneName: "WorkbenchPhotosV1", ownerName: CKCurrentUserDefaultName)
        XCTAssertThrowsError(try CloudPhotoTransport.deletedPhotoID(CKRecord.ID(recordName: "not-a-photo-id", zoneID: zone),
            recordType: "PhotoV1", account: account))
    }

    func testMalformedMetadataFutureVersionAndMismatchedIDRemainRejected() throws {
        let photo = photo()
        let missing = try record(photo, owner: CKCurrentUserDefaultName); missing["metadata"] = nil
        let wrongType = try record(photo, owner: CKCurrentUserDefaultName); wrongType["metadata"] = "not data" as NSString
        let malformed = try record(photo, owner: CKCurrentUserDefaultName); malformed["metadata"] = Data("{".utf8) as NSData
        let oversized = try record(photo, owner: CKCurrentUserDefaultName); oversized["metadata"] = Data(repeating: 32, count: 16_001) as NSData
        let future = try record(self.photo(version: 2), owner: CKCurrentUserDefaultName)
        let mismatch = try record(photo, owner: CKCurrentUserDefaultName, id: UUID())
        for response in [missing, wrongType, malformed, oversized, future, mismatch] {
            XCTAssertThrowsError(try CloudPhotoTransport.decode(response, account: account))
        }
    }
}
