import AVFoundation
import SceneKit
import SwiftUI

#if os(macOS)
import AppKit
private typealias PlatformColor = NSColor
#elseif os(iOS)
import UIKit
private typealias PlatformColor = UIColor
#endif

#if os(macOS)
struct SceneKit360VideoView: NSViewRepresentable {
    let player: AVPlayer?
    let resetID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(resetID: resetID)
    }

    func makeNSView(context: Context) -> SphereSceneView {
        let view = SphereSceneView(frame: .zero)
        view.setPlayer(player)
        return view
    }

    func updateNSView(_ nsView: SphereSceneView, context: Context) {
        nsView.setPlayer(player)

        if context.coordinator.resetID != resetID {
            context.coordinator.resetID = resetID
            nsView.resetCamera(animated: true)
        }
    }

    final class Coordinator {
        var resetID: UUID

        init(resetID: UUID) {
            self.resetID = resetID
        }
    }
}
#elseif os(iOS)
struct SceneKit360VideoView: UIViewRepresentable {
    let player: AVPlayer?
    let resetID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(resetID: resetID)
    }

    func makeUIView(context: Context) -> SphereSceneView {
        let view = SphereSceneView(frame: .zero)
        view.setPlayer(player)
        return view
    }

    func updateUIView(_ uiView: SphereSceneView, context: Context) {
        uiView.setPlayer(player)

        if context.coordinator.resetID != resetID {
            context.coordinator.resetID = resetID
            uiView.resetCamera(animated: true)
        }
    }

    final class Coordinator {
        var resetID: UUID

        init(resetID: UUID) {
            self.resetID = resetID
        }
    }
}
#endif

final class SphereSceneView: SCNView {
    private enum CameraControl {
        static let mouseDragRadiansPerPoint: CGFloat = 0.006
        static let preciseScrollRadiansPerPoint: CGFloat = 0.0045
        static let wheelScrollRadiansPerPoint: CGFloat = 0.06
        static let keyStepRadians: CGFloat = 0.08
        static let magnifyFieldOfViewScale: CGFloat = 28
        static let minimumPitch: CGFloat = -.pi / 2 + 0.04
        static let maximumPitch: CGFloat = .pi / 2 - 0.04
        static let minimumFieldOfView: CGFloat = 35
        static let maximumFieldOfView: CGFloat = 104
        static let defaultFieldOfView: CGFloat = 76
    }

    private let sphereMaterial = SCNMaterial()
    private let yawNode = SCNNode()
    private let pitchNode = SCNNode()
    private let cameraNode = SCNNode()
    private weak var currentPlayer: AVPlayer?
    private var yaw: CGFloat = 0
    private var pitch: CGFloat = 0
    private var fieldOfView: CGFloat = CameraControl.defaultFieldOfView

    #if os(macOS)
    private var lastDragLocation: NSPoint?
    #endif

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        configureScene()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScene()
    }

    #if os(macOS)
    override var acceptsFirstResponder: Bool {
        true
    }
    #endif

    func setPlayer(_ player: AVPlayer?) {
        guard currentPlayer !== player else {
            return
        }

        currentPlayer = player

        if let player {
            sphereMaterial.diffuse.contents = player
        } else {
            sphereMaterial.diffuse.contents = PlatformColor.black
        }
    }

    func resetCamera(animated: Bool) {
        yaw = 0
        pitch = 0
        fieldOfView = CameraControl.defaultFieldOfView

        guard animated else {
            applyCamera()
            return
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.18
        applyCamera()
        SCNTransaction.commit()
    }

    private func configureScene() {
        #if os(macOS)
        wantsLayer = true
        #endif

        backgroundColor = .black
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        isPlaying = true
        rendersContinuously = true

        let scene = SCNScene()
        self.scene = scene

        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 160

        sphereMaterial.lightingModel = .constant
        sphereMaterial.isDoubleSided = false
        sphereMaterial.cullMode = .front
        sphereMaterial.diffuse.contents = PlatformColor.black
        sphereMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
        sphereMaterial.diffuse.wrapS = .repeat
        sphereMaterial.diffuse.wrapT = .clamp

        sphere.firstMaterial = sphereMaterial

        let sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 100
        camera.fieldOfView = fieldOfView

        cameraNode.camera = camera
        cameraNode.position = SCNVector3Zero
        pitchNode.addChildNode(cameraNode)
        yawNode.addChildNode(pitchNode)
        scene.rootNode.addChildNode(yawNode)

        pointOfView = cameraNode
        configurePlatformInput()
        applyCamera()
    }

    private func configurePlatformInput() {
        #if os(iOS)
        isUserInteractionEnabled = true

        let oneFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleOneFingerPan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.delegate = self
        addGestureRecognizer(oneFingerPan)

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = self
        addGestureRecognizer(twoFingerPan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        #endif
    }

    private func applyCamera() {
        yawNode.eulerAngles = SCNVector3(0, Float(yaw), 0)
        pitchNode.eulerAngles = SCNVector3(Float(pitch), 0, 0)
        cameraNode.camera?.fieldOfView = fieldOfView
    }

    private func rotateCamera(deltaX: CGFloat, deltaY: CGFloat, sensitivity: CGFloat) {
        yaw += deltaX * sensitivity
        pitch -= deltaY * sensitivity
        pitch = min(max(pitch, CameraControl.minimumPitch), CameraControl.maximumPitch)
        applyCamera()
    }

    private func zoomCamera(delta: CGFloat) {
        fieldOfView -= delta
        fieldOfView = min(
            max(fieldOfView, CameraControl.minimumFieldOfView),
            CameraControl.maximumFieldOfView
        )
        applyCamera()
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragLocation = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.locationInWindow
        guard let lastDragLocation else {
            self.lastDragLocation = location
            return
        }

        let deltaX = location.x - lastDragLocation.x
        let deltaY = location.y - lastDragLocation.y
        self.lastDragLocation = location
        rotateCamera(
            deltaX: deltaX,
            deltaY: deltaY,
            sensitivity: CameraControl.mouseDragRadiansPerPoint
        )
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
        NSCursor.openHand.set()
    }

    override func scrollWheel(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let sensitivity = event.hasPreciseScrollingDeltas
            ? CameraControl.preciseScrollRadiansPerPoint
            : CameraControl.wheelScrollRadiansPerPoint

        rotateCamera(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            sensitivity: sensitivity
        )
    }

    override func magnify(with event: NSEvent) {
        window?.makeFirstResponder(self)
        zoomCamera(delta: event.magnification * CameraControl.magnifyFieldOfViewScale)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            yaw -= CameraControl.keyStepRadians
        case 124:
            yaw += CameraControl.keyStepRadians
        case 125:
            pitch -= CameraControl.keyStepRadians
        case 126:
            pitch += CameraControl.keyStepRadians
        case 15:
            resetCamera(animated: true)
            return
        default:
            super.keyDown(with: event)
            return
        }

        pitch = min(max(pitch, CameraControl.minimumPitch), CameraControl.maximumPitch)
        applyCamera()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
    #elseif os(iOS)
    @objc private func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        rotateCamera(
            deltaX: translation.x,
            deltaY: -translation.y,
            sensitivity: CameraControl.mouseDragRadiansPerPoint
        )
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        rotateCamera(
            deltaX: translation.x,
            deltaY: -translation.y,
            sensitivity: CameraControl.preciseScrollRadiansPerPoint
        )
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let scaleDelta = recognizer.scale - 1
        zoomCamera(delta: scaleDelta * CameraControl.magnifyFieldOfViewScale)
        recognizer.scale = 1
    }
    #endif
}

#if os(iOS)
extension SphereSceneView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
