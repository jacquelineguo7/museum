import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if library.isOpen {
                MainView()
            } else {
                WelcomeView()
            }
        }
        .task { await library.restoreLibrary() }
        // Pick up edits made outside the app (Finder, a text editor, a sync client).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, library.isOpen {
                Task { try? await library.reload() }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }
}

/// Shown until a library folder has been chosen.
struct WelcomeView: View {
    @Environment(LibraryModel.self) private var library
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Museum")
                .font(.system(.largeTitle, design: .serif))
            Text("Everything you save is kept as plain files in a folder you choose, so it's always yours.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Button("Choose Library Folder…") { isChoosingFolder = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Text("Pick an existing library, or make a new empty folder.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task { await library.openLibrary(at: url) }
            case .failure(let error):
                library.errorMessage = error.localizedDescription
            }
        }
    }
}
