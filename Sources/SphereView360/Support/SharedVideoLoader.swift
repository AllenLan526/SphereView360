@preconcurrency import Foundation
import UniformTypeIdentifiers

enum SharedVideoLoader {
    enum LoadedMedia: @unchecked Sendable {
        case video(URL)
        case image(PlatformImage)
    }

    typealias MediaLoadCompletion = (Result<LoadedMedia, Error>) -> Void
    typealias VideoLoadCompletion = (Result<URL, Error>) -> Void

    private enum MediaKind {
        case video
        case image
    }

    private final class Candidate: @unchecked Sendable {
        let provider: NSItemProvider
        let typeIdentifier: String
        let suggestedName: String?
        let mediaKind: MediaKind?
        let fallbackExtension: String

        init(provider: NSItemProvider, typeIdentifier: String) {
            self.provider = provider
            self.typeIdentifier = typeIdentifier
            suggestedName = provider.suggestedName
            mediaKind = Self.mediaKind(forTypeIdentifier: typeIdentifier)
            fallbackExtension = Self.fallbackExtension(forTypeIdentifier: typeIdentifier, mediaKind: mediaKind)
        }

        private static func mediaKind(forTypeIdentifier typeIdentifier: String) -> MediaKind? {
            if typeIdentifier == UTType.fileURL.identifier {
                return nil
            }

            if typeIdentifier == "dev.local.insv" {
                return .video
            }

            guard let contentType = UTType(typeIdentifier) else {
                return nil
            }

            if contentType.conforms(to: .movie) {
                return .video
            }

            if contentType.conforms(to: .image) {
                return .image
            }

            return nil
        }

        private static func fallbackExtension(
            forTypeIdentifier typeIdentifier: String,
            mediaKind: MediaKind?
        ) -> String {
            if typeIdentifier == "dev.local.insv" {
                return "insv"
            }

            if let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension {
                return preferredExtension
            }

            switch mediaKind {
            case .video:
                return "mov"
            case .image:
                return "jpg"
            case nil:
                return "mov"
            }
        }
    }

    private final class LoadState: @unchecked Sendable {
        let candidates: [Candidate]
        let completion: MediaLoadCompletion

        init(candidates: [Candidate], completion: @escaping MediaLoadCompletion) {
            self.candidates = candidates
            self.completion = completion
        }
    }

    enum LoaderError: LocalizedError {
        case noMediaAttachment
        case noVideoAttachment
        case unsupportedItem
        case unreadableImage

        var errorDescription: String? {
            switch self {
            case .noMediaAttachment:
                return "No shared video or image was found."
            case .noVideoAttachment:
                return "No shared video was found."
            case .unsupportedItem:
                return "The shared item could not be opened as a supported 360 video or image."
            case .unreadableImage:
                return "The shared image could not be read."
            }
        }
    }

    static var acceptedTypeIdentifiers: [String] {
        [
            UTType.fileURL.identifier
        ] + acceptedVideoTypeIdentifiers + acceptedImageTypeIdentifiers
    }

    static var acceptedVideoTypeIdentifiers: [String] {
        var identifiers = [
            UTType.movie.identifier,
            UTType.mpeg4Movie.identifier,
            UTType.quickTimeMovie.identifier
        ]

        if let m4v = UTType(filenameExtension: "m4v")?.identifier {
            identifiers.append(m4v)
        }

        if let insta360 = UTType(filenameExtension: "insv")?.identifier {
            identifiers.append(insta360)
        }

        return identifiers
    }

    static var acceptedImageTypeIdentifiers: [String] {
        var identifiers = [
            UTType.image.identifier,
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.tiff.identifier
        ]

        for imageExtension in ["heic", "heif"] {
            if let identifier = UTType(filenameExtension: imageExtension)?.identifier {
                identifiers.append(identifier)
            }
        }

        return identifiers
    }

    static func loadFirstMedia(
        from extensionContext: NSExtensionContext?,
        completion: @escaping MediaLoadCompletion
    ) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        loadFirstMedia(from: providers, completion: completion)
    }

    static func loadFirstMedia(
        from providers: [NSItemProvider],
        completion: @escaping MediaLoadCompletion
    ) {
        let candidates: [Candidate] = providers.flatMap { provider in
            acceptedTypeIdentifiers.compactMap { identifier in
                provider.hasItemConformingToTypeIdentifier(identifier)
                    ? Candidate(provider: provider, typeIdentifier: identifier)
                    : nil
            }
        }

        guard !candidates.isEmpty else {
            completion(.failure(LoaderError.noMediaAttachment))
            return
        }

        loadFirstWorkingCandidate(LoadState(candidates: candidates, completion: completion), index: 0)
    }

    static func loadFirstVideoURL(
        from extensionContext: NSExtensionContext?,
        completion: @escaping VideoLoadCompletion
    ) {
        loadFirstMedia(from: extensionContext) { result in
            completion(videoResult(from: result))
        }
    }

    static func loadFirstVideoURL(
        from providers: [NSItemProvider],
        completion: @escaping VideoLoadCompletion
    ) {
        loadFirstMedia(from: providers) { result in
            completion(videoResult(from: result))
        }
    }

    static func copyVideoToTemporaryLocation(_ sourceURL: URL, preferredFilename: String? = nil) throws -> URL {
        try copyMediaToTemporaryLocation(
            sourceURL,
            preferredFilename: preferredFilename,
            fallbackExtension: "mov"
        )
    }

    static func copyMediaToTemporaryLocation(
        _ sourceURL: URL,
        preferredFilename: String? = nil,
        fallbackExtension: String = "mov"
    ) throws -> URL {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension.isEmpty ? fallbackExtension : sourceURL.pathExtension
        let rawBaseName = preferredFilename ?? sourceURL.deletingPathExtension().lastPathComponent
        let baseName = rawBaseName.isEmpty ? "SphereView360Media" : rawBaseName
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func videoResult(from result: Result<LoadedMedia, Error>) -> Result<URL, Error> {
        switch result {
        case .success(.video(let url)):
            return .success(url)
        case .success(.image):
            return .failure(LoaderError.noVideoAttachment)
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func loadFirstWorkingCandidate(
        _ state: LoadState,
        index: Int
    ) {
        guard index < state.candidates.count else {
            state.completion(.failure(LoaderError.unsupportedItem))
            return
        }

        let candidate = state.candidates[index]
        let provider = candidate.provider
        let typeIdentifier = candidate.typeIdentifier

        if typeIdentifier == UTType.fileURL.identifier {
            loadItemURL(from: candidate, state: state, index: index)
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
            if let url {
                do {
                    let loadedMedia = try loadedMedia(fromFileAt: url, candidate: candidate)
                    state.completion(.success(loadedMedia))
                } catch {
                    handleCandidateResult(
                        .failure(error),
                        state: state,
                        index: index,
                    )
                }
                return
            }

            if let error {
                handleCandidateResult(
                    .failure(error),
                    state: state,
                    index: index,
                )
                return
            }

            loadItemURL(from: candidate, state: state, index: index)
        }
    }

    private static func loadItemURL(
        from candidate: Candidate,
        state: LoadState,
        index: Int
    ) {
        candidate.provider.loadItem(forTypeIdentifier: candidate.typeIdentifier, options: nil) { item, error in
            if let error {
                handleCandidateResult(.failure(error), state: state, index: index)
                return
            }

            do {
                let media = try temporaryMedia(from: item, candidate: candidate)
                handleCandidateResult(.success(media), state: state, index: index)
            } catch {
                handleCandidateResult(.failure(error), state: state, index: index)
            }
        }
    }

    private static func temporaryMedia(from item: NSSecureCoding?, candidate: Candidate) throws -> LoadedMedia {
        if let url = item as? URL {
            return try loadedMedia(fromFileAt: url, candidate: candidate)
        }

        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            return try loadedMedia(fromFileAt: url, candidate: candidate)
        }

        if let data = item as? Data {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(candidate.suggestedName ?? "SphereView360Media")-\(UUID().uuidString)")
                .appendingPathExtension(candidate.fallbackExtension)

            try data.write(to: destination, options: .atomic)
            return try loadedMedia(fromFileAt: destination, candidate: candidate)
        }

        if let image = item as? PlatformImage {
            return .image(image)
        }

        throw LoaderError.unsupportedItem
    }

    private static func loadedMedia(fromFileAt url: URL, candidate: Candidate) throws -> LoadedMedia {
        let copiedURL = try copyMediaToTemporaryLocation(
            url,
            preferredFilename: candidate.suggestedName,
            fallbackExtension: candidate.fallbackExtension
        )
        let kind = mediaKind(forFileAt: copiedURL) ?? candidate.mediaKind

        switch kind {
        case .video:
            return .video(copiedURL)
        case .image:
            guard let image = loadImage(from: copiedURL) else {
                throw LoaderError.unreadableImage
            }
            return .image(image)
        case nil:
            throw LoaderError.unsupportedItem
        }
    }

    private static func mediaKind(forFileAt url: URL) -> MediaKind? {
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else {
            return nil
        }

        if ["mp4", "m4v", "mov", "insv"].contains(fileExtension) {
            return .video
        }

        if ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"].contains(fileExtension) {
            return .image
        }

        guard let contentType = UTType(filenameExtension: fileExtension) else {
            return nil
        }

        if contentType.conforms(to: .movie) {
            return .video
        }

        if contentType.conforms(to: .image) {
            return .image
        }

        return nil
    }

    private static func loadImage(from url: URL) -> PlatformImage? {
        #if os(macOS)
        PlatformImage(contentsOf: url)
        #elseif os(iOS)
        PlatformImage(contentsOfFile: url.path)
        #endif
    }

    private static func handleCandidateResult(
        _ result: Result<LoadedMedia, Error>,
        state: LoadState,
        index: Int
    ) {
        switch result {
        case .success(let media):
            state.completion(.success(media))
        case .failure:
            loadFirstWorkingCandidate(state, index: index + 1)
        }
    }
}
