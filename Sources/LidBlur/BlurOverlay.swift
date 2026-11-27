import AppKit
import LidBlurCore
import QuartzCore

/// A click-through, full-screen window on the built-in display that blurs everything behind it.
///
/// The blur is a backdrop layer that samples the window server's content behind the window and
/// runs a variable blur over it: the mask sets the radius per row, so the radius itself is the
/// gradient (strongest at the top, softer at the hinge) and no part of the screen is left sharp.
/// Opening the lid lowers the radius everywhere at once until the screen is sharp. There is no
/// material tint; the screen only darkens towards black near closed.
///
/// If the backdrop classes are unavailable, it falls back to an even blur, and as a last resort
/// to a standard visual-effect view without any mask.
@MainActor
final class BlurOverlay: NSObject {
    private var window: NSWindow?
    private var backdrop: BackdropBlur?
    private var fallbackView: NSVisualEffectView?
    private var tintView: NSView?

    /// How dark the screen gets when the lid is closed, on top of the blur.
    private let maxTint = 0.9

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// `fold` is 0 with the lid open and 1 with it closed.
    func apply(fold: Double, style: BlurStyle, radiusScale: Double) {
        let profile = BlurProfile(fold: fold, gradient: style == .unfold, scale: radiusScale)
        guard profile.isVisible else {
            hide()
            return
        }
        guard let window = ensureWindow(), let tintView else { return }

        if let backdrop {
            window.alphaValue = 1
            backdrop.update(topRadius: profile.topRadius, hingeRatio: profile.hingeRatio)
        } else if fallbackView != nil {
            // The stock material has a fixed radius, so the only control left is its opacity.
            window.alphaValue = CGFloat(Easing.clamp(profile.topRadius / (BlurProfile.maxRadius * 0.5)))
        }
        tintView.alphaValue = CGFloat(profile.dim * maxTint)

        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        window?.orderOut(nil)
    }

    @objc private func screensChanged() {
        // Rebuilt on the next frame for whatever the built-in display looks like now.
        window?.orderOut(nil)
        window = nil
        backdrop = nil
        fallbackView = nil
        tintView = nil
    }

    private func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
    }

    private func ensureWindow() -> NSWindow? {
        // In clamshell mode with an external display there is no built-in screen: nothing to do.
        guard let screen = builtInScreen() else {
            hide()
            return nil
        }
        if let window {
            if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
            return window
        }

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)

        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let container = NSView(frame: bounds)
        container.autoresizingMask = [.width, .height]

        if let blur = BackdropBlur(frame: bounds) {
            container.addSubview(blur.view)
            backdrop = blur
        } else {
            let effect = NSVisualEffectView(frame: bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .fullScreenUI
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.appearance = NSAppearance(named: .darkAqua)
            container.addSubview(effect)
            fallbackView = effect
        }

        let tint = NSView(frame: bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.cgColor
        tint.alphaValue = 0
        container.addSubview(tint)

        window.contentView = container
        self.window = window
        self.tintView = tint
        return window
    }
}

/// A layer-hosting view whose backdrop layer blurs the content behind the window with a
/// per-row radius. Uses Core Animation's backdrop layer and filters, the same machinery behind
/// the system's own blurs, through their Objective-C runtime names.
@MainActor
private final class BackdropBlur {
    let view: NSView
    private let layer: CALayer
    private let variable: Bool
    private var lastRadius = -1.0
    private var lastMaskKey = -1

    private static let variableType = "variableBlur"
    private static let gaussianType = "gaussianBlur"
    private static let maskHeight = 256

    init?(frame: NSRect) {
        guard let layerClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else {
            return nil
        }
        let types = (filterClass as AnyObject).perform(NSSelectorFromString("filterTypes"))?
            .takeUnretainedValue() as? [String] ?? []
        variable = types.contains(BackdropBlur.variableType)
        let type = variable ? BackdropBlur.variableType : BackdropBlur.gaussianType
        guard types.contains(type),
              let filter = (filterClass as AnyObject).perform(NSSelectorFromString("filterWithType:"), with: type)?
                .takeUnretainedValue() as? NSObject else {
            return nil
        }
        filter.setValue(type, forKey: "name")
        filter.setValue(0, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        if variable {
            filter.setValue(BackdropBlur.mask(hingeRatio: 1), forKey: "inputMaskImage")
        }

        let layer = layerClass.init()
        // Sample what the window server draws behind this window, not just our own content.
        layer.setValue(true, forKey: "windowServerAware")
        // Blur a half-resolution copy: visually identical at these radii and much cheaper.
        layer.setValue(0.5, forKey: "scale")
        layer.frame = CGRect(origin: .zero, size: frame.size)
        layer.filters = [filter]
        self.layer = layer

        let view = FlippedView(frame: frame)
        view.autoresizingMask = [.width, .height]
        view.layer = layer
        view.wantsLayer = true
        self.view = view
    }

    func update(topRadius: Double, hingeRatio: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let type = variable ? BackdropBlur.variableType : BackdropBlur.gaussianType
        if abs(topRadius - lastRadius) > 0.01 {
            lastRadius = topRadius
            layer.setValue(topRadius, forKeyPath: "filters.\(type).inputRadius")
        }
        guard variable else { return }
        let key = Int((hingeRatio * 200).rounded())
        if key != lastMaskKey {
            lastMaskKey = key
            layer.setValue(BackdropBlur.mask(hingeRatio: hingeRatio), forKeyPath: "filters.\(type).inputMaskImage")
        }
    }

    /// A one-pixel-wide column, stretched over the screen. Alpha scales the radius per row:
    /// 1 at the top edge down to `hingeRatio` at the hinge, never 0.
    private static func mask(hingeRatio: Double) -> CGImage? {
        let height = maskHeight
        var pixels = [UInt8](repeating: 0, count: height * 4)
        for row in 0..<height {
            // Row 0 is the top of the image.
            let depth = Double(row) / Double(height - 1)
            let alpha = BlurProfile.coverage(atDepth: depth, hingeRatio: hingeRatio)
            pixels[row * 4 + 3] = UInt8((alpha * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: 1, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Top-left origin, so the mask's first row sits at the top edge of the screen.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
