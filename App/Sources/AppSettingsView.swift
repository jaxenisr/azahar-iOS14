import SwiftUI
import UIKit

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
