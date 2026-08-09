import AppKit

enum VideoOpenPanel {
    @MainActor
    static func chooseMedia() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open 360 Media"
        panel.message = "Choose an equirectangular 360 video or image."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = SupportedVideoTypes.openPanelTypes

        return panel.runModal() == .OK ? panel.url : nil
    }
}
