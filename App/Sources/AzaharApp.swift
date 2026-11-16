import SwiftUI

@main
struct AzaharApp: App {
    @StateObject private var library = GameLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                // The pages are light by design and the player supplies its own
                // dark colours, so the app declares light: without this every
                // system control — a menu, a picker, a switch — arrives in the
                // device's dark appearance over a white card.
                .preferredColorScheme(.light)
                .onAppear {
                    // So an exception that does get past a guard leaves its name and
                    // reason in the log instead of only in a crash report.
                    AZInstallExceptionHandler()
                    library.reload()
                    library.runCoreCheck()
                    AudioOutput.shared.prepare()
                }
        }
    }
}
