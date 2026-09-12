import AppKit

/// Screen proportions belong to the viewport. The frame is measured outwards
/// from it, so a live feed and the inner rounded edge agree at every size.
struct DeviceViewport: Codable, Equatable {
    var aspect = 9.0 / 19.5
    var border = 0.009
    var corners = 0.10
    static let phone = DeviceViewport()
    static let tablet = DeviceViewport(aspect: 3.0 / 4.0, border: 0.012, corners: 0.035)
    static let landscape = DeviceViewport(aspect: 4.0 / 3.0, border: 0.012, corners: 0.035)
    // Preserve the old outer proportions when decoding an existing scene.
    static let legacy = DeviceViewport(aspect: (0.485 - 0.024) / 0.976, border: 0.012, corners: 0.105)
    func validated() throws -> DeviceViewport {
        guard [aspect, border, corners].allSatisfy(\.isFinite) else { throw SceneError.invalidScene }
        return DeviceViewport(aspect: min(2.4, max(0.3, aspect)),
                              border: min(0.035, max(0.003, border)), corners: min(0.3, max(0, corners)))
    }
}

struct ViewportGeometry {
    /// Size describes the outer border, so 100% reaches both canvas edges
    /// without cropping the frame or enlarging the live screen past its bezel.
    static let heightRange = 0.3...1.0
    let outer: CGRect
    let screen: CGRect
    let border: CGFloat
    let innerRadius: CGFloat
    var outerRadius: CGFloat { innerRadius + border }
    init(scene: DemoScene, size: CGSize) {
        let device = scene.viewport ?? .legacy
        let fraction = min(Self.heightRange.upperBound, max(Self.heightRange.lowerBound, scene.phoneHeight))
        var height = size.height * fraction
        var border = height * device.border
        var width = (height - 2 * border) * device.aspect + 2 * border
        let fit = min(1, size.width * 0.96 / max(1, width))
        height *= fit; width *= fit; border *= fit
        self.border = border
        outer = CGRect(x: (size.width - width) * scene.phoneX, y: (size.height - height) * scene.phoneY,
                       width: width, height: height)
        screen = outer.insetBy(dx: border, dy: border)
        innerRadius = min(screen.width, screen.height) * device.corners
    }
}

/// A separate entry for each picture chain; a physical monitor may host many
/// Spaces. Public AppKit cannot reliably identify or switch arbitrary Spaces.
enum DesktopRecovery {
    static func plan(_ snapshots: [DesktopSnapshot], current: [String: URL]) -> (ready: [DesktopSnapshot], retained: [DesktopSnapshot]) {
        (snapshots.filter { $0.owns(current[$0.screenID]) }, snapshots.filter { !$0.owns(current[$0.screenID]) })
    }
    static func matchingIndex(_ snapshots: [DesktopSnapshot], screenID: String, current: URL?) -> Int? {
        snapshots.lastIndex { $0.screenID == screenID && $0.owns(current) }
    }
    static func preparing(_ snapshots: [DesktopSnapshot], screenID: String, current: URL?,
                          output: URL, original: DesktopSnapshot) -> [DesktopSnapshot] {
        var result = snapshots
        if let index = matchingIndex(result, screenID: screenID, current: current),
           let next = result[index].preparingSwitch(to: output, current: current) {
            result[index] = next
        } else {
            result.append(original)
        }
        return result
    }
}
