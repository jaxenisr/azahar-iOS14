import UIKit
import SwiftUI
import GameController
import Combine

/// Soft, restrained haptics. Every call is a no-op when the setting is off.
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    var isEnabled = true

    func prepare() {
        light.prepare()
        soft.prepare()
        selection.prepare()
    }

    func tap() {
        guard isEnabled else { return }
        light.impactOccurred()
    }

    func press() {
        guard isEnabled else { return }
        soft.impactOccurred(intensity: 0.55)
    }

    func tick() {
        guard isEnabled else { return }
        selection.selectionChanged()
    }
}

/// A translucent control that reports press and release, including when a finger
/// slides off it. Being a UIControl is what makes simultaneous touches on
/// different controls work without any gesture arbitration.
final class PadButtonView: UIControl {
    enum Shape {
        case circle
        case pill
    }

    private let shape: Shape
    private let fill = UIView()
    private let label = UILabel()
    private var activeTouch: UITouch?

    var onPress: ((Bool) -> Void)?
    var onHaptic: (() -> Void)?

    init(title: String, shape: Shape) {
        self.shape = shape
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
        backgroundColor = .clear

        fill.isUserInteractionEnabled = false
        fill.backgroundColor = UIColor(white: 1, alpha: 0.1)
        fill.layer.borderWidth = 1
        fill.layer.borderColor = UIColor(white: 1, alpha: 0.16).cgColor
        fill.layer.shadowColor = UIColor.black.cgColor
        fill.layer.shadowOpacity = 0.45
        fill.layer.shadowRadius = 8
        fill.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(fill)

        label.text = title
        label.adjustsFontSizeToFitWidth = true
        label.textColor = UIColor(white: 1, alpha: 0.86)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = bounds
        switch shape {
        case .circle:
            fill.layer.cornerRadius = bounds.width / 2
        case .pill:
            fill.layer.cornerRadius = min(bounds.height / 2, 18)
        }
        label.frame = bounds.insetBy(dx: 4, dy: 2)
        label.font = .systemFont(ofSize: max(min(bounds.height * 0.34, 20), 9), weight: .semibold)
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.fill.backgroundColor = self.isHighlighted
                    ? UIColor(white: 1, alpha: 0.26)
                    : UIColor(white: 1, alpha: 0.1)
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.95, y: 0.95)
                    : .identity
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        activeTouch = touch
        isHighlighted = true
        onHaptic?()
        onPress?(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let inside = bounds.insetBy(dx: -18, dy: -18).contains(touch.location(in: self))
        if inside != isHighlighted {
            isHighlighted = inside
        }
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
        isHighlighted = false
        onPress?(false)
    }

    /// A generous target: the drawn circle is the visual, not the edge of the tap.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: -10).contains(point)
    }
}

/// The circle pad: a real analogue stick, not a D-pad. Radial tracking, a small
/// dead zone, spring return, light haptics at the edge of the dead zone.
final class ThumbstickView: UIControl {
    private let base = UIView()
    private let knob = UIView()
    private var activeTouch: UITouch?
    private var wasEngaged = false

    var onChange: ((CGFloat, CGFloat) -> Void)?
    var onHaptic: (() -> Void)?

    private let deadZone: CGFloat = 0.14

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        base.isUserInteractionEnabled = false
        base.backgroundColor = UIColor(white: 1, alpha: 0.07)
        base.layer.borderWidth = 1
        base.layer.borderColor = UIColor(white: 1, alpha: 0.13).cgColor
        addSubview(base)

        knob.isUserInteractionEnabled = false
        knob.backgroundColor = UIColor(white: 1, alpha: 0.18)
        knob.layer.borderWidth = 1
        knob.layer.borderColor = UIColor(white: 1, alpha: 0.22).cgColor
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.4
        knob.layer.shadowRadius = 8
        knob.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(knob)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        base.frame = bounds
        base.layer.cornerRadius = bounds.width / 2
        let side = bounds.width * 0.46
        knob.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        knob.layer.cornerRadius = side / 2
        if activeTouch == nil {
            knob.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        activeTouch = touch
        update(with: touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        update(with: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    private func release(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        wasEngaged = false
        onChange?(0, 0)
        UIView.animate(withDuration: 0.18,
                       delay: 0,
                       usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.knob.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        }
    }

    private func update(with touch: UITouch) {
        let location = touch.location(in: self)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let travel = bounds.width / 2 - knob.bounds.width / 2
        guard travel > 1 else { return }

        var dx = (location.x - center.x) / travel
        var dy = (location.y - center.y) / travel
        let magnitude = sqrt(dx * dx + dy * dy)
        if magnitude > 1 {
            dx /= magnitude
            dy /= magnitude
        }

        let engaged = magnitude >= deadZone
        if engaged != wasEngaged {
            wasEngaged = engaged
            onHaptic?()
        }

        var outX = dx
        var outY = dy
        if !engaged {
            outX = 0
            outY = 0
        } else {
            let scaled = (min(magnitude, 1) - deadZone) / (1 - deadZone)
            outX = (dx / magnitude) * scaled
            outY = (dy / magnitude) * scaled
        }

        knob.center = CGPoint(x: center.x + outX * travel, y: center.y + outY * travel)
        onChange?(outX, outY)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: -10).contains(point)
    }
}

/// The whole control surface. It only answers touches that land on a control, so
/// a finger on the game image still reaches the touchscreen underneath.
///
/// The frames arrive ready-made from `PlaybackGeometry`: this view draws and
/// reports, it does not decide where anything goes.
final class OnScreenControlsView: UIView {
    struct Setup {
        var opacity: CGFloat = 0.9
        var haptics = true
        var button: CGFloat = 52
        var offset: CGFloat = 48
        var stick = CGRect.zero
        var dpad = CGRect.zero
        var diamond = CGRect.zero
        var shoulderL = CGRect.zero
        var shoulderR = CGRect.zero
        var start = CGRect.zero
        var select = CGRect.zero
    }

    var onButton: ((UInt32, Bool) -> Void)?
    var onStick: ((CGFloat, CGFloat) -> Void)?

    private let haptics = Haptics()
    private var setup = Setup()

    private let stick = ThumbstickView(frame: .zero)
    private let leftUp = PadButtonView(title: "▲", shape: .circle)
    private let leftDown = PadButtonView(title: "▼", shape: .circle)
    private let leftLeft = PadButtonView(title: "◀", shape: .circle)
    private let leftRight = PadButtonView(title: "▶", shape: .circle)
    private let buttonA = PadButtonView(title: "A", shape: .circle)
    private let buttonB = PadButtonView(title: "B", shape: .circle)
    private let buttonX = PadButtonView(title: "X", shape: .circle)
    private let buttonY = PadButtonView(title: "Y", shape: .circle)
    private let shoulderL = PadButtonView(title: "L", shape: .pill)
    private let shoulderR = PadButtonView(title: "R", shape: .pill)
    private let start = PadButtonView(title: "Start", shape: .pill)
    private let select = PadButtonView(title: "Select", shape: .pill)

    private var allButtons: [PadButtonView] {
        [leftUp, leftDown, leftLeft, leftRight,
         buttonA, buttonB, buttonX, buttonY,
         shoulderL, shoulderR, start, select]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        addSubview(stick)
        for view in allButtons {
            addSubview(view)
        }

        stick.onChange = { [weak self] x, y in
            self?.onStick?(x, y)
        }
        stick.onHaptic = { [weak self] in
            self?.haptics.tick()
        }

        bind(leftUp, PlaybackSession.Pad.up)
        bind(leftDown, PlaybackSession.Pad.down)
        bind(leftLeft, PlaybackSession.Pad.left)
        bind(leftRight, PlaybackSession.Pad.right)
        bind(buttonA, PlaybackSession.Pad.a)
        bind(buttonB, PlaybackSession.Pad.b)
        bind(buttonX, PlaybackSession.Pad.x)
        bind(buttonY, PlaybackSession.Pad.y)
        bind(shoulderL, PlaybackSession.Pad.l)
        bind(shoulderR, PlaybackSession.Pad.r)
        bind(start, PlaybackSession.Pad.start)
        bind(select, PlaybackSession.Pad.select)

        haptics.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bind(_ button: PadButtonView, _ mask: UInt32) {
        button.onPress = { [weak self] pressed in
            self?.onButton?(mask, pressed)
        }
        button.onHaptic = { [weak self] in
            self?.haptics.press()
        }
    }

    func apply(_ setup: Setup) {
        self.setup = setup
        alpha = setup.opacity
        haptics.isEnabled = setup.haptics
        isHidden = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        stick.frame = setup.stick
        shoulderL.frame = setup.shoulderL
        shoulderR.frame = setup.shoulderR
        start.frame = setup.start
        select.frame = setup.select

        let face = max(setup.button, 30)
        let distance = max(setup.offset, face)

        // The D-pad's four buttons are drawn to fill its own square, so the two
        // arms meet instead of leaving holes between them.
        let cross = setup.dpad
        let d = max(min(cross.width / 3 - 2, 58), 26)
        let dc = CGPoint(x: cross.midX, y: cross.midY)
        leftUp.frame = CGRect(x: dc.x - d / 2, y: cross.minY, width: d, height: d)
        leftDown.frame = CGRect(x: dc.x - d / 2, y: cross.maxY - d, width: d, height: d)
        leftLeft.frame = CGRect(x: cross.minX, y: dc.y - d / 2, width: d, height: d)
        leftRight.frame = CGRect(x: cross.maxX - d, y: dc.y - d / 2, width: d, height: d)

        // The 3DS diamond: X above, B below, Y left, A right.
        let centre = CGPoint(x: setup.diamond.midX, y: setup.diamond.midY)
        buttonX.frame = CGRect(x: centre.x - face / 2, y: centre.y - distance - face / 2,
                              width: face, height: face)
        buttonB.frame = CGRect(x: centre.x - face / 2, y: centre.y + distance - face / 2,
                              width: face, height: face)
        buttonY.frame = CGRect(x: centre.x - distance - face / 2, y: centre.y - face / 2,
                              width: face, height: face)
        buttonA.frame = CGRect(x: centre.x + distance - face / 2, y: centre.y - face / 2,
                              width: face, height: face)

        for button in allButtons {
            button.setNeedsLayout()
        }
    }

    /// Only the controls themselves take touches, each with a generous margin;
    /// everything else falls through to the game surface, where the bottom
    /// screen is.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for view in subviews where !view.isHidden && view.alpha > 0.05 {
            if view.frame.insetBy(dx: -6, dy: -6).contains(point) { return true }
        }
        return false
    }
}

/// Wraps the UIKit controls for SwiftUI and keeps their configuration current.
struct ControlsOverlay: UIViewRepresentable {
    let setup: OnScreenControlsView.Setup
    let onButton: (UInt32, Bool) -> Void
    let onStick: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> OnScreenControlsView {
        let view = OnScreenControlsView()
        view.onButton = onButton
        view.onStick = onStick
        view.apply(setup)
        return view
    }

    func updateUIView(_ view: OnScreenControlsView, context: Context) {
        view.onButton = onButton
        view.onStick = onStick
        view.apply(setup)
    }
}

/// Watches for MFi controllers and feeds the emulator from them. When one is
/// connected the on-screen controls hide, so the same input is never applied
/// twice and the game image is not covered by buttons nobody needs.
final class ControllerMonitor: ObservableObject {
    static let shared = ControllerMonitor()

    @Published private(set) var isConnected = false
    weak var session: PlaybackSession?

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        let controllers = GCController.controllers()
        isConnected = !controllers.isEmpty

        for (index, controller) in controllers.enumerated() {
            controller.playerIndex = GCControllerPlayerIndex(rawValue: index) ?? .index1
            if let pad = controller.extendedGamepad {
                pad.valueChangedHandler = { [weak self] pad, _ in
                    self?.handle(pad)
                }
            }
        }
    }

    private func handle(_ pad: GCExtendedGamepad) {
        guard let session = session else { return }

        var mask: UInt32 = 0
        if pad.buttonA.isPressed { mask |= PlaybackSession.Pad.a }
        if pad.buttonB.isPressed { mask |= PlaybackSession.Pad.b }
        if pad.buttonX.isPressed { mask |= PlaybackSession.Pad.x }
        if pad.buttonY.isPressed { mask |= PlaybackSession.Pad.y }
        if pad.leftShoulder.isPressed { mask |= PlaybackSession.Pad.l }
        if pad.rightShoulder.isPressed { mask |= PlaybackSession.Pad.r }
        if pad.dpad.up.isPressed { mask |= PlaybackSession.Pad.up }
        if pad.dpad.down.isPressed { mask |= PlaybackSession.Pad.down }
        if pad.dpad.left.isPressed { mask |= PlaybackSession.Pad.left }
        if pad.dpad.right.isPressed { mask |= PlaybackSession.Pad.right }
        if pad.buttonMenu.isPressed { mask |= PlaybackSession.Pad.start }
        if pad.buttonOptions?.isPressed == true { mask |= PlaybackSession.Pad.select }

        session.setButtons(mask)

        // libretro's analog Y is positive downwards; the controller's is positive
        // upwards, so it is inverted here rather than in the core.
        session.setCirclePad(x: Int(CGFloat(pad.leftThumbstick.xAxis.value) * 32767),
                             y: Int(CGFloat(-pad.leftThumbstick.yAxis.value) * 32767))
    }
}
