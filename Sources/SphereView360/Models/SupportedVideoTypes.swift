import Foundation
import UniformTypeIdentifiers

enum SupportedVideoTypes {
    enum MediaKind {
        case video
        case image
    }

    struct ContentType: Identifiable {
        let id: String
        let filenameExtension: String
        let displayName: String
    }

    static let videoFilenameExtensions: Set<String> = [
        "mp4",
        "m4v",
        "mov",
        "insv"
    ]

    static let imageFilenameExtensions: Set<String> = [
        "jpg",
        "jpeg",
        "png",
        "heic",
        "heif",
        "tif",
        "tiff"
    ]

    static let filenameExtensions = videoFilenameExtensions.union(imageFilenameExtensions)

    static let defaultOpenContentTypes: [ContentType] = [
        ContentType(id: "public.mpeg-4", filenameExtension: "mp4", displayName: "MP4"),
        ContentType(id: "com.apple.m4v-video", filenameExtension: "m4v", displayName: "M4V"),
        ContentType(id: "com.apple.quicktime-movie", filenameExtension: "mov", displayName: "MOV"),
        ContentType(id: "dev.local.insv", filenameExtension: "insv", displayName: "INSV"),
        ContentType(id: "public.jpeg", filenameExtension: "jpg", displayName: "JPEG"),
        ContentType(id: "public.png", filenameExtension: "png", displayName: "PNG"),
        ContentType(id: "public.heic", filenameExtension: "heic", displayName: "HEIC"),
        ContentType(id: "public.tiff", filenameExtension: "tif", displayName: "TIFF")
    ]

    static var openPanelTypes: [UTType] {
        var types: [UTType] = [
            .image,
            .jpeg,
            .png,
            .tiff,
            .movie,
            .mpeg4Movie,
            .quickTimeMovie
        ]

        for imageExtension in ["heic", "heif"] {
            if let imageType = UTType(filenameExtension: imageExtension) {
                types.append(imageType)
            }
        }

        if let m4v = UTType(filenameExtension: "m4v") {
            types.append(m4v)
        }

        if let insta360 = UTType(filenameExtension: "insv") {
            types.append(insta360)
        }

        return types
    }

    static var dropTypeIdentifiers: [String] {
        [
            UTType.fileURL.identifier
        ]
    }

    static func isLikelyVideo(_ url: URL) -> Bool {
        mediaKind(for: url) == .video
    }

    static func isLikelyImage(_ url: URL) -> Bool {
        mediaKind(for: url) == .image
    }

    static func isLikelyMedia(_ url: URL) -> Bool {
        mediaKind(for: url) != nil
    }

    static func mediaKind(for url: URL) -> MediaKind? {
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else {
            return nil
        }

        if videoFilenameExtensions.contains(fileExtension) {
            return .video
        }

        if imageFilenameExtensions.contains(fileExtension) {
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
}
