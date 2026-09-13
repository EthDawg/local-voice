import AppKit
import SwiftUI

/// Opt-in UI fixture using the real scene editor and bundled resources. Every
/// scene/image write is isolated to a fresh temporary folder; system actions
/// are disabled and no AppCoordinator/global shortcuts are started.
@MainActor
final class BackdropReplacementFixture: NSObject, NSApplicationDelegate {
    private var root: URL?
    private var model: DemoScenes?
    private var window: NSWindow?
    func run() {
        do {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("WorkbenchBackdropFixture-" + UUID().uuidString)
            root = temporary
            let library = temporary.appendingPathComponent("Scenes"), imports = temporary.appendingPathComponent("Imports")
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
            try backdrop(top: .systemTeal, bottom: .darkGray, size: CGSize(width: 1600, height: 1000)).write(to: library.appendingPathComponent("teal.png"))
            try backdrop(top: .systemIndigo, bottom: .black, size: CGSize(width: 1600, height: 900)).write(to: library.appendingPathComponent("indigo.png"))
            try backdrop(top: .systemOrange, bottom: .systemRed, size: CGSize(width: 700, height: 1200)).write(to: imports.appendingPathComponent("Portrait candidate.png"))
            try backdrop(top: .systemBlue, bottom: .systemPurple, size: CGSize(width: 2000, height: 700)).write(to: imports.appendingPathComponent("Wide candidate.png"))
            try artwork("SAMPLE CO", size: CGSize(width: 360, height: 100), color: .white).write(to: library.appendingPathComponent("logo.png"))
            try artwork("Morgan\nDemo persona", size: CGSize(width: 280, height: 220), color: .systemYellow).write(to: library.appendingPathComponent("persona.png"))
            var customer = DemoScene(name: "Customer layout — replace its backdrop", background: "teal.png")
            customer.backgroundX = 0.25; customer.backgroundY = 0.65; customer.zoom = 1.2
            customer.phoneX = 0.4; customer.phoneHeight = 0.8
            customer.logo = SceneLogo(image: "logo.png"); customer.logo!.corner = .topLeft
            customer.persona = PersonaPlacement(image: "persona.png", x: 0.97, y: 0.08, width: 0.2)
            var duplicate = customer; duplicate.id = UUID(); duplicate.name = "Shared original — must stay unchanged"
            var another = customer; another.id = UUID(); another.name = "Indigo backdrop to reuse"; another.background = "indigo.png"
            var missing = customer; missing.id = UUID(); missing.name = "Missing backdrop — repair this scene"; missing.background = "missing.png"
            try SceneStorage.save([customer, duplicate, another, missing], to: library.appendingPathComponent("scenes.json"))
            let scenes = DemoScenes(root: library, systemIntegrationEnabled: false)
            model = scenes
            NSApp.delegate = self
            NSApp.setActivationPolicy(.regular); NSApp.finishLaunching()
            let menu = NSMenu(), applicationItem = NSMenuItem()
            menu.addItem(applicationItem)
            let applicationMenu = NSMenu(title: "Fixture")
            let quit = NSMenuItem(title: "Quit Backdrop Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp; applicationMenu.addItem(quit); applicationItem.submenu = applicationMenu
            NSApp.mainMenu = menu
            let panel = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1140, height: 800),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Workbench Backdrop Fixture · Temporary scenes"
            panel.minSize = CGSize(width: 850, height: 680); panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: DemoScenesView(model: scenes))
            window = panel
            scenes.onOpen = { [weak self] in self?.window?.makeKeyAndOrderFront(nil) }
            print("Backdrop fixture root: \(temporary.path)")
            print("Choose image candidates: \(imports.path)")
            print("Bundled starters: \(SceneStarters.directory.path)")
            panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            NSApp.run()
        } catch { print("Fixture could not open: \(error.localizedDescription)"); cleanup() }
    }
    private func backdrop(top: NSColor, bottom: NSColor, size: CGSize) throws -> Data {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: bottom, ending: top)?.draw(in: rect, angle: 90)
            NSColor.white.withAlphaComponent(0.14).setFill()
            CGRect(x: rect.width * 0.12, y: 0, width: rect.width * 0.13, height: rect.height).fill()
            CGRect(x: rect.width * 0.72, y: 0, width: rect.width * 0.08, height: rect.height).fill()
            return true
        }
        var scene = DemoScene(background: "fixture.png"); scene.showsPhone = false
        return try SceneRenderer.png(scene, image: image, size: size)
    }
    private func artwork(_ text: String, size: CGSize, color: NSColor) throws -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill(); CGRect(origin: .zero, size: size).fill(using: .copy)
        color.setFill(); NSBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8), xRadius: 18, yRadius: 18).fill()
        (text as NSString).draw(in: CGRect(x: 25, y: 15, width: size.width - 50, height: size.height - 40),
            withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { cleanup() }
    private func cleanup() {
        model?.shutdown(); model = nil
        if let root { try? FileManager.default.removeItem(at: root) }
    }
}
