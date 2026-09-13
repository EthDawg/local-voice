import UIKit
import Combine

enum MobileQuickAction: String, CaseIterable {
    case captureScene = "com.ethdawg.workbench.capture-scene"
    case dictate = "com.ethdawg.workbench.dictate"
}

/// Cold and warm launches feed one queue. The foreground view consumes it once;
/// receiving an action cannot itself start a camera or microphone session.
@MainActor final class MobileQuickActionRouter: ObservableObject {
    static let shared = MobileQuickActionRouter()
    @Published private(set) var pending: MobileQuickAction?
    @discardableResult func receive(type: String) -> Bool {
        guard let action = MobileQuickAction(rawValue: type) else { return false }
        pending = action; return true
    }
    func take(isActive: Bool) -> MobileQuickAction? {
        guard isActive else { return nil }
        defer { pending = nil }
        return pending
    }
}

final class MobileApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = MobileQuickActionSceneDelegate.self
        return configuration
    }
}

final class MobileQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            _ = MobileQuickActionRouter.shared.receive(type: item.type)
        }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(MobileQuickActionRouter.shared.receive(type: shortcutItem.type))
    }
}
