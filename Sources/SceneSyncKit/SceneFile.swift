import Foundation
import UniformTypeIdentifiers

/// One portable file format for explicit copies, independent of the sync provider.
public enum SceneFile {
    public static let contentType = UTType(exportedAs: "com.ethdawg.workbench.scene", conformingTo: .data)
    public static let fileExtension = "workbenchscene"

    public static func read(_ url: URL) throws -> Data {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              let size = (values[.size] as? NSNumber)?.intValue,
              size > 0, size <= ScenePackage.maximumBytes else {
            throw SceneDocumentError.invalid("Choose a Workbench scene file under 100 MB.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let bytes = try handle.read(upToCount: ScenePackage.maximumBytes + 1),
              bytes.count <= ScenePackage.maximumBytes else {
            throw SceneDocumentError.invalid("This scene file is too large to open safely.")
        }
        return bytes
    }
}
