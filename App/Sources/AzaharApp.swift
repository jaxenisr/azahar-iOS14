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
                    library.reload()
                    library.runCoreCheck()
                    AudioOutput.shared.prepare()
                }
        }
    }
}
