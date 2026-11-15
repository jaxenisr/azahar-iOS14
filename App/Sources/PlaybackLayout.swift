import UIKit

/// Where every part of the playback screen goes.
///
/// The picture is fitted, at the core's own aspect, into whatever the controls
/// leave behind and centred in it; the controls live in a column at each outer
/// margin in landscape and in a band below the picture in portrait; the HUD
/// docks in a margin. Nothing is computed from the raw screen bounds, so the
/// status bar, the home indicator and the rounded corners cannot take a bite
/// out of the layout.
struct PlaybackGeometry {
    enum HUDState {
        case compact
        case full
    }

    let landscape: Bool
    /// Where the game picture is drawn, exactly.
    let image: CGRect
    let shoulderL: CGRect
    let shoulderR: CGRect
    let stick: CGRect
    /// Square that contains the four D-pad buttons.
    let dpad: CGRect
    /// Square that contains the four face buttons.
    let diamond: CGRect
    let start: CGRect
    let select: CGRect
    /// The strip the HUD may use. Never overlaps `image`.
    let hud: CGRect
    /// One face button or D-pad button.
    let button: CGFloat
    /// Centre of a face button from the centre of the diamond.
    let offset: CGFloat

    var hudHeight: CGFloat { hud.height }

    static func make(in size: CGSize,
                     safe: UIEdgeInsets,
                     scale: CGFloat,
                     aspect: CGFloat,
                     hud: HUDState,
                     hudMetrics: HUDMetrics) -> PlaybackGeometry {
        let s = min(max(scale, 0.7), 1.35)
        let margin: CGFloat = 16
        let content = CGRect(x: safe.left + margin,
                             y: safe.top + margin,
                             width: max(size.width - safe.left - safe.right - margin * 2, 200),
                             height: max(size.height - safe.top - safe.bottom - margin * 2, 200))

        if size.width > size.height {
            return landscapeLayout(in: content, scale: s, aspect: aspect,
                                   hud: hud, hudMetrics: hudMetrics)
        }
        return portraitLayout(in: content, scale: s, aspect: aspect,
                              hud: hud, hudMetrics: hudMetrics)
    }

    // MARK: - Landscape

    private static func landscapeLayout(in content: CGRect,
                                        scale s: CGFloat,
                                        aspect: CGFloat,
                                        hud: HUDState,
                                        hudMetrics: HUDMetrics) -> PlaybackGeometry {
        let guess = min(max(156 * s, 150), content.width * 0.26)
        // The HUD needs a column wide enough for its widest row, so the margins
        // give way rather than the card clipping.
        let column = min(max(guess, hudMetrics.width), content.width * 0.34)
        let gap: CGFloat = 10

        let imageArea = CGRect(x: content.minX + column + gap,
                               y: content.minY,
                               width: max(content.width - (column + gap) * 2, 160),
                               height: content.height)
        let image = fit(aspect: aspect, in: imageArea)

        let left = CGRect(x: content.minX, y: content.minY, width: column, height: content.height)
        let right = CGRect(x: content.maxX - column, y: content.minY, width: column, height: content.height)

        let shoulderWidth = min(column, 108)
        let shoulderL = CGRect(x: left.minX, y: left.minY, width: shoulderWidth, height: 40)
        let shoulderR = CGRect(x: right.maxX - shoulderWidth, y: left.minY, width: shoulderWidth, height: 40)

        // The stick sits at the bottom of the left column, where the thumb rests;
        // the D-pad sits above it; the HUD takes what is left below L.
        let stickSide = min(max(column * 0.95, 118), 186)
        let crossSide = min(column - 4, stickSide * 0.94)
        let bottomBlock = stickSide + 16 + crossSide

        let hudTop = shoulderL.maxY + 12
        let hudSpace = max(left.maxY - bottomBlock - 24 - hudTop, 0)
        let hudHeight: CGFloat = hud == .full ? min(hudMetrics.fullHeight, hudSpace) : 34
        let hudRect = CGRect(x: left.minX, y: hudTop,
                             width: min(column, hudMetrics.width),
                             height: max(hudHeight, 34))

        let stick = CGRect(x: left.midX - stickSide / 2,
                           y: left.maxY - stickSide,
                           width: stickSide, height: stickSide)
        let dpadTop = max(stick.minY - 16 - crossSide, hudRect.maxY + 12)
        let dpad = CGRect(x: left.midX - crossSide / 2,
                          y: dpadTop,
                          width: crossSide, height: crossSide)

        let button = min(max(52 * s, 46), 62)
        let offset = button * 0.92
        let diamondSide = offset * 2 + button
        let diamond = CGRect(x: right.midX - diamondSide / 2,
                             y: right.midY - diamondSide / 2,
                             width: diamondSide, height: diamondSide)

        let startWidth = min(column, 96)
        let start = CGRect(x: right.midX - startWidth / 2,
                           y: diamond.maxY + 20,
                           width: startWidth, height: 34)
        let select = CGRect(x: start.minX, y: start.maxY + 10, width: startWidth, height: 34)

        return PlaybackGeometry(landscape: true,
                                image: image,
                                shoulderL: shoulderL,
                                shoulderR: shoulderR,
                                stick: stick,
                                dpad: dpad,
                                diamond: diamond,
                                start: start,
                                select: select,
                                hud: hudRect,
                                button: button,
                                offset: offset)
    }

    // MARK: - Portrait

    private static func portraitLayout(in content: CGRect,
                                       scale s: CGFloat,
                                       aspect: CGFloat,
                                       hud: HUDState,
                                       hudMetrics: HUDMetrics) -> PlaybackGeometry {
        let shoulderWidth = min(content.width * 0.24, 110)
        let shoulderL = CGRect(x: content.minX, y: content.minY, width: shoulderWidth, height: 40)
        let shoulderR = CGRect(x: content.maxX - shoulderWidth, y: content.minY,
                               width: shoulderWidth, height: 40)

        let hudHeight: CGFloat = hud == .full ? hudMetrics.fullHeight : 34
        let hudRect = CGRect(x: content.minX, y: shoulderL.maxY + 10,
                             width: min(content.width, hudMetrics.width),
                             height: hudHeight)

        let bandHeight = min(max(190 * s, 172), content.height * 0.32)
        let band = CGRect(x: content.minX, y: content.maxY - bandHeight,
                          width: content.width, height: bandHeight)

        let imageArea = CGRect(x: content.minX,
                               y: hudRect.maxY + 12,
                               width: content.width,
                               height: max(band.minY - 12 - (hudRect.maxY + 12), 160))
        let image = fit(aspect: aspect, in: imageArea)

        let stickSide = min(bandHeight * 0.8, 150 * s)
        let stick = CGRect(x: band.minX + 6,
                           y: band.midY - stickSide / 2,
                           width: stickSide, height: stickSide)

        let crossSide = min(stickSide * 0.9, bandHeight * 0.78)
        let dpad = CGRect(x: stick.maxX + 16,
                          y: band.midY - crossSide / 2,
                          width: crossSide, height: crossSide)

        let button = min(max(52 * s, 44), 58)
        let offset = button * 0.92
        let diamondSide = offset * 2 + button
        let diamond = CGRect(x: band.maxX - diamondSide - 4,
                             y: band.midY - diamondSide / 2,
                             width: diamondSide, height: diamondSide)

        let pillWidth = min(max((diamond.minX - dpad.maxX) * 0.5, 72), 96)
        let centre = (dpad.maxX + diamond.minX) / 2
        let start = CGRect(x: centre - pillWidth / 2, y: band.midY - 42,
                           width: pillWidth, height: 34)
        let select = CGRect(x: start.minX, y: band.midY + 8,
                            width: pillWidth, height: 34)

        return PlaybackGeometry(landscape: false,
                                image: image,
                                shoulderL: shoulderL,
                                shoulderR: shoulderR,
                                stick: stick,
                                dpad: dpad,
                                diamond: diamond,
                                start: start,
                                select: select,
                                hud: hudRect,
                                button: button,
                                offset: offset)
    }

    // MARK: - Helpers

    /// The largest rect with this aspect that fits in `area`, centred in it.
    private static func fit(aspect: CGFloat, in area: CGRect) -> CGRect {
        let ratio = (aspect.isFinite && aspect > 0.05) ? aspect : 400.0 / 480.0
        let areaRatio = area.width / max(area.height, 1)
        let size: CGSize
        if ratio > areaRatio {
            size = CGSize(width: area.width, height: area.width / ratio)
        } else {
            size = CGSize(height: area.height * ratio, height: area.height)
        }
        return CGRect(x: area.midX - size.width / 2,
                      y: area.midY - size.height / 2,
                      width: max(size.width, 1),
                      height: max(size.height, 1))
    }
}

/// The size the HUD card needs, worked out from the rows it actually shows.
///
/// The card used to be given a guessed width and its rows had to fit into it:
/// the heading wrapped, the renderer name was cut short and the bottom rows lost
/// their values off the edge. Each row is now a label column and a right-aligned
/// value column, and the card is exactly as wide as its widest row.
///
/// The value widths come from the widest a value can get rather than the value it
/// happens to show, so the card does not resize as the numbers tick over.
struct HUDMetrics {
    static let rowHeight: CGFloat = 13
    static let labelGap: CGFloat = 8
    static let columnGap: CGFloat = 12
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 20
    static let buttonsHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 8
    static let rowGap: CGFloat = 3
    static let heading = "PERFORMANCE"

    let columns: Int
    let rowCount: Int
    let labelWidth: CGFloat
    let valueWidth: CGFloat
    /// The whole card, padding included.
    let width: CGFloat
    /// The card with every row and the buttons showing.
    let fullHeight: CGFloat

    /// The rows that fall in one column, reading across then down.
    func indices(in column: Int) -> [Int] {
        guard columns > 1 else { return Array(0..<rowCount) }
        return stride(from: column, to: rowCount, by: columns).map { $0 }
    }

    static func make(labels: [String], widestValues: [String], columns: Int) -> HUDMetrics {
        let font = UIFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
        // A point of slack on each column: a measured string that lands a hair
        // wider in SwiftUI would otherwise truncate.
        let labelWidth = ceil((labels.map { textWidth($0, font) }.max() ?? 0) + 1)
        let valueWidth = ceil((widestValues.map { textWidth($0, font) }.max() ?? 0) + 1)
        let rowWidth = labelWidth + labelGap + valueWidth

        let headingWidth = textWidth(heading, UIFont.systemFont(ofSize: 10, weight: .semibold))
            + 0.7 * CGFloat(heading.count)
        // Two 24 pt icon buttons, 4 pt apart, a 6 pt gap after the heading.
        let headerWidth = headingWidth + 6 + 24 + 4 + 24

        let rows = max(labels.count, widestValues.count)
        let columns = max(columns, 1)
        let perColumn = Int((Double(rows) / Double(columns)).rounded(.up))
        let columnsWidth = CGFloat(columns) * rowWidth + CGFloat(columns - 1) * columnGap
        let body = max(columnsWidth, headerWidth)
        let height = padding * 2 + headerHeight + rowSpacing
            + CGFloat(perColumn) * rowHeight + CGFloat(max(perColumn - 1, 0)) * rowGap
            + rowSpacing + buttonsHeight

        return HUDMetrics(columns: columns,
                          rowCount: rows,
                          labelWidth: labelWidth,
                          valueWidth: valueWidth,
                          width: ceil(body + padding * 2),
                          fullHeight: ceil(height))
    }

    private static func textWidth(_ text: String, _ font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
