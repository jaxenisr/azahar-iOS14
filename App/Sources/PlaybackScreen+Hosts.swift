import SwiftUI
import UIKit
import QuartzCore

/// A UIView backed by a CAMetalLayer, which is what MoltenVK presents into.
struct MetalSurfaceView: UIViewRepresentable {
    let onLayer: (CAMetalLayer) -> Void

    func makeUIView(context: Context) -> MetalContainerView {
        let view = MetalContainerView()
        if let layer = view.layer as? CAMetalLayer {
            onLayer(layer)
        }
        return view
    }

    func updateUIView(_ view: MetalContainerView, context: Context) {}
}

final class MetalContainerView: UIView {
    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        if let layer = layer as? CAMetalLayer {
            layer.framebufferOnly = false
            layer.isOpaque = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Draws a software-rendered frame. A layer's contents is the cheapest path from
/// a CGImage to the screen.
///
/// In the stacked layout the two screens are cropped out of the one image and
/// drawn as separate layers, so the hinge is real space between them and not a
/// seam inside a stretched picture.
struct FrameImageView: UIViewRepresentable {
    let image: CGImage
    var stacked: Bool = false
    var hinge: CGFloat = 0

    func makeUIView(context: Context) -> FrameContainerView {
        FrameContainerView()
    }

    func updateUIView(_ view: FrameContainerView, context: Context) {
        view.show(image, stacked: stacked, hinge: hinge)
    }
}

final class FrameContainerView: UIView {
    private let whole = CALayer()
    private let upper = CALayer()
    private let lower = CALayer()
    private var stacked = false
    private var hinge: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        for layer in [whole, upper, lower] {
            layer.contentsGravity = .resizeAspect
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            self.layer.addSublayer(layer)
        }
        upper.isHidden = true
        lower.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ image: CGImage, stacked: Bool, hinge: CGFloat) {
        self.stacked = stacked
        self.hinge = min(max(hinge, 0), 0.25)
        whole.contents = stacked ? nil : image
        whole.isHidden = stacked
        upper.isHidden = !stacked
        lower.isHidden = !stacked
        if stacked {
            // The core composes the pair flush, one screen above the other.
            upper.contents = image
            lower.contents = image
            upper.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 0.5)
            lower.contentsRect = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        whole.frame = bounds
        guard stacked else { return }
        let unit = bounds.height * (1 - hinge) / 2
        let gap = bounds.height - unit * 2
        upper.frame = CGRect(x: 0, y: 0, width: bounds.width, height: unit)
        lower.frame = CGRect(x: 0, y: unit + gap,
                             width: bounds.width, height: bounds.height - unit - gap)
    }
}

/// The bottom screen. The core maps a normalised pointer onto the bottom screen
/// itself, so this only has to say where the finger is inside the frame the core
/// is producing.
final class TouchSurfaceView: UIView {
    /// Every tap this surface has received since launch. The touch diagnostics
    /// read it: a tap has to land here before anything downstream can happen, so
    /// this is the first of the three counters.
    static private(set) var taps = 0

    var onTouch: ((CGFloat, CGFloat, Bool) -> Void)?
    var stacked = false
    var hinge: CGFloat = 0
    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        TouchSurfaceView.taps += 1
        activeTouch = touch
        report(touch, pressed: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        report(touch, pressed: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        onTouch?(0, 0, false)
    }

    /// The view's frame is already the picture's rect, so a touch maps straight
    /// onto the core's frame; the core then maps it onto the bottom screen.
    ///
    /// In the stacked layout the picture is the pair plus the hinge, and only the
    /// lower half holds the touchscreen. The core measures the pointer across its
    /// whole frame, though, and drops a press that lands above the bottom screen,
    /// so the point is turned into a fraction of that frame: the lower half starts
    /// at the middle of it. The pixel under the finger is therefore the pixel the
    /// core gets, at any scale.
    private func report(_ touch: UITouch, pressed: Bool) {
        let point = touch.location(in: self)
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }

        if stacked {
            let fraction = min(max(hinge, 0), 0.25)
            let unit = size.height * (1 - fraction) / 2
            guard unit > 1 else { return }
            let bottomTop = size.height - unit
            // The pointer the core reads is normalised over its whole frame -- top
            // screen above, bottom screen below -- and a press that does not land
            // inside the lower screen is dropped. So the point becomes a fraction
            // of that frame: across the full width, and downwards from the middle
            // for the lower half. Sending the lower half as -1...1 instead maps
            // every tap into the top half, where the core ignores it.
            let frameX = point.x / size.width
            let frameY = 0.5 + 0.5 * ((point.y - bottomTop) / unit)
            let x = frameX * 2 - 1
            let y = frameY * 2 - 1
            onTouch?(min(max(x, -1.5), 1.5), min(max(y, -0.25), 1.25), pressed)
            return
        }

        let source = AZCoreSourceSize()
        let sourceWidth = source.width > 1 ? source.width : 400
        let sourceHeight = source.height > 1 ? source.height : 480
        let scale = min(size.width / sourceWidth, size.height / sourceHeight)
        guard scale > 0 else { return }

        let drawnWidth = sourceWidth * scale
        let drawnHeight = sourceHeight * scale
        let originX = (size.width - drawnWidth) / 2
        let originY = (size.height - drawnHeight) / 2

        let x = ((point.x - originX) / drawnWidth) * 2 - 1
        let y = ((point.y - originY) / drawnHeight) * 2 - 1
        onTouch?(x, y, pressed)
    }
}
