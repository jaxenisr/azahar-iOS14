import SwiftUI

@main
struct AzaharApp: App {
    @StateObject private var library = GameLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
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
