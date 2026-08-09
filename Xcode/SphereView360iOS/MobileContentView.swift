import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MobileContentView: View {
    @ObservedObject var store: ViewerStore
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var isImporting = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if store.hasMedia {
                SceneKit360VideoView(player: store.player, image: store.image, resetID: store.viewResetID)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MobileHeader(title: store.displayName, resetAction: store.requestViewReset)
                    Spacer()

                    if store.hasVideo {
                        MobilePlaybackBar(store: store)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                MobileEmptyState(
                    selectedMediaItem: $selectedMediaItem,
                    openFilesAction: { isFileImporterPresented = true }
                )
            }

            if isImporting {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(18)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .task(id: selectedMediaItem) {
            guard let selectedMediaItem else {
                return
            }

            await loadPhotosMedia(selectedMediaItem)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: SupportedVideoTypes.openPanelTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
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

    @MainActor
    private func loadPhotosMedia(_ item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            selectedMediaItem = nil
        }

        do {
            guard let media = try await item.loadTransferable(type: PickedMedia.self) else {
                store.alertMessage = "Photos did not provide a playable 360 video or image."
                return
            }

            store.open(media.url)
        } catch {
            store.alertMessage = error.localizedDescription
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            let temporaryURL = try SharedVideoLoader.copyMediaToTemporaryLocation(url)
            store.open(temporaryURL)
        } catch {
            store.alertMessage = error.localizedDescription
        }
    }
}

private struct MobileHeader: View {
    let title: String
    let resetAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            Button(action: resetAction) {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }
}

private struct MobileEmptyState: View {
    @Binding var selectedMediaItem: PhotosPickerItem?
    let openFilesAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "view.3d")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))

            VStack(spacing: 6) {
                Text("Open a 360 video or image")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Equirectangular MP4, MOV, INSV, JPEG, PNG, HEIC, or TIFF")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedMediaItem, matching: .any(of: [.videos, .images])) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                Button(action: openFilesAction) {
                    Label("Files", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(26)
    }
}

private struct MobilePlaybackBar: View {
    @ObservedObject var store: ViewerStore
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.togglePlayback()
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Text(TimeFormatter.clockTime(isScrubbing ? scrubTime : store.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 48, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : store.currentTime },
                    set: { newValue in
                        scrubTime = newValue
                    }
                ),
                in: 0...max(store.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        store.seek(to: scrubTime)
                    }
                }
            )
            .tint(.white)

            Text(TimeFormatter.clockTime(store.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 48, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { media in
            SentTransferredFile(media.url)
        } importing: { received in
            let copiedURL = try SharedVideoLoader.copyMediaToTemporaryLocation(
                received.file,
                fallbackExtension: "mov"
            )
            return PickedMedia(url: copiedURL)
        }

        FileRepresentation(contentType: .image) { media in
            SentTransferredFile(media.url)
        } importing: { received in
            let copiedURL = try SharedVideoLoader.copyMediaToTemporaryLocation(
                received.file,
                fallbackExtension: "jpg"
            )
            return PickedMedia(url: copiedURL)
        }
    }
}
