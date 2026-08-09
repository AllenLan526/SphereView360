import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ViewerStore
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if store.hasMedia {
                SceneKit360VideoView(player: store.player, image: store.image, resetID: store.viewResetID)
                    .ignoresSafeArea()
            } else {
                EmptyStateView {
                    store.presentOpenPanel()
                } makeDefaultAction: {
                    store.registerOpenWithOption()
                }
            }

            if store.hasMedia {
                VStack(spacing: 0) {
                    HeaderOverlay(title: store.displayName)
                    Spacer()

                    if store.hasVideo {
                        PlaybackBar(store: store)
                    }
                }
                .padding(16)
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .background(.black.opacity(0.18))
                    .padding(18)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentOpenPanel()
                } label: {
                    Label("Open Media", systemImage: "folder")
                }

                Button {
                    store.requestViewReset()
                } label: {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
                .disabled(!store.hasMedia)

                Button {
                    store.registerOpenWithOption()
                } label: {
                    Label("Add to Open With", systemImage: "doc.badge.gearshape")
                }
            }
        }
        .onDrop(
            of: SupportedVideoTypes.dropTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: handleDrop(providers:)
        )
        .alert(
            "SphereView360",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.alertMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?

            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }

            guard let url else {
                return
            }

            Task { @MainActor in
                store.open(url)
            }
        }

        return true
    }
}

private struct HeaderOverlay: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
    }
}

private struct EmptyStateView: View {
    let openAction: () -> Void
    let makeDefaultAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "view.3d")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))

            VStack(spacing: 5) {
                Text("Drop a 360 video or image")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Equirectangular MP4, MOV, INSV, JPEG, PNG, HEIC, or TIFF files")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 10) {
                Button {
                    openAction()
                } label: {
                    Label("Open Media", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    makeDefaultAction()
                } label: {
                    Label("Add to Open With", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
    }
}
