# SphereView360

SphereView360 is a native Apple-platform prototype for quickly previewing equirectangular 360 videos and photos. It maps the media onto the inside of a sphere and lets you look around with left-click drag, two-finger trackpad scroll, arrow keys, and pinch zoom on macOS, plus touch gestures on iPhone and iPad.

## Run

```bash
./script/build_and_run.sh
```

The script builds the Xcode app project, stages `dist/SphereView360.app`, and opens it. The Codex app Run action is wired to the same script through `.codex/environments/environment.toml`.

To install the Finder `Open With` handler, the Photos.app edit extension, and the macOS Share extension:

```bash
./script/build_and_run.sh --install-integrations
```

To compile the iPhone/iPad simulator app:

```bash
./script/build_and_run.sh --build-ios-simulator
```

## macOS integration

- `File > Open 360 Media...` and `Command-O`
- Drag video or image files from Finder into the window
- Finder/Open With support from the generated app bundle
- `Add to Open With` registers SphereView360 as an alternate app for compatible videos and images
- Double-click/Open-With handoff through `NSApplicationDelegate.application(_:open:)`
- Document metadata for common movie and image types, including MP4, M4V, MOV, compatible `.insv`, JPEG, PNG, HEIC, and TIFF
- Photos.app edit extension for opening videos or images from Photos' edit extension menu
- Share extension for videos or images from macOS share sheets, including Photos' right-click `Share` menu

macOS default app settings are based on file type, not 360 metadata. SphereView360 should be used as an `Open With` option for MP4/M4V/MOV unless you intentionally want to change the default app for every file of that type.

## Photos.app

The Xcode project embeds `SphereView360PhotosExtension.appex`, a `com.apple.photo-editing` extension that supports Photos video and image assets. It is currently a read-only preview extension: it displays the selected Photos asset in the same 360 viewer and returns no edits back to Photos.

After installing integrations, open Photos, select a video or 360 image, enter Edit, then choose SphereView360 from the Extensions menu. If Photos was already running during install, quit and reopen Photos so it refreshes the PluginKit extension registry.

For the right-click flow, select or right-click a video or image in Photos, choose `Share`, then choose SphereView360. Apple does not expose a public API for third-party apps to inject arbitrary top-level items directly into Photos' context menu, so the Share submenu is the supported system surface for this.

## iPhone and iPad

The Xcode project includes a `SphereView360iOS` app target and an iOS Share extension. The mobile app opens videos and images from Photos or Files, supports iPhone and iPad orientations, and uses touch controls: one-finger drag to look around, two-finger drag to pan the view, and pinch to zoom.

On iPhone or iPad, the share extension is the Photos integration path: select a video or image in Photos, tap Share, then choose SphereView360.

## Media support

This prototype assumes the media is already equirectangular, which is the usual format for exported 360 MP4/MOV videos and 360 JPEG/PNG/HEIC/TIFF photos. Raw dual-fisheye Insta360 `.insv` footage may need to be stitched/exported first unless AVFoundation can decode it as a normal equirectangular movie.
