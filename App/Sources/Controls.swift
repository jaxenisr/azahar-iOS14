import UIKit
import SwiftUI
import GameController
import Combine

/// Where the game image sits and where the controls sit, so the two can never
/// overlap. The controls live in the margins the aspect-fit image leaves behind.
struct ControlMetrics {
    let game: CGRect
    let landscape: Bool
    let shoulderHeight: CGFloat

    static func make(in size: CGSize, safeArea: UIEdgeInsets, scale: CGFloat) -> ControlMetrics {
        let s = min(max(scale, 0.7), 1.35)
        let shoulderHeight: CGFloat = 42
        let landscape = size.width > size.height

        if landscape {
            let columnWidth = min(max(168 * s, 148), size.width * 0.24)
            let game = CGRect(x: safeArea.left + columnWidth,
                              y: safeArea.top + 4,
                              width: max(size.width - safeArea.left - safeArea.right - columnWidth * 2, 120),
                              height: max(size.height - safeArea.top - safeArea.bottom - 8, 120))
            return ControlMetrics(game: game, landscape: true, shoulderHeight: shoulderHeight)
        }

        let bandHeight = min(max(206 * s, 186), size.height * 0.34)
        let game = CGRect(x: safeArea.left,
                          y: safeArea.top + shoulderHeight + 8,
                          width: max(size.width - safeArea.left - safeArea.right, 120),
                          height: max(size.height - safeArea.top - safeArea.bottom - bandHeight - shoulderHeight - 8, 120))
        return ControlMetrics(game: game, landscape: false, shoulderHeight: shoulderHeight)
    }
}

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
    private let diameter: CGFloat
    private var activeTouch: UITouch?

    var onPress: ((Bool) -> Void)?
    var onHaptic: (() -> Void)?

    init(title: String, diameter: CGFloat, shape: Shape) {
        self.diameter = diameter
        self.shape = shape
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        isExclusiveTouch = false

        fill.isUserInteractionEnabled = false
        fill.backgroundColor = UIColor(white: 1, alpha: 0.075)
        fill.layer.borderWidth = 1
        fill.layer.borderColor = UIColor(white: 1, alpha: 0.13).cgColor
        addSubview(fill)

        label.text = title
        label.font = .systemFont(ofSize: diameter * 0.34, weight: .semibold)
        label.textColor = UIColor(white: 1, alpha: 0.9)
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
        label.frame = bounds
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.09) {
                self.fill.backgroundColor = UIColor(white: 1, alpha: self.isHighlighted ? 0.22 : 0.075)
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
        let inside = bounds.insetBy(dx: -14, dy: -14).contains(touch.location(in: self))
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

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
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
        base.isUserInteractionEnabled = false
        base.backgroundColor = UIColor(white: 1, alpha: 0.055)
        base.layer.borderWidth = 1
        base.layer.borderColor = UIColor(white: 1, alpha: 0.10).cgColor
        addSubview(base)

        knob.isUserInteractionEnabled = false
        knob.backgroundColor = UIColor(white: 1, alpha: 0.16)
        knob.layer.borderWidth = 1
        knob.layer.borderColor = UIColor(white: 1, alpha: 0.20).cgColor
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.35
        knob.layer.shadowRadius = 6
        knob.layer.shadowOffset = CGSize(width: 0, height: 3)
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
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }
}

/// The whole control surface. It only answers touches that land on a control, so
/// a finger on the game image still reaches the touchscreen underneath.
final class OnScreenControlsView: UIView {
    struct Setup {
        var opacity: CGFloat = 0.9
        var scale: CGFloat = 1
        var haptics = true
        var landscape = true
        var game = CGRect.zero
        var safeArea = UIEdgeInsets.zero
    }

    var onButton: ((UInt32, Bool) -> Void)?
    var onStick: ((CGFloat, CGFloat) -> Void)?

    private let haptics = Haptics()
    private var setup = Setup()

    private let stick = ThumbstickView(frame: .zero)
    private let leftUp = PadButtonView(title: "▲", diameter: 54, shape: .circle)
    private let leftDown = PadButtonView(title: "▼", diameter: 54, shape: .circle)
    private let leftLeft = PadButtonView(title: "◀", diameter: 54, shape: .circle)
    private let leftRight = PadButtonView(title: "▶", diameter: 54, shape: .circle)
    private let buttonA = PadButtonView(title: "A", diameter: 58, shape: .circle)
    private let buttonB = PadButtonView(title: "B", diameter: 58, shape: .circle)
    private let buttonX = PadButtonView(title: "X", diameter: 58, shape: .circle)
    private let buttonY = PadButtonView(title: "Y", diameter: 58, shape: .circle)
    private let shoulderL = PadButtonView(title: "L", diameter: 40, shape: .pill)
    private let shoulderR = PadButtonView(title: "R", diameter: 40, shape: .pill)
    private let start = PadButtonView(title: "Start", diameter: 40, shape: .pill)
    private let select = PadButtonView(title: "Select", diameter: 40, shape: .pill)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        addSubview(stick)
        for view in [leftUp, leftDown, leftLeft, leftRight,
                     buttonA, buttonB, buttonX, buttonY,
                     shoulderL, shoulderR, start, select] {
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
        let safe = setup.safeArea
        let game = setup.game
        guard game.width > 1, game.height > 1 else { return }

        let s = min(max(setup.scale, 0.7), 1.35)
        let buttonSize = min(max(48 * s, 44), 64)
        let stickSize = min(max(150 * s, 132), 186)

        if setup.landscape {
            let columnWidth = game.minX - safe.left
            let rightColumnWidth = bounds.width - safe.right - game.maxX
            let leftCenterX = safe.left + columnWidth / 2
            let rightCenterX = game.maxX + rightColumnWidth / 2
            let shoulderY = safe.top + 4

            shoulderL.frame = CGRect(x: safe.left + 8, y: shoulderY,
                                     width: min(columnWidth - 16, 96), height: 38)
            shoulderR.frame = CGRect(x: bounds.width - safe.right - min(rightColumnWidth - 16, 96),
                                     y: shoulderY,
                                     width: min(rightColumnWidth - 16, 96), height: 38)

            let stickTop = shoulderY + 52
            let stickSide = min(stickSize, columnWidth - 24)
            stick.frame = CGRect(x: leftCenterX - stickSide / 2, y: stickTop,
                                 width: stickSide, height: stickSide)

            let crossSize = min(stickSide * 0.86, game.height - stickSide - 90)
            let crossY = stick.frame.maxY + 16
            layoutCross(centerX: leftCenterX, top: crossY, size: crossSize, button: buttonSize)

            let diamondCenter = CGPoint(x: rightCenterX, y: game.midY - 10)
            layoutDiamond(center: diamondCenter, button: buttonSize)

            let startWidth = min(rightColumnWidth - 16, 96)
            start.frame = CGRect(x: rightCenterX - startWidth / 2,
                                 y: diamondCenter.y + buttonSize * 1.9,
                                 width: startWidth, height: 36)
            select.frame = CGRect(x: rightCenterX - startWidth / 2,
                                  y: start.frame.maxY + 10,
                                  width: startWidth, height: 36)
        } else {
            let bandTop = game.maxY
            let bandHeight = bounds.height - safe.bottom - bandTop
            let bandMidY = bandTop + bandHeight / 2

            let shoulderWidth = min(bounds.width * 0.22, 116)
            shoulderL.frame = CGRect(x: safe.left + 12, y: safe.top + 4,
                                     width: shoulderWidth, height: 38)
            shoulderR.frame = CGRect(x: bounds.width - safe.right - shoulderWidth - 12,
                                     y: safe.top + 4,
                                     width: shoulderWidth, height: 38)

            let stickSide = min(stickSize, bandHeight - 24)
            stick.frame = CGRect(x: safe.left + bandHeight * 0.1,
                                 y: bandMidY - stickSide / 2,
                                 width: stickSide, height: stickSide)

            let crossSize = min(stickSide * 0.8, bandHeight - 40)
            layoutCross(centerX: stick.frame.maxX + crossSize / 2 + 18,
                        top: bandMidY - crossSize / 2 - 14,
                        size: crossSize,
                        button: min(buttonSize * 0.9, 52))

            let diamondCenter = CGPoint(x: bounds.width - safe.right - bandHeight * 0.55,
                                        y: bandMidY - 8)
            layoutDiamond(center: diamondCenter, button: min(buttonSize, 56))

            let startWidth: CGFloat = 78
            start.frame = CGRect(x: diamondCenter.x - startWidth - 6,
                                 y: diamondCenter.y + buttonSize * 1.55,
                                 width: startWidth, height: 32)
            select.frame = CGRect(x: diamondCenter.x + 6,
                                  y: diamondCenter.y + buttonSize * 1.55,
                                  width: startWidth, height: 32)
        }

        for button in [leftUp, leftDown, leftLeft, leftRight,
                       buttonA, buttonB, buttonX, buttonY,
                       shoulderL, shoulderR, start, select] {
            button.setNeedsLayout()
        }
    }

    private func layoutCross(centerX: CGFloat, top: CGFloat, size: CGFloat, button: CGFloat) {
        let side = max(size, button * 2.6)
        let midY = top + side / 2
        let gap: CGFloat = 2
        leftUp.frame = CGRect(x: centerX - button / 2, y: top, width: button, height: button)
        leftDown.frame = CGRect(x: centerX - button / 2,
                                y: top + side - button,
                                width: button, height: button)
        leftLeft.frame = CGRect(x: centerX - side / 2,
                                y: midY - button / 2,
                                width: button, height: button)
        leftRight.frame = CGRect(x: centerX + side / 2 - button,
                                 y: midY - button / 2,
                                 width: button, height: button)
        // Keep the three rows from touching when the button is large.
        if leftUp.frame.maxY + gap > leftLeft.frame.minY {
            leftUp.frame.origin.y = leftLeft.frame.minY - gap - button
        }
    }

    private func layoutDiamond(center: CGPoint, button: CGFloat) {
        let offset = button * 0.92
        buttonX.frame = CGRect(x: center.x - button / 2, y: center.y - offset - button / 2,
                              width: button, height: button)
        buttonB.frame = CGRect(x: center.x - button / 2, y: center.y + offset - button / 2,
                              width: button, height: button)
        buttonY.frame = CGRect(x: center.x - offset - button / 2, y: center.y - button / 2,
                              width: button, height: button)
        buttonA.frame = CGRect(x: center.x + offset - button / 2, y: center.y - button / 2,
                              width: button, height: button)
    }

    /// Only the controls themselves take touches; everything else falls through to
    /// the game surface, where the bottom screen is.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for view in subviews where !view.isHidden && view.alpha > 0.05 {
            if view.frame.contains(point) { return true }
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
