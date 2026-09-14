import Foundation

public struct PhotoAccount: Codable, Equatable, Hashable, Sendable {
    public let container: String
    public let environment: String
    public let userRecordName: String
    public init(container: String, environment: String, userRecordName: String) {
        self.container = container; self.environment = environment; self.userRecordName = userRecordName
    }
    func validate() throws {
        guard container.hasPrefix("iCloud."), container.count <= 200,
              ["Development", "Production"].contains(environment),
              !userRecordName.isEmpty, userRecordName.count <= 255,
              !["__defaultOwner__", "_defaultOwner"].contains(userRecordName),
              userRecordName.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.controlCharacters.contains($0) })
        else { throw PhotoHandoffError.invalid("The iCloud account could not be identified safely.") }
    }
}

enum PhotoDisposition: String, Codable, Sendable {
    case local, queued, uploaded, downloaded, deleting, removed
}

public struct HandoffPhoto: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let created: Date
    public let sourceDevice: String
    public var isUploaded: Bool { disposition == .uploaded || disposition == .downloaded }
    public var statusLabel: String {
        if let transientStatus { return transientStatus }
        switch disposition {
        case .local: return "Only on this device"
        case .queued: return "Queued for iCloud"
        case .uploaded: return "In iCloud"
        case .downloaded: return "Downloaded on this device"
        case .deleting: return "Removal queued"
        case .removed: return "Removed from iCloud · local copy kept"
        }
    }
    var account: PhotoAccount?
    var disposition: PhotoDisposition
    let digest: String
    let byteCount: Int
    let width: Int
    let height: Int
    let hasOriginal: Bool
    var transientStatus: String? = nil
    enum CodingKeys: String, CodingKey {
        case id, title, created, sourceDevice, account, disposition, digest, byteCount, width, height, hasOriginal
    }
    var remote: RemoteHandoffPhoto {
        RemoteHandoffPhoto(id: id, title: title, created: created, sourceDevice: sourceDevice,
                           digest: digest, byteCount: byteCount, width: width, height: height)
    }
}

public struct RemoteHandoffPhoto: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let title: String
    public let created: Date
    public let sourceDevice: String
    public let digest: String
    public let byteCount: Int
    public let width: Int
    public let height: Int
    public init(version: Int = 1, id: UUID, title: String, created: Date, sourceDevice: String,
                digest: String, byteCount: Int, width: Int, height: Int) {
        self.version = version; self.id = id; self.title = title; self.created = created
        self.sourceDevice = sourceDevice; self.digest = digest; self.byteCount = byteCount
        self.width = width; self.height = height
    }
    public func validated() throws -> Self {
        guard version == 1, !title.isEmpty, title.count <= 160, sourceDevice.count <= 80,
              created.timeIntervalSince1970.isFinite,
              digest.count == 64, digest.allSatisfy({ "0123456789abcdef".contains($0) }),
              byteCount > 0, byteCount <= PhotoMedia.maximumTransferBytes,
              width > 0, height > 0, width <= 3840, height <= 3840
        else { throw PhotoHandoffError.invalid("A handoff photo is damaged or uses an unsupported version. Refresh after the source is repaired.") }
        return self
    }
}

public struct PhotoChangePage: Sendable {
    public let photos: [RemoteHandoffPhoto]
    public let deletedIDs: [UUID]
    public let checkpoint: Data?
    public let hasMore: Bool
    public init(photos: [RemoteHandoffPhoto], deletedIDs: [UUID] = [], checkpoint: Data? = nil, hasMore: Bool = false) {
        self.photos = photos; self.deletedIDs = deletedIDs; self.checkpoint = checkpoint; self.hasMore = hasMore
    }
}

public struct PhotoCloudConfiguration: Sendable {
    public let isConfigured: Bool
    public let container: String
    public let environment: String
    public let explanation: String
    public init(isConfigured: Bool, container: String = "iCloud.com.ethdawg.workbench.preview",
                environment: String = "Development", explanation: String = "") {
        self.isConfigured = isConfigured; self.container = container
        self.environment = environment; self.explanation = explanation
    }
}

@MainActor public protocol PhotoHandoffTransport: AnyObject {
    var configuration: PhotoCloudConfiguration { get }
    var onAccountChange: (@MainActor @Sendable () -> Void)? { get set }
    func identity() async throws -> PhotoAccount
    func upload(_ photo: RemoteHandoffPhoto, fileURL: URL, account: PhotoAccount) async throws
    func changes(after checkpoint: Data?, account: PhotoAccount) async throws -> PhotoChangePage
    func download(_ photo: RemoteHandoffPhoto, account: PhotoAccount) async throws -> Data
    func remove(_ id: UUID, account: PhotoAccount) async throws
    func cancel()
}

public enum PhotoHandoffError: LocalizedError, Sendable {
    case invalid(String), unavailable(String), accountChanged, cancelled, timeout
    case retryAfter(Date, String), expiredCheckpoint
    public var errorDescription: String? {
        switch self {
        case .invalid(let text), .unavailable(let text): return text
        case .accountChanged: return "Your iCloud account changed. Reconnect deliberately; photos queued for the previous account stay there."
        case .cancelled: return "Photo transfer stopped. Local photos are kept."
        case .timeout: return "iCloud took too long to respond. Your local photo is kept; try again later."
        case .retryAfter(_, let text): return text
        case .expiredCheckpoint: return "The iCloud refresh position expired. Refresh again to safely rebuild the photo list."
        }
    }
}
