import AppKit
import CoreMedia
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "com.thomasmelak.LidBlur", category: "capture")

/// A live copy of the built-in display (without this app's own windows), drawn into `layer`.
/// The overlay uses it to redraw the screen scaled and tilted back while the lid is folded,
/// which an overlay on top of other apps' windows cannot do otherwise. Needs Screen Recording.
@MainActor
final class ScreenMirror: NSObject {
    let layer = CALayer()
    /// True once a frame is showing; until then the overlay keeps its plain backdrop blur.
    private(set) var hasFrame = false

    private var stream: SCStream?
    private var starting = false
    private var wanted = false
    private let output = FrameOutput()
    /// After a failed start, wait before trying again instead of retrying every frame.
    private var retryAfter: CFTimeInterval = 0
    private var frameCount = 0

    /// What the capture is doing, shown in the menu so a silent failure is visible.
    private(set) var status = "idle"

    private static var permissionCache: (granted: Bool, checked: CFTimeInterval)?

    /// Screen Recording access, re-checked at most every two seconds (it is asked every frame).
    static var hasPermission: Bool {
        let now = CACurrentMediaTime()
        if let cache = permissionCache, now - cache.checked < 2 { return cache.granted }
        let granted = CGPreflightScreenCaptureAccess()
        permissionCache = (granted, now)
        return granted
    }

    static func requestPermission() {
        permissionCache = nil
        _ = CGRequestScreenCaptureAccess()
    }

    /// Opens Privacy & Security > Screen Recording in System Settings.
    static func openPrivacySettings() {
        permissionCache = nil
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    override init() {
        super.init()
        layer.contentsGravity = .resize
        layer.actions = ["contents": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        output.mirror = self
        output.onFrame = { [weak self] surface in
            Task { @MainActor in self?.show(surface) }
        }
    }

    func start(displayID: CGDirectDisplayID, pixelSize: CGSize) {
        wanted = true
        guard stream == nil, !starting else { return }
        guard ScreenMirror.hasPermission else {
            setStatus("no Screen Recording permission")
            return
        }
        guard CACurrentMediaTime() >= retryAfter else { return }
        starting = true
        setStatus("starting")
        Task { @MainActor in
            defer { starting = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard wanted else {
                    setStatus("idle")
                    return
                }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    let ids = content.displays.map { String($0.displayID) }.joined(separator: ", ")
                    fail("display \(displayID) not in shareable displays [\(ids)]")
                    return
                }
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let own = content.applications.filter { $0.processID == ownPID }
                let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])

                let config = SCStreamConfiguration()
                config.width = max(1, Int(pixelSize.width))
                config.height = max(1, Int(pixelSize.height))
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.queueDepth = 4
                // The real cursor is drawn above everything anyway.
                config.showsCursor = false

                let stream = SCStream(filter: filter, configuration: config, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                try await stream.startCapture()
                if wanted {
                    self.stream = stream
                    frameCount = 0
                    setStatus("running, waiting for frames")
                } else {
                    try? await stream.stopCapture()
                    setStatus("idle")
                }
            } catch {
                self.stream = nil
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ reason: String) {
        retryAfter = CACurrentMediaTime() + 2
        setStatus("failed: \(reason)")
    }

    private func setStatus(_ text: String) {
        guard text != status else { return }
        status = text
        log.notice("3D capture: \(text, privacy: .public)")
    }

    func stop() {
        wanted = false
        hasFrame = false
        layer.contents = nil
        if !status.hasPrefix("failed") && status != "no Screen Recording permission" { setStatus("idle") }
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    private func show(_ surface: IOSurfaceRef) {
        guard wanted, stream != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = surface
        CATransaction.commit()
        hasFrame = true
        frameCount += 1
        if frameCount == 1 { setStatus("running") }
    }

    /// Restarts on the next request if the system stops the stream (sleep, display change).
    fileprivate func streamStopped(_ error: Error) {
        stream = nil
        hasFrame = false
        fail("stream stopped: \(error.localizedDescription)")
    }

    /// Receives frames on the capture queue and hands complete ones to the main actor.
    private final class FrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
        let queue = DispatchQueue(label: "lidblur.capture", qos: .userInteractive)
        var onFrame: ((IOSurfaceRef) -> Void)?
        weak var mirror: ScreenMirror?

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen,
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: rawStatus) == .complete,
                  let pixelBuffer = sampleBuffer.imageBuffer,
                  let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
                return
            }
            onFrame?(surface)
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            Task { @MainActor [weak self] in self?.mirror?.streamStopped(error) }
        }
    }
}
