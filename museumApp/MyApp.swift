import SwiftUI

@main struct MyApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
