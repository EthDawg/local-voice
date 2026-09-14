import XCTest
import UIKit
@testable import WorkbenchMobile

@MainActor final class SceneMotionPreviewTests: XCTestCase {
    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60), format: format).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
    }
    func testOnlyPhotoLayerAnimatesAndStoppingRestoresAuthoredCrop() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let view = SceneMotionPhotoView(frame: window.bounds)
        let foreground = CALayer(); foreground.frame = CGRect(x: 20, y: 30, width: 40, height: 50)
        window.layer.addSublayer(foreground); window.addSubview(view)
        view.configure(image: image(), x: 0.25, y: 0.8, zoom: 1.5, playing: true)
        let authored = CGRect(x: -40, y: -36, width: 480, height: 360)
        XCTAssertEqual(view.photoLayer.frame.minX, authored.minX, accuracy: 0.0001)
        XCTAssertEqual(view.photoLayer.frame.minY, authored.minY, accuracy: 0.0001)
        XCTAssertEqual(view.photoLayer.frame.size, authored.size)
        let animation = try XCTUnwrap(view.photoLayer.animation(forKey: GentlePhotoMotion.animationKey) as? CABasicAnimation)
        XCTAssertEqual(animation.keyPath, "transform.scale")
        XCTAssertNil(foreground.animationKeys()); XCTAssertEqual(foreground.frame, CGRect(x: 20, y: 30, width: 40, height: 50))
        XCTAssertNil(view.layer.animationKeys())
        view.configure(image: image(), x: 0.25, y: 0.8, zoom: 1.5, playing: false)
        XCTAssertNil(view.photoLayer.animationKeys()); XCTAssertTrue(CATransform3DIsIdentity(view.photoLayer.transform))
        XCTAssertEqual(view.photoLayer.frame.minY, authored.minY, accuracy: 0.0001)
        XCTAssertEqual(view.photoLayer.frame.size, authored.size)
        view.removeFromSuperview()
    }
    func testDetachAndDismantleRemoveAnimationButReattachCanResumeEligiblePreview() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let view = SceneMotionPhotoView(frame: window.bounds)
        view.configure(image: image(), x: 0.5, y: 0.5, zoom: 1, playing: true)
        XCTAssertNil(view.photoLayer.animationKeys())
        window.addSubview(view); XCTAssertNotNil(view.photoLayer.animation(forKey: GentlePhotoMotion.animationKey))
        view.removeFromSuperview(); XCTAssertNil(view.photoLayer.animationKeys())
        window.addSubview(view); XCTAssertNotNil(view.photoLayer.animation(forKey: GentlePhotoMotion.animationKey))
        SceneMotionPreview.dismantleUIView(view, coordinator: ())
        view.setNeedsLayout(); view.layoutIfNeeded()
        XCTAssertNil(view.photoLayer.animationKeys())
        view.removeFromSuperview()
    }
    func testCropMathUsesUnflippedSceneCoordinatesAcrossPortraitAndResize() {
        let bottom = SceneMotionPhotoView.authoredFrame(imageSize: CGSize(width: 100, height: 200), canvas: CGSize(width: 300, height: 200), x: 0, y: 0, zoom: 1)
        XCTAssertEqual(bottom, CGRect(x: 0, y: -400, width: 300, height: 600))
        let top = SceneMotionPhotoView.authoredFrame(imageSize: CGSize(width: 100, height: 200), canvas: CGSize(width: 300, height: 200), x: 1, y: 1, zoom: 1)
        XCTAssertEqual(top, CGRect(x: 0, y: 0, width: 300, height: 600))
        let empty = SceneMotionPhotoView.authoredFrame(imageSize: .zero, canvas: CGSize(width: 300, height: 200), x: 0.5, y: 0.5, zoom: 1)
        XCTAssertEqual(empty, .zero)
    }
    func testLifecycleSuspensionsKeepAuthoredRequestAndResumeOnlyWhenAllEligible() {
        var state = SceneMotionPlayback(requested: true, visible: true, active: true)
        XCTAssertTrue(state.isPlaying)
        state.active = false; XCTAssertFalse(state.isPlaying); state.active = true
        state.visible = false; XCTAssertFalse(state.isPlaying); state.visible = true
        state.editingCrop = true; XCTAssertFalse(state.isPlaying); state.editingCrop = false
        state.reduceMotion = true; XCTAssertFalse(state.isPlaying); state.reduceMotion = false
        state.lowPower = true; XCTAssertFalse(state.isPlaying); state.lowPower = false
        state.thermalState = .serious; XCTAssertFalse(state.isPlaying)
        state.thermalState = .critical; XCTAssertFalse(state.isPlaying)
        state.thermalState = .fair; XCTAssertTrue(state.isPlaying)
        state.paused = true; state.active = false; state.active = true
        XCTAssertFalse(state.isPlaying); XCTAssertTrue(state.requested)
        state.paused = false; XCTAssertTrue(state.isPlaying)
        state.requested = false; XCTAssertFalse(state.isPlaying)
    }
}
