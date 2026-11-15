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

struct RootView: View {
    @State private var tab: RootTab = .games

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .games:
                    LibraryView()
                case .emulation:
                    EmulationView()
                case .settings:
                    AppSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: $tab)
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
    }
}

struct TabBar: View {
    @Binding var selection: RootTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RootTab.allCases) { item in
                Button(action: { selection = item }) {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        if selection == item {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundColor(selection == item ? .white : .white.opacity(0.45))
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Capsule().fill(selection == item ? Color.white.opacity(0.14) : Color.clear))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(item.title)
            }
        }
        .padding(6)
        .background(BlurBackdrop(style: .systemThinMaterialDark).clipShape(Capsule()))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.bottom, 10)
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundColor(.white.opacity(0.42))
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

struct SegmentedRow: View {
    let options: [String]
    let selection: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                Button(action: { onSelect(index) }) {
                    Text(options[index])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selection == index ? .black : .white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            Capsule().fill(selection == index
                                           ? Color.white.opacity(0.88)
                                           : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct ValueSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let text: String
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(get: { value },
                                  set: { onChange($0) }),
                   in: range)
                .accentColor(.white.opacity(0.85))
                .frame(width: 160)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
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
            .toggleStyle(SwitchToggleStyle(tint: Color.white.opacity(0.75)))
    }
}

// MARK: - Emulation

struct EmulationView: View {
    @ObservedObject private var store = SettingsStore.shared

    private var settings: EmulationSettings { store.global.emulation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Emulation",
                             subtitle: "Defaults for every title. A title can override these from its own page.")

                SettingsCard("Graphics") {
                    SettingRow("Resolution scale", subtitle: "Applied when playback starts") {
                        SegmentedRow(options: ["1x", "2x", "3x", "4x"],
                                     selection: settings.clampedResolution - 1) { index in
                            store.updateGlobal { $0.resolutionScale = index + 1 }
                        }
                    }
                    SettingRow("Screen layout", subtitle: "How the two screens are composed") {
                        SegmentedRow(options: PlaybackLayout.allCases.map { $0.title },
                                     selection: PlaybackLayout.allCases.firstIndex(of: settings.layout) ?? 0) { index in
                            store.updateGlobal { $0.layout = PlaybackLayout.allCases[index] }
                        }
                    }
                }

                SettingsCard("Performance") {
                    SettingRow("Emulation speed",
                               subtitle: "How fast playback runs, against real time") {
                        SegmentedRow(options: PlaybackSpeed.allCases.map { $0.title },
                                     selection: PlaybackSpeed.allCases.firstIndex(of: settings.speed) ?? 2) { index in
                            store.updateGlobal { $0.speed = PlaybackSpeed.allCases[index] }
                        }
                    }
                    SettingRow("3DS CPU clock",
                               subtitle: "How fast the emulated CPU runs. A separate setting: higher does not make playback faster, it makes the emulated machine faster") {
                        SegmentedRow(options: EmulationSettings.cpuClockChoices.map { "\($0)%" },
                                     selection: EmulationSettings.cpuClockChoices.firstIndex(of: settings.clampedClock) ?? 3) { index in
                            store.updateGlobal { $0.cpuClockPercent = EmulationSettings.cpuClockChoices[index] }
                        }
                    }
                }

                SettingsCard("Audio") {
                    SettingRow("Volume", subtitle: "Applies immediately, even mid-game") {
                        ValueSlider(value: settings.volume,
                                    range: 0...1,
                                    text: "\(Int(settings.volume * 100))%") { value in
                            store.updateGlobal { $0.volume = value }
                        }
                    }
                    SettingRow("Mute", subtitle: nil) {
                        SettingsToggle(isOn: settings.isMuted) { value in
                            store.updateGlobal { $0.isMuted = value }
                        }
                    }
                }

                SettingsCard("Controls") {
                    SettingRow("Opacity", subtitle: nil) {
                        ValueSlider(value: settings.clampedOpacity,
                                    range: 0.25...1,
                                    text: "\(Int(settings.clampedOpacity * 100))%") { value in
                            store.updateGlobal { $0.controlsOpacity = value }
                        }
                    }
                    SettingRow("Size", subtitle: nil) {
                        ValueSlider(value: settings.clampedScale,
                                    range: 0.7...1.35,
                                    text: "\(Int(settings.clampedScale * 100))%") { value in
                            store.updateGlobal { $0.controlsScale = value }
                        }
                    }
                    SettingRow("Haptics", subtitle: nil) {
                        SettingsToggle(isOn: settings.hapticsEnabled) { value in
                            store.updateGlobal { $0.hapticsEnabled = value }
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 96)
        }
    }
}

// MARK: - Settings

struct AppSettingsView: View {
    @EnvironmentObject private var library: GameLibrary
    @ObservedObject private var store = SettingsStore.shared
    @State private var usage = SettingsStore.StorageUsage()
    @State private var cacheMessage: String?
    @State private var showsCacheAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Settings", subtitle: "System files, storage and the core")

                SettingsCard("System files") {
                    ForEach(library.coreFileStatus()) { status in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: status.present ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(status.present ? Color.green.opacity(0.85) : Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.id)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.88))
                                Text(status.present ? status.note : "missing · \(status.note)")
                                    .font(.system(size: 11))
                                    .foregroundColor(status.present ? .white.opacity(0.42) : .orange.opacity(0.9))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                SettingsCard("Storage") {
                    storageRow("ROMs", usage.romsBytes)
                    storageRow("Save data", usage.saveDataBytes)
                    storageRow("Save states", usage.stateBytes)
                    storageRow("Shader cache", usage.cacheBytes)
                    Divider().background(Color.white.opacity(0.08))
                    storageRow("Total", usage.totalBytes)

                    Button(action: { showsCacheAlert = true }) {
                        Text("Clear shader cache")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .padding(.top, 4)
                }

                SettingsCard("About") {
                    SettingRow("Core", subtitle: nil) {
                        Text(library.coreDescription)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("3DS emulation powered by Azahar · GPLv3\nFrontend for iPadOS 14.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 96)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .padding(.bottom, 90)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text(SettingsStore.StorageUsage.format(bytes))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func refreshUsage() {
        usage = store.storageUsage(romsDirectory: library.romsDirectory,
                                   coreDirectory: library.coreDirectory)
    }
}
