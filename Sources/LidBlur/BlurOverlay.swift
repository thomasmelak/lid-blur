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
/// With 3D depth on (and Screen Recording allowed), a live capture of the screen is drawn on
/// top instead, carrying the same blur but scaled down and tilted back from the hinge, so the
/// picture seems to sit behind the glass and rise forward as the lid opens.
///
/// If the backdrop classes are unavailable, it falls back to an even blur, and as a last resort
/// to a standard visual-effect view without any mask.
@MainActor
final class BlurOverlay: NSObject {
    private var window: NSWindow?
    private var backdrop: BackdropBlur?
    private var fallbackView: NSVisualEffectView?
    private var tintView: NSView?
    private var stageView: NSView?
    private var stage: CALayer?
    /// Holds the perspective. A plain layer with a centred anchor, so the vanishing point is the
    /// middle of the screen regardless of how AppKit anchors the view's own layer.
    private var pivot: CALayer?
    /// Darkens the blurred backdrop around the receding picture.
    private var surround: CALayer?
    private var featherMask: CALayer?
    private var mirrorBlur: BlurFilter?
    private let mirror = ScreenMirror()
    private var displayID: CGDirectDisplayID = 0
    private var pixelSize = CGSize.zero

    /// How dark the screen gets when the lid is closed, on top of the blur.
    private let maxTint = 0.9

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// `fold` is 0 with the lid open and 1 with it closed.
    func apply(fold: Double, style: BlurStyle, radiusScale: Double, depth: Bool) {
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

        applyDepth(fold: fold, profile: profile, enabled: depth)
    }

    func hide() {
        window?.orderOut(nil)
        mirror.stop()
        stageView?.isHidden = true
    }

    /// With depth on, the screen is redrawn from a live capture, scaled down and tilted back
    /// around the hinge, so the picture appears to sit behind the glass and rise forward as the
    /// lid opens. The capture carries the same variable blur. Until the first frame arrives (or
    /// without Screen Recording access) the plain backdrop blur underneath shows instead.
    private func applyDepth(fold: Double, profile: BlurProfile, enabled: Bool) {
        guard enabled, ScreenMirror.hasPermission, let stage, let stageView, let mirrorBlur else {
            mirror.stop()
            stageView?.isHidden = true
            return
        }
        mirror.start(displayID: displayID, pixelSize: pixelSize)
        guard mirror.hasFrame else {
            stageView.isHidden = true
            return
        }

        guard let pivot, let surround, let featherMask else { return }
        let look = DepthLook(fold: fold)
        let size = stage.bounds.size
        let bounds = CGRect(origin: .zero, size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surround.frame = bounds
        // How far back the picture sits, 0...1; the surround darkens with it.
        let depth = (1 - look.scale) / (1 - DepthLook.minScale)
        surround.opacity = Float(0.45 * depth)

        pivot.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        pivot.bounds = bounds
        pivot.position = CGPoint(x: size.width / 2, y: size.height / 2)
        // Eye distance a little over twice the screen height: a clear but gentle perspective,
        // centred horizontally so both sides recede equally.
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (2.2 * max(size.height, 1))
        pivot.sublayerTransform = perspective

        let layer = mirror.layer
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.bounds = bounds
        layer.position = CGPoint(x: size.width / 2, y: 0)
        var transform = CATransform3DMakeScale(CGFloat(look.scale), CGFloat(look.scale), 1)
        // Negative angle: the top edge leans away from the viewer, pivoting on the hinge.
        transform = CATransform3DRotate(transform, -CGFloat(look.tilt * .pi / 180), 1, 0, 0)
        layer.transform = transform
        featherMask.frame = bounds
        CATransaction.commit()

        mirrorBlur.update(topRadius: profile.topRadius, hingeRatio: profile.hingeRatio)
        window?.alphaValue = 1
        if stageView.isHidden {
            // Cross-fade from the plain blur to the captured picture as the first frame lands.
            stageView.isHidden = false
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.25
            stage.add(fade, forKey: "appear")
        }
    }

    @objc private func screensChanged() {
        // Rebuilt on the next frame for whatever the built-in display looks like now.
        window?.orderOut(nil)
        mirror.stop()
        mirror.layer.removeFromSuperlayer()
        window = nil
        backdrop = nil
        fallbackView = nil
        tintView = nil
        stageView = nil
        stage = nil
        pivot = nil
        surround = nil
        featherMask = nil
        mirrorBlur = nil
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
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            displayID = CGDirectDisplayID(number.uint32Value)
        }
        pixelSize = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                           height: screen.frame.height * screen.backingScaleFactor)
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

        // The stage holds the captured screen; black shows around it once it moves back.
        // The stage holds the captured screen over the (flat) backdrop blur. It has no background:
        // around the receding picture you see the same blur, darkened, and the picture's edges
        // are feathered into it, so there is no visible frame.
        let stage = CALayer()
        stage.frame = bounds
        stage.masksToBounds = true
        let noActions: [String: CAAction] = [
            "sublayerTransform": NSNull(), "bounds": NSNull(), "position": NSNull(),
            "opacity": NSNull(), "anchorPoint": NSNull(), "transform": NSNull(),
        ]
        stage.actions = noActions

        let surround = CALayer()
        surround.backgroundColor = NSColor.black.cgColor
        surround.frame = bounds
        surround.opacity = 0
        surround.actions = noActions
        stage.addSublayer(surround)

        let pivot = CALayer()
        pivot.actions = noActions
        pivot.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        pivot.frame = bounds
        stage.addSublayer(pivot)

        mirror.layer.removeFromSuperlayer()
        pivot.addSublayer(mirror.layer)
        let feather = BlurOverlay.featherMaskLayer()
        feather.actions = noActions
        feather.frame = bounds
        mirror.layer.mask = feather
        let stageView = NSView(frame: bounds)
        stageView.autoresizingMask = [.width, .height]
        stageView.layer = stage
        stageView.wantsLayer = true
        stageView.isHidden = true
        container.addSubview(stageView)
        mirrorBlur = BlurFilter.attach(to: mirror.layer)

        let tint = NSView(frame: bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.cgColor
        tint.alphaValue = 0
        container.addSubview(tint)

        window.contentView = container
        self.window = window
        self.tintView = tint
        self.stageView = stageView
        self.stage = stage
        self.pivot = pivot
        self.surround = surround
        self.featherMask = feather
        return window
    }

    /// Feather width of the picture's edges, in points.
    private static let featherWidth = 80

    /// An alpha mask that is opaque in the middle and fades to transparent over `featherWidth`
    /// at every edge, with smoothly rounded corners. Its centre pixel is stretched over the
    /// layer, so the fade keeps the same width at any size.
    private static func featherMaskLayer() -> CALayer {
        let f = featherWidth
        let side = 2 * f + 1
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(min(x, side - 1 - x)) / Double(f)
                let dy = Double(min(y, side - 1 - y)) / Double(f)
                let alpha = Easing.smoothstep(dx) * Easing.smoothstep(dy)
                pixels[(y * side + x) * 4 + 3] = UInt8((alpha * 255).rounded())
            }
        }
        let layer = CALayer()
        if let provider = CGDataProvider(data: Data(pixels) as CFData) {
            layer.contents = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
        layer.contentsScale = 1
        let c = CGFloat(f) / CGFloat(side)
        layer.contentsCenter = CGRect(x: c, y: c, width: 1 / CGFloat(side), height: 1 / CGFloat(side))
        return layer
    }
}

/// A layer-hosting view whose backdrop layer blurs the content behind the window. The backdrop
/// is Core Animation's own machinery behind the system blurs, reached through its runtime name.
@MainActor
private final class BackdropBlur {
    let view: NSView
    private let blur: BlurFilter

    init?(frame: NSRect) {
        guard let layerClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return nil }
        let layer = layerClass.init()
        // Sample what the window server draws behind this window, not just our own content.
        layer.setValue(true, forKey: "windowServerAware")
        // Blur a half-resolution copy: visually identical at these radii and much cheaper.
        layer.setValue(0.5, forKey: "scale")
        layer.frame = CGRect(origin: .zero, size: frame.size)
        guard let blur = BlurFilter.attach(to: layer) else { return nil }
        self.blur = blur

        let view = NSView(frame: frame)
        view.autoresizingMask = [.width, .height]
        view.layer = layer
        view.wantsLayer = true
        self.view = view
    }

    func update(topRadius: Double, hingeRatio: Double) {
        blur.update(topRadius: topRadius, hingeRatio: hingeRatio)
    }
}

/// A variable blur on a layer: the mask sets the radius per row, so the radius itself is the
/// gradient. Falls back to an even gaussian blur where the variable filter is unavailable.
@MainActor
private final class BlurFilter {
    private weak var layer: CALayer?
    private let type: String
    private let variable: Bool
    private var lastRadius = -1.0
    private var lastMaskKey = -1

    private static let variableType = "variableBlur"
    private static let gaussianType = "gaussianBlur"
    private static let maskHeight = 256

    private init(layer: CALayer, type: String) {
        self.layer = layer
        self.type = type
        variable = type == BlurFilter.variableType
    }

    static func attach(to layer: CALayer) -> BlurFilter? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let types = (filterClass as AnyObject).perform(NSSelectorFromString("filterTypes"))?
            .takeUnretainedValue() as? [String] ?? []
        let type = types.contains(variableType) ? variableType : gaussianType
        guard types.contains(type),
              let filter = (filterClass as AnyObject).perform(NSSelectorFromString("filterWithType:"), with: type)?
                .takeUnretainedValue() as? NSObject else {
            return nil
        }
        filter.setValue(type, forKey: "name")
        filter.setValue(0, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        if type == variableType {
            filter.setValue(mask(hingeRatio: 1), forKey: "inputMaskImage")
        }
        layer.filters = [filter]
        return BlurFilter(layer: layer, type: type)
    }

    func update(topRadius: Double, hingeRatio: Double) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if abs(topRadius - lastRadius) > 0.01 {
            lastRadius = topRadius
            layer.setValue(topRadius, forKeyPath: "filters.\(type).inputRadius")
        }
        guard variable else { return }
        let key = Int((hingeRatio * 200).rounded())
        if key != lastMaskKey {
            lastMaskKey = key
            layer.setValue(BlurFilter.mask(hingeRatio: hingeRatio), forKeyPath: "filters.\(type).inputMaskImage")
        }
    }

    /// A one-pixel-wide column, stretched over the layer. Alpha scales the radius per row:
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
