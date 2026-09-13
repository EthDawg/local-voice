import SwiftUI
import PencilKit

@MainActor final class MobileDrawingControls: ObservableObject {
    weak var canvas: PKCanvasView?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var exceedsLimit = false
    func setLimitExceeded(_ value: Bool) { exceedsLimit = value }
    func refresh() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }
    func undo() { canvas?.undoManager?.undo(); refresh() }
    func redo() { canvas?.undoManager?.redo(); refresh() }
}

struct MobileDrawingCanvas: UIViewRepresentable {
    let image: UIImage
    @Binding var data: Data?
    let toolsVisible: Bool
    let isEnabled: Bool
    let controls: MobileDrawingControls
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MobileDrawingSurface {
        let surface = MobileDrawingSurface()
        surface.canvas.delegate = context.coordinator
        context.coordinator.canvas = surface.canvas
        controls.canvas = surface.canvas
        context.coordinator.picker.addObserver(surface.canvas)
        surface.onWindow = { [weak coordinator = context.coordinator] in coordinator?.updateTools() }
        return surface
    }
    func updateUIView(_ surface: MobileDrawingSurface, context: Context) {
        context.coordinator.parent = self
        surface.imageView.image = image
        surface.logicalSize = MobileImageRenderer.logicalDrawingSize(image.size)
        surface.canvas.isUserInteractionEnabled = isEnabled
        let current = surface.canvas.drawing.dataRepresentation()
        if data != context.coordinator.lastData && data != current {
            do {
                context.coordinator.updating = true
                surface.canvas.drawing = try data.map(PKDrawing.init(data:)) ?? PKDrawing()
                context.coordinator.lastData = data
                context.coordinator.updating = false
            } catch { context.coordinator.updating = false; onError("This drawing could not be opened. Your original image is unchanged.") }
        }
        surface.setNeedsLayout()
        context.coordinator.updateTools()
    }
    static func dismantleUIView(_ surface: MobileDrawingSurface, coordinator: Coordinator) {
        coordinator.picker.setVisible(false, forFirstResponder: surface.canvas)
        coordinator.picker.removeObserver(surface.canvas)
        surface.canvas.resignFirstResponder()
        coordinator.parent.controls.canvas = nil
    }

    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: MobileDrawingCanvas
        weak var canvas: PKCanvasView?
        let picker = PKToolPicker()
        var lastData: Data?
        var updating = false
        private var toolsAreActive = false
        init(_ parent: MobileDrawingCanvas) { self.parent = parent }
        func updateTools() {
            guard let canvas else { return }
            let active = parent.toolsVisible && parent.isEnabled && canvas.window != nil
            // A Name edit or layout update must not reclaim the text field's focus.
            guard active != toolsAreActive else { return }
            toolsAreActive = active
            if active {
                canvas.becomeFirstResponder(); picker.setVisible(true, forFirstResponder: canvas)
            } else { picker.setVisible(false, forFirstResponder: canvas); canvas.resignFirstResponder() }
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !updating else { return }
            let next = canvasView.drawing.dataRepresentation()
            guard next.count <= 4_000_000 else {
                parent.controls.setLimitExceeded(true)
                parent.onError("This drawing is too large to save. Undo the last marks to continue. Your last saved drawing is unchanged.")
                parent.controls.refresh(); return
            }
            parent.controls.setLimitExceeded(false)
            lastData = next; parent.data = next
            DispatchQueue.main.async { [weak self] in self?.parent.controls.refresh() }
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { parent.controls.refresh() }
    }
}

final class MobileDrawingSurface: UIView {
    let imageView = UIImageView()
    let canvas = PKCanvasView()
    var logicalSize = CGSize(width: 1200, height: 800)
    var onWindow: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleToFill; imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput; canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.bounces = false; canvas.contentInset = .zero
        canvas.tool = PKInkingTool(.pen, color: .systemRed, width: 5)
        addSubview(canvas)
        accessibilityLabel = "Image drawing canvas"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds; canvas.frame = bounds
        guard bounds.width > 0, logicalSize.width > 0 else { return }
        let fit = bounds.width / logicalSize.width
        canvas.contentSize = logicalSize
        canvas.minimumZoomScale = min(fit, canvas.minimumZoomScale)
        canvas.maximumZoomScale = max(fit, canvas.maximumZoomScale)
        if abs(canvas.zoomScale - fit) > 0.0001 { canvas.zoomScale = fit }
        canvas.minimumZoomScale = fit; canvas.maximumZoomScale = fit
        canvas.contentOffset = .zero
    }
    override func didMoveToWindow() { super.didMoveToWindow(); onWindow?() }
}

struct MobileCompositionPreview: UIViewRepresentable {
    let project: MobileImageProject
    let background: UIImage
    var foreground: UIImage?
    var logo: UIImage?
    var persona: UIImage?
    func makeUIView(context: Context) -> MobileCompositionSurface { MobileCompositionSurface() }
    func updateUIView(_ view: MobileCompositionSurface, context: Context) {
        view.project = project; view.backgroundImage = background
        view.foreground = foreground; view.logo = logo; view.persona = persona; view.setNeedsDisplay()
    }
}

final class MobileCompositionSurface: UIView {
    var project: MobileImageProject?
    var backgroundImage: UIImage?
    var foreground: UIImage?
    var logo: UIImage?
    var persona: UIImage?
    override func draw(_ rect: CGRect) {
        guard let project, let backgroundImage else { return }
        MobileImageRenderer.draw(project: project, background: backgroundImage, foreground: foreground,
                                 logo: logo, persona: persona, size: bounds.size)
    }
}

struct MobileScreenAspectReader: UIViewRepresentable {
    let onChange: (Double) -> Void
    func makeUIView(context: Context) -> MobileScreenAspectSurface {
        let view = MobileScreenAspectSurface(); view.onChange = onChange; return view
    }
    func updateUIView(_ view: MobileScreenAspectSurface, context: Context) { view.onChange = onChange }
}

final class MobileScreenAspectSurface: UIView {
    var onChange: ((Double) -> Void)?
    private var lastAspect: Double?
    override func didMoveToWindow() { super.didMoveToWindow(); publishAspect() }
    override func layoutSubviews() { super.layoutSubviews(); publishAspect() }
    private func publishAspect() {
        guard let size = window?.windowScene?.screen.bounds.size, size.width > 0, size.height > 0 else { return }
        let aspect = Double(min(size.width, size.height) / max(size.width, size.height))
        guard aspect != lastAspect else { return }; lastAspect = aspect
        DispatchQueue.main.async { [weak self] in self?.onChange?(aspect) }
    }
}
