import SwiftUI
import UIKit

enum RootTab: String, CaseIterable, Identifiable {
    case games
    case emulation
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games: return "Games"
        case .emulation: return "Emulation"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .games: return "square.grid.2x2"
        case .emulation: return "slider.horizontal.3"
        case .settings: return "gear"
        }
    }
}

/// The shell. One navigation component, two arrangements.
///
/// The size class decides which one, and only which one: the screens, the cell,
/// the row and the motion are the same objects in both. Compact width on this app
/// is an iPad in split view or slide over, not a phone.
struct RootView: View {
    @State private var tab: RootTab = .games
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactShell
            } else {
                regularShell
            }
        }
        .background(Design.Palette.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .games:
            LibraryView()
        case .emulation:
            EmulationView()
        case .settings:
            AppSettingsView()
        }
    }

    /// Regular width: navigation at the top, centred, with the page underneath.
    private var regularShell: some View {
        VStack(spacing: 0) {
            TopNavigationBar(selection: $tab)
                .padding(.top, Design.Space.xs)
                .padding(.bottom, Design.Space.xxs)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Compact width: navigation floating above the home indicator, over the page.
    private var compactShell: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            BottomNavigationBar(selection: $tab)
                .padding(.bottom, Design.Space.xs)
                // Whatever the page does with a touch at the bottom, the bar is
                // the view that has to get it.
                .zIndex(1)
        }
    }
}

/// The regular-width segments. The pill is one object that moves between them:
/// both states draw it with the same geometry id, so the selection reads as
/// travel rather than as two colours swapping.
struct TopNavigationBar: View {
    @Binding var selection: RootTab
    @Namespace private var activePill

    var body: some View {
        FloatingCapsuleBar {
            HStack(spacing: 0) {
                ForEach(RootTab.allCases) { item in
                    Button(action: { selection = item }) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(selection == item ? Design.Palette.accent : Design.Palette.ink)
                            .padding(.horizontal, Design.Space.l)
                            .frame(height: 36)
                            .background(
                                Group {
                                    if selection == item {
                                        Capsule()
                                            .fill(Design.Palette.accentSoft)
                                            .matchedGeometryEffect(id: "active", in: activePill)
                                    }
                                }
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .pressHaptic()
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == item ? [.isSelected] : [])
                }
            }
            .animation(Design.Motion.selection)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The compact segments: symbol over label, the active one in a filled accent
/// capsule, and the whole item rectangle is the target, transparent parts too.
struct BottomNavigationBar: View {
    @Binding var selection: RootTab

    var body: some View {
        FloatingCapsuleBar {
            HStack(spacing: Design.Space.xxs) {
                ForEach(RootTab.allCases) { item in
                    Button(action: { selection = item }) {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 17, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(selection == item ? .white : Design.Palette.secondaryInk)
                        .frame(minWidth: 88)
                        .frame(height: 52)
                        .background(
                            Capsule().fill(selection == item ? Design.Palette.accent : Color.clear)
                        )
                        .contentShape(Capsule())
                        .animation(Design.Motion.selection)
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .pressHaptic()
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == item ? [.isSelected] : [])
                }
            }
        }
    }
}

/// The title bar the library uses: same size, same subtitle, same margins, and
/// one slot for the buttons on the right. The two settings pages collapse their
/// title with `CollapsingTitle` instead, because their content scrolls past it.
struct ScreenHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    let accessory: Accessory

    init(title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(title)
                    .font(Design.Fonts.title)
                    .foregroundColor(Design.Palette.ink)
                Text(subtitle)
                    .font(Design.Fonts.rowSubtitle)
                    .foregroundColor(Design.Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Design.Space.xs)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Space.sideMargin)
        .padding(.top, Design.Space.l)
        .padding(.bottom, Design.Space.xs)
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A settings card is the design card: same radius, same fill, same shadow, same
/// header. It keeps this name because every screen already calls it that.
struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        DesignCard(title, subtitle: subtitle) {
            content
        }
    }
}

/// A row is the design row. `isAvailable` is how a placeholder says so.
struct SettingRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let isAvailable: Bool
    let control: Control

    init(_ title: String,
         subtitle: String? = nil,
         isAvailable: Bool = true,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.isAvailable = isAvailable
        self.control = control()
    }

    var body: some View {
        DesignRow(title, subtitle: subtitle, isAvailable: isAvailable) { control }
            .frame(minHeight: 44)
    }
}

/// A setting the app cannot honour yet: a real row, the real title, greyed out and
/// inert, with the phrase the brief asks for followed by what is actually missing.
struct PlaceholderRow: View {
    let feature: PlannedFeature

    var body: some View {
        SettingRow(feature.title,
                   subtitle: feature.isAvailable
                    ? nil
                    : "Unavailable for now — \(feature.missing)",
                   isAvailable: feature.isAvailable) {
            EmptyView()
        }
    }
}

/// A one-of-N choice, using the shared chip row. It scrolls sideways rather than
/// squeezing eight CPU clock options into a row that cannot hold them.
struct SegmentedRow: View {
    let options: [String]
    let selection: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ChipRow(options: options, selection: selection, onSelect: onSelect)
        }
        .frame(maxWidth: 420)
    }
}

struct ValueSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let text: String
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Slider(value: Binding(get: { value },
                                  set: { onChange($0) }),
                   in: range)
                .accentColor(Design.Palette.accent)
                .frame(width: 160)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(Design.Palette.secondaryInk)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

struct SettingsToggle: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Design.Palette.accent))
    }
}

// MARK: - Emulation

struct EmulationView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var scrollOffset: CGFloat = 0

    private var settings: EmulationSettings { store.global.emulation }

    var body: some View {
        VStack(spacing: 0) {
            CollapsingTitle(title: "Emulation",
                            subtitle: "Defaults for every title. A title can override these from its own page.",
                            offset: scrollOffset)

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    ScrollOffsetReader()

                    column {
                        SettingsCard("Graphics", subtitle: "How the 3DS picture is drawn") {
                            SettingRow("Resolution scale", subtitle: "Applied when playback starts") {
                                SegmentedRow(options: ["1x", "2x", "3x", "4x"],
                                             selection: settings.clampedResolution - 1) { index in
                                    store.updateGlobal { $0.resolutionScale = index + 1 }
                                }
                            }
                            RowDivider()
                            SettingRow("Screen layout", subtitle: "How the two screens are composed") {
                                SegmentedRow(options: PlaybackLayout.allCases.map { $0.title },
                                             selection: PlaybackLayout.allCases.firstIndex(of: settings.layout) ?? 0) { index in
                                    store.updateGlobal { $0.layout = PlaybackLayout.allCases[index] }
                                }
                            }
                            RowDivider()
                            PlaceholderRow(feature: .textureFilter)
                        }
                        .entrance(0)

                        SettingsCard("Performance", subtitle: "How fast the emulated machine runs") {
                            SettingRow("Emulation speed",
                                       subtitle: "How fast playback runs, against real time") {
                                SegmentedRow(options: PlaybackSpeed.allCases.map { $0.title },
                                             selection: PlaybackSpeed.allCases.firstIndex(of: settings.speed) ?? 2) { index in
                                    store.updateGlobal { $0.speed = PlaybackSpeed.allCases[index] }
                                }
                            }
                            RowDivider()
                            SettingRow("3DS CPU clock",
                                       subtitle: "How fast the emulated CPU runs. A separate setting: higher does not make playback faster, it makes the emulated machine faster") {
                                SegmentedRow(options: EmulationSettings.cpuClockChoices.map { "\($0)%" },
                                             selection: EmulationSettings.cpuClockChoices.firstIndex(of: settings.clampedClock) ?? 3) { index in
                                    store.updateGlobal { $0.cpuClockPercent = EmulationSettings.cpuClockChoices[index] }
                                }
                            }
                            RowDivider()
                            PlaceholderRow(feature: .new3DSMode)
                        }
                        .entrance(1)

                        SettingsCard("Region",
                                     subtitle: "Which market the emulated console reports. Region locking is the title's own, so a game that refuses to boot may be one that wants a different market.") {
                            SettingRow("3DS system region",
                                       subtitle: "Read when a game starts: restart a running game to apply it") {
                                SegmentedRow(options: PlaybackRegion.allCases.map { $0.title },
                                             selection: PlaybackRegion.allCases.firstIndex(of: settings.region) ?? 0) { index in
                                    store.updateGlobal { $0.region = PlaybackRegion.allCases[index] }
                                }
                            }
                        }
                        .entrance(2)

                        SettingsCard("Audio", subtitle: "Applies immediately, even mid-game") {
                            SettingRow("Volume") {
                                ValueSlider(value: settings.volume,
                                            range: 0...1,
                                            text: "\(Int(settings.volume * 100))%") { value in
                                    store.updateGlobal { $0.volume = value }
                                }
                            }
                            RowDivider()
                            SettingRow("Mute") {
                                SettingsToggle(isOn: settings.isMuted) { value in
                                    store.updateGlobal { $0.isMuted = value }
                                }
                            }
                        }
                        .entrance(3)

                        SettingsCard("Controls", subtitle: "Opacity and size apply to every layout") {
                            SettingRow("Opacity") {
                                ValueSlider(value: settings.clampedOpacity,
                                            range: 0.25...1,
                                            text: "\(Int(settings.clampedOpacity * 100))%") { value in
                                    store.updateGlobal { $0.controlsOpacity = value }
                                }
                            }
                            RowDivider()
                            SettingRow("Size") {
                                ValueSlider(value: settings.clampedScale,
                                            range: 0.7...1.35,
                                            text: "\(Int(settings.clampedScale * 100))%") { value in
                                    store.updateGlobal { $0.controlsScale = value }
                                }
                            }
                            RowDivider()
                            SettingRow("Haptics") {
                                SettingsToggle(isOn: settings.hapticsEnabled) { value in
                                    store.updateGlobal { $0.hapticsEnabled = value }
                                }
                            }
                        }
                        .entrance(4)

                        SettingsCard("Not available yet",
                                     subtitle: "Real plans, not shipped. Each row turns itself on once the work behind it lands.") {
                            PlaceholderRow(feature: .cheats)
                            RowDivider()
                            PlaceholderRow(feature: .texturePacks)
                            RowDivider()
                            PlaceholderRow(feature: .cameraFeed)
                            RowDivider()
                            PlaceholderRow(feature: .articBase)
                            RowDivider()
                            PlaceholderRow(feature: .cpuJIT)
                        }
                        .entrance(5)
                    }
                }
                // Room for the compact bar when the page scrolls under it.
                .padding(.bottom, Design.Space.xxl * 3)
            }
            .screenScrollSpace()
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
        }
    }

    /// One column, side margins, and a cap so rows do not stretch across ten
    /// inches. The header keeps its own margins, so it sits outside this.
    private func column<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Design.Space.sideMargin)
    }
}

// MARK: - Settings

struct AppSettingsView: View {
    @EnvironmentObject private var library: GameLibrary
    @ObservedObject private var store = SettingsStore.shared
    @State private var usage = SettingsStore.StorageUsage()
    @State private var cacheMessage: String?
    @State private var showsCacheAlert = false
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            CollapsingTitle(title: "Settings",
                            subtitle: "System files, storage and the core",
                            offset: scrollOffset)

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    ScrollOffsetReader()

                    VStack(alignment: .leading, spacing: Design.Space.l) {
                        SettingsCard("System files", subtitle: "What the core reads from Documents/Azahar") {
                            ForEach(library.coreFileStatus()) { status in
                                HStack(alignment: .top, spacing: Design.Space.s) {
                                    Image(systemName: status.present ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(status.present ? Design.Palette.positive : Color.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(status.id)
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                            .foregroundColor(Design.Palette.ink)
                                        Text(status.present ? status.note : "missing · \(status.note)")
                                            .font(Design.Fonts.caption)
                                            .foregroundColor(status.present ? Design.Palette.secondaryInk : Color.orange)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .entrance(0)

                        SettingsCard("Storage", subtitle: "Counted from the app's own folders") {
                            storageRow("ROMs", usage.romsBytes)
                            storageRow("Save data", usage.saveDataBytes)
                            storageRow("Save states", usage.stateBytes)
                            storageRow("Shader cache", usage.cacheBytes)
                            RowDivider()
                            storageRow("Total", usage.totalBytes)

                            Button(action: { showsCacheAlert = true }) {
                                Text("Clear shader cache")
                                    .font(Design.Fonts.caption.weight(.semibold))
                                    .foregroundColor(Design.Palette.ink)
                                    .padding(.horizontal, Design.Space.m)
                                    .frame(height: 36)
                                    .background(Capsule().fill(Design.Palette.card))
                                    .overlay(Capsule().stroke(Design.Palette.hairline, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            .pressHaptic()
                            .padding(.top, Design.Space.xxs)
                        }
                        .entrance(1)

                        SettingsCard("About", subtitle: nil) {
                            SettingRow("Core") {
                                Text(library.coreDescription)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                            RowDivider()
                            SettingRow("Core check") {
                                Text(library.coreStatus)
                                    .font(Design.Fonts.caption)
                                    .foregroundColor(Design.Palette.secondaryInk)
                                    .multilineTextAlignment(.trailing)
                            }
                            Text("3DS emulation powered by Azahar · GPLv3\nFrontend for iPadOS 14.")
                                .font(Design.Fonts.caption)
                                .foregroundColor(Design.Palette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .entrance(2)
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, Design.Space.sideMargin)
                }
                .padding(.bottom, Design.Space.xxl * 3)
            }
            .screenScrollSpace()
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
        }
        .onAppear(perform: refreshUsage)
        .alert(isPresented: $showsCacheAlert) {
            Alert(title: Text("Clear shader cache?"),
                  message: Text("The core will rebuild it as you play. Nothing else is deleted."),
                  primaryButton: .destructive(Text("Clear")) {
                      cacheMessage = store.clearShaderCache(coreDirectory: library.coreDirectory)
                      refreshUsage()
                  },
                  secondaryButton: .cancel())
        }
        .overlay(
            Group {
                if let message = cacheMessage {
                    Text(message)
                        .font(Design.Fonts.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, Design.Space.m)
                        .padding(.vertical, Design.Space.xs)
                        .background(Capsule().fill(Design.Palette.ink.opacity(0.9)))
                        .padding(.bottom, 120)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                if cacheMessage == message { cacheMessage = nil }
                            }
                        }
                }
            }
        )
    }

    private func storageRow(_ title: String, _ bytes: Int64) -> some View {
        HStack {
            Text(title)
                .font(Design.Fonts.rowTitle)
                .foregroundColor(Design.Palette.ink)
            Spacer()
            Text(SettingsStore.StorageUsage.format(bytes))
                .font(Design.Fonts.cellMeta)
                .foregroundColor(Design.Palette.secondaryInk)
        }
        .frame(minHeight: 44)
    }

    private func refreshUsage() {
        usage = store.storageUsage(romsDirectory: library.romsDirectory,
                                   coreDirectory: library.coreDirectory)
    }
}
