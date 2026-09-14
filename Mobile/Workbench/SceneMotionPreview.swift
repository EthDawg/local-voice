import SwiftUI
import UIKit
import QuartzCore

/// Transient editor playback, separate from the scene's authored preference.
struct SceneMotionPlayback {
    var requested = false
    var paused = false
    var editingCrop = false
    var visible = false
    var active = false
    var reduceMotion = false
    var lowPower = false
    var thermalState = ProcessInfo.ThermalState.nominal

    var isPlaying: Bool {
        GentlePhotoMotion.permitted(requested: requested && !paused && !editingCrop,
            visible: visible && active, reduceMotion: reduceMotion,
            lowPower: lowPower, thermalState: thermalState)
    }
    var explanation: String {
        if editingCrop { return "Preview stays still while you adjust the crop." }
        if paused { return "Preview paused. The saved scene still uses gentle motion." }
        if reduceMotion { return "Preview stays still because Reduce Motion is on." }
        if lowPower { return "Preview stays still in Low Power Mode." }
        if thermalState == .serious || thermalState == .critical { return "Preview stays still while your device cools down." }
        return "Only the backdrop moves. The device, logo and persona stay still."
    }
}

/// One decoded photo, animated by Core Animation. Sibling scene layers never
/// enter this view, and stopping returns to the exact authored crop.
struct SceneMotionPreview: UIViewRepresentable {
    let image: UIImage
    let x: Double
    let y: Double
    let zoom: Double
    let playing: Bool

    func makeUIView(context: Context) -> SceneMotionPhotoView { SceneMotionPhotoView() }
    func updateUIView(_ view: SceneMotionPhotoView, context: Context) {
        view.configure(image: image, x: x, y: y, zoom: zoom, playing: playing)
    }
    static func dismantleUIView(_ view: SceneMotionPhotoView, coordinator: ()) { view.stop() }
}

@MainActor final class SceneMotionPhotoView: UIView {
    let photoLayer = CALayer()
    private var imageSize = CGSize.zero
    private var cropX = 0.5, cropY = 0.5, zoom = 1.0
    private var playing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true; isUserInteractionEnabled = false; accessibilityElementsHidden = true
        photoLayer.contentsGravity = .resize
        layer.addSublayer(photoLayer)
    }
    required init?(coder: NSCoder) { nil }

    func configure(image: UIImage, x: Double, y: Double, zoom: Double, playing: Bool) {
        imageSize = image.size; cropX = x; cropY = y; self.zoom = zoom
        self.playing = playing
        CATransaction.begin(); CATransaction.setDisableActions(true)
        photoLayer.contents = image.cgImage
        CATransaction.commit()
        setNeedsLayout(); layoutIfNeeded(); updateAnimation()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        photoLayer.frame = Self.authoredFrame(imageSize: imageSize, canvas: bounds.size, x: cropX, y: cropY, zoom: zoom)
        CATransaction.commit()
        updateAnimation()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); updateAnimation() }

    static func authoredFrame(imageSize: CGSize, canvas: CGSize, x: Double, y: Double, zoom: Double) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = max(canvas.width / imageSize.width, canvas.height / imageSize.height) * zoom
        let width = imageSize.width * scale, height = imageSize.height * scale
        return CGRect(x: (canvas.width - width) * x, y: (canvas.height - height) * (1 - y), width: width, height: height)
    }
    private func updateAnimation() {
        guard playing, window != nil, !isHidden, bounds.width > 0, bounds.height > 0, photoLayer.contents != nil else {
            removeMotion(); return
        }
        if photoLayer.animation(forKey: GentlePhotoMotion.animationKey) == nil {
            photoLayer.add(GentlePhotoMotion.animation(), forKey: GentlePhotoMotion.animationKey)
        }
    }
    func stop() { playing = false; removeMotion() }
    private func removeMotion() {
        photoLayer.removeAnimation(forKey: GentlePhotoMotion.animationKey)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        photoLayer.transform = CATransform3DIdentity
        CATransaction.commit()
    }
}
