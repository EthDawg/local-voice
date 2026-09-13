#!/usr/bin/env python3
"""Build, but never launch, an isolated Mac photo-handoff QA app.

Compiles exact snapshots of the production view and PhotoHandoffKit. The visible
host uses an injected in-memory transport, a fresh library for each launch, and
no real iCloud, clipboard, microphone, scene or user-library access. Save a copy
remains the production user-invoked save panel. An optional --image must name a
known synthetic asset inside this repository; otherwise native rectangles are
generated. Build output and source hashes are retained for review.
"""

import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
VIEW = ROOT / "Sources/LocalVoice/PhotoHandoffView.swift"
MODULE = ROOT / "Sources/PhotoHandoffKit"

HOST = r'''
import AppKit
import Combine
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
@testable import PhotoHandoffKit

// Only the app palette is supplied by this host. View and model logic are exact
// source snapshots; Workbench's normal singleton/settings are never created.
enum Workbench {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.43, green: 0.89, blue: 0.73, alpha: 1)
            : NSColor(srgbRed: 0.04, green: 0.43, blue: 0.32, alpha: 1)
    })
}

@MainActor final class SimulatedPhotoTransport: PhotoHandoffTransport {
    let configuration = PhotoCloudConfiguration(isConfigured: true,
        container: "iCloud.com.example.workbench.fixture", environment: "Development",
        explanation: "Simulated arrival · no iCloud")
    var onAccountChange: (@MainActor @Sendable () -> Void)?
    let account = PhotoAccount(container: "iCloud.com.example.workbench.fixture",
        environment: "Development", userRecordName: "synthetic-qa-account")
    var offline = false
    var item: (RemoteHandoffPhoto, Data)?
    private func available(_ owner: PhotoAccount? = nil) throws {
        try Task.checkCancellation()
        if offline { throw PhotoHandoffError.unavailable("Simulated offline failure. The downloaded photo is still available locally. No network request was made.") }
        if let owner, owner != account { throw PhotoHandoffError.accountChanged }
    }
    func identity() async throws -> PhotoAccount { try available(); return account }
    func upload(_ photo: RemoteHandoffPhoto, fileURL: URL, account: PhotoAccount) async throws {
        throw PhotoHandoffError.unavailable("This inspection app never uploads photos.")
    }
    func changes(after checkpoint: Data?, account: PhotoAccount) async throws -> PhotoChangePage {
        try available(account)
        return PhotoChangePage(photos: item.map { [$0.0] } ?? [], checkpoint: Data("fixture-page-1".utf8))
    }
    func download(_ photo: RemoteHandoffPhoto, account: PhotoAccount) async throws -> Data {
        try available(account)
        guard let item, item.0 == photo else { throw PhotoHandoffError.invalid("The simulated photo is unavailable.") }
        return item.1
    }
    func remove(_ id: UUID, account: PhotoAccount) async throws {
        throw PhotoHandoffError.unavailable("This inspection app does not remove cloud records.")
    }
    func cancel() { }
}

enum FixtureImage {
    static func data() throws -> Data {
        if let file = Bundle.main.url(forResource: "SyntheticInput", withExtension: "bin") {
            return try Data(contentsOf: file)
        }
        guard let context = CGContext(data: nil, width: 1200, height: 800,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw PhotoHandoffError.invalid("Could not create the native synthetic image.")
        }
        context.setFillColor(CGColor(red: 0.91, green: 0.93, blue: 0.91, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        context.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 90, y: 100, width: 1020, height: 610))
        context.setFillColor(CGColor(red: 0.08, green: 0.45, blue: 0.35, alpha: 1))
        context.fill(CGRect(x: 155, y: 560, width: 540, height: 35))
        context.fill(CGRect(x: 155, y: 460, width: 350, height: 16))
        context.fill(CGRect(x: 155, y: 410, width: 445, height: 16))
        context.fill(CGRect(x: 155, y: 360, width: 280, height: 16))
        context.setFillColor(CGColor(red: 0.92, green: 0.70, blue: 0.31, alpha: 1))
        context.fill(CGRect(x: 740, y: 290, width: 215, height: 210))
        context.setFillColor(CGColor(red: 0.53, green: 0.69, blue: 0.80, alpha: 1))
        context.fill(CGRect(x: 440, y: 175, width: 215, height: 110))
        guard let image = context.makeImage() else { throw PhotoHandoffError.invalid("No synthetic image was rendered.") }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoHandoffError.invalid("Could not encode the synthetic JPEG.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoHandoffError.invalid("Synthetic JPEG encoding failed.") }
        return bytes as Data
    }
}

@MainActor final class FixtureController: ObservableObject {
    let transport: SimulatedPhotoTransport
    let model: PhotoHandoffModel
    @Published var log = "Empty receiving library. Inject a synthetic JPEG to inspect a normal arrival."
    @Published var injected = false
    @Published var backdrop: PhotoBackdropRequest?

    init() {
        let base = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "FixtureOutputDirectory") as! String, isDirectory: true)
        let directory = base.appendingPathComponent("Libraries", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let transport = SimulatedPhotoTransport()
        self.transport = transport
        // An explicit transport bypasses the real CloudPhotoTransport entirely.
        // No production application support path or saved settings are used.
        model = PhotoHandoffModel(directory: directory, platform: "Mac QA fixture", transport: transport)
    }
    func inject() async {
        guard !model.isBusy, !injected else { return }
        do {
            let prepared = try PhotoMedia.prepare(FixtureImage.data())
            let photo = RemoteHandoffPhoto(id: UUID(), title: "Synthetic whiteboard photo",
                created: Date(timeIntervalSince1970: 1_800_230_400), sourceDevice: "iPhone · synthetic fixture",
                digest: prepared.digest, byteCount: prepared.jpeg.count, width: prepared.width, height: prepared.height)
            transport.item = (photo, prepared.jpeg); transport.offline = false
            if model.isEnabled { await model.refresh() } else { await model.enable() }
            injected = model.photos.contains { $0.id == photo.id }
            log = injected ? "Simulated JPEG downloaded through the real model and local store. No iCloud was used."
                : "The production model rejected the simulated arrival: " + (model.error ?? model.status)
        } catch { log = error.localizedDescription }
    }
    func setOffline(_ offline: Bool) async {
        guard !model.isBusy else { return }
        transport.offline = offline
        if model.isEnabled { await model.refresh() } else { await model.enable() }
        log = offline ? "Offline failure is simulated. The real view still uses its committed local copy."
            : "Simulated connection restored. Refresh replay uses the same photo ID; no new copy is inserted."
    }
    func previewBackdrop(_ url: URL, _ title: String) {
        log = "Simulated backdrop callback received. No saved scene, presentation or wallpaper was changed."
        backdrop = PhotoBackdropRequest(url: url, title: title)
    }
}

@MainActor struct FixtureRoot: View {
    @ObservedObject var fixture: FixtureController
    @ObservedObject var model: PhotoHandoffModel
    init(fixture: FixtureController) { self.fixture = fixture; model = fixture.model }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Simulated arrival · no iCloud", systemImage: "testtube.2")
                    .font(.headline).foregroundStyle(.orange)
                HStack {
                    Button("Inject one JPEG") { Task { await fixture.inject() } }
                        .disabled(model.isBusy || fixture.injected).accessibilityIdentifier("fixture.inject")
                    Button("Simulate offline") { Task { await fixture.setOffline(true) } }
                        .disabled(model.isBusy).accessibilityIdentifier("fixture.offline")
                    Button("Restore connection") { Task { await fixture.setOffline(false) } }
                        .disabled(model.isBusy).accessibilityIdentifier("fixture.online")
                    Spacer()
                    Text("Disposable library · simulated backdrop").font(.caption).foregroundStyle(.secondary)
                }
                Text(fixture.log).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("fixture.log")
            }.padding(14).background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            PhotoHandoffView(handoff: model, onUseAsBackdrop: fixture.previewBackdrop)
        }.padding(22).frame(minWidth: 900, minHeight: 770)
            .sheet(item: $fixture.backdrop) { request in
                VStack(alignment: .leading, spacing: 18) {
                    Label("Simulated backdrop preview", systemImage: "testtube.2").font(.title2)
                    Text(request.title).font(.headline)
                    Text("The real photo view passed its validated local JPEG to this callback. This QA app stops here: it does not open StageKit or edit a scene.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Close simulated preview") { fixture.backdrop = nil }.keyboardShortcut(.cancelAction)
                }.padding(26).frame(width: 480)
            }
    }
}

@main @MainActor struct PhotoHandoffQAApp: App {
    @StateObject private var fixture = FixtureController()
    var body: some Scene {
        WindowGroup("Workbench Photo Handoff QA") { FixtureRoot(fixture: fixture) }
            .defaultSize(width: 1100, height: 850)
    }
}
'''


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New or empty directory; defaults to a private temporary directory.")
    parser.add_argument("--image", type=Path, help="Optional known synthetic image inside this repository.")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("The disposable native app requires macOS and Xcode.")
    image = None
    if args.image:
        image = args.image.resolve(strict=True)
        if not image.is_relative_to(ROOT) or not image.is_file() or image.suffix.lower() not in (".png", ".jpg", ".jpeg", ".heic"):
            parser.error("--image must name a known synthetic PNG/JPEG/HEIC file inside this repository.")
        if not 0 < image.stat().st_size <= 64_000_000:
            parser.error("The synthetic image must be within the production 64 MB input limit.")
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="workbench-photo-handoff-ui-", dir="/private/tmp"))
    if output.exists() and any(output.iterdir()):
        parser.error("--output must be empty; this script never replaces a prior fixture.")
    output.mkdir(parents=True, exist_ok=True)
    source_dir = output / "Sources"
    source_dir.mkdir()
    shared_dir = source_dir / "PhotoHandoffKit"
    shared_dir.mkdir()
    hashes = {}
    sources = []
    for source in sorted(MODULE.glob("*.swift")) + [VIEW]:
        destination = (shared_dir if source.parent == MODULE else source_dir) / source.name
        data = source.read_bytes()
        destination.write_bytes(data)
        hashes[str(source.relative_to(ROOT))] = hashlib.sha256(data).hexdigest()
        if source.parent == MODULE:
            sources.append(destination)
    host = source_dir / "FixtureApp.swift"
    host.write_text(HOST)
    app = output / "Workbench Photo Handoff QA.app"
    contents = app / "Contents"
    executable = contents / "MacOS/PhotoHandoffQA"
    frameworks = contents / "Frameworks"
    resources = contents / "Resources"
    for directory in (executable.parent, frameworks, resources, output / "Modules", output / "ModuleCache"):
        directory.mkdir(parents=True)
    if image:
        shutil.copyfile(image, resources / "SyntheticInput.bin")
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleIdentifier": "com.example.workbench.photo-handoff-qa",
            "CFBundleExecutable": executable.name, "CFBundleName": "Workbench Photo Handoff QA",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
            "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True,
            "WorkbenchPhotoCloudProvisioned": False, "FixtureOutputDirectory": str(output)}, stream)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    target = f"{platform.machine()}-apple-macosx14.0"
    common = ["xcrun", "swiftc", "-swift-version", "5", "-sdk", sdk,
              "-target", target, "-module-cache-path", output / "ModuleCache"]
    library = frameworks / "libPhotoHandoffKit.dylib"
    run(*common, "-parse-as-library", "-enable-testing", "-emit-module", "-emit-library",
        "-module-name", "PhotoHandoffKit", "-emit-module-path", output / "Modules/PhotoHandoffKit.swiftmodule",
        "-Xlinker", "-install_name", "-Xlinker", "@rpath/libPhotoHandoffKit.dylib",
        *sources, "-o", library)
    run(*common, "-parse-as-library", "-I", output / "Modules", "-L", frameworks, "-lPhotoHandoffKit",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        host, source_dir / VIEW.name, "-o", executable)
    run("codesign", "--force", "--sign", "-", library)
    run("codesign", "--force", "--sign", "-", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    (output / "SourceManifest.json").write_text(json.dumps({"productionSourceSHA256": hashes,
        "image": str(image.relative_to(ROOT)) if image else "Native generated rectangles",
        "target": target, "app": str(app), "launched": False,
        "scope": "Synthetic transport and temporary local state; backdrop callback simulated."}, indent=2) + "\n")
    (output / "README.txt").write_text(
        "Disposable Workbench photo-handoff inspection app. Built, not launched.\n"
        "1. Open the app manually; the receiving library begins empty.\n"
        "2. Inject one JPEG to inspect the production downloaded state.\n"
        "3. Simulate offline, then Restore connection; the local photo remains usable.\n"
        "4. Use as backdrop opens a clearly simulated callback sheet only.\n"
        "The real Save a copy button opens a native user-chosen save panel.\n"
        "Each launch uses a new library retained under Libraries. No cloud or clipboard is used.\n"
        "SourceManifest.json records the exact production sources compiled.\n")
    print(json.dumps({"built": str(app), "sourceManifest": str(output / "SourceManifest.json"),
                      "launched": False, "cloud": "Injected synthetic transport only"}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Photo handoff fixture build failed: {error}", file=sys.stderr)
        raise SystemExit(1)
