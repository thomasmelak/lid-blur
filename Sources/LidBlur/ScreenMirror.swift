import AppKit
import CoreMedia
import ScreenCaptureKit

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
        guard stream == nil, !starting, ScreenMirror.hasPermission else { return }
        starting = true
        Task { @MainActor in
            defer { starting = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard wanted, let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
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
                } else {
                    try? await stream.stopCapture()
                }
            } catch {
                self.stream = nil
            }
        }
    }

    func stop() {
        wanted = false
        hasFrame = false
        layer.contents = nil
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
    }

    /// Restarts on the next request if the system stops the stream (sleep, display change).
    fileprivate func streamStopped() {
        stream = nil
        hasFrame = false
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
            Task { @MainActor [weak self] in self?.mirror?.streamStopped() }
        }
    }
}
