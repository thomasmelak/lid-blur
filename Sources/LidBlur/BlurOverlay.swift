import AppKit
import LidBlurCore

/// A click-through, full-screen window on the built-in display that blurs everything behind it.
@MainActor
final class BlurOverlay: NSObject {
    private var window: NSWindow?
    private var effectView: NSVisualEffectView?
    private var tintView: NSView?
    private var lastMaskKey = -1

    /// How dark the screen gets at full strength, on top of the blur.
    private let maxTint = 0.3

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func apply(strength: Double, style: BlurStyle, maxOpacity: Double) {
        let s = Easing.clamp(strength)
        guard s > 0.002 else {
            hide()
            return
        }
        guard let window = ensureWindow(), let effectView, let tintView else { return }

        switch style {
        case .uniform:
            window.alphaValue = CGFloat(s * maxOpacity)
            if effectView.maskImage != nil { effectView.maskImage = nil }
            lastMaskKey = -1
        case .unfold:
            // The reveal is spatial, so keep the window mostly opaque and let the mask do the work.
            window.alphaValue = CGFloat(min(1, s * 2.5) * maxOpacity)
            let key = Int((s * 240).rounded())
            if key != lastMaskKey {
                lastMaskKey = key
                effectView.maskImage = BlurOverlay.unfoldMask(UnfoldMask(strength: s))
            }
        }
        tintView.alphaValue = CGFloat(s * maxTint)

        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        window?.orderOut(nil)
    }

    @objc private func screensChanged() {
        // Rebuilt on the next frame for whatever the built-in display looks like now.
        window?.orderOut(nil)
        window = nil
        effectView = nil
        tintView = nil
        lastMaskKey = -1
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

        let effect = NSVisualEffectView(frame: bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        container.addSubview(effect)

        let tint = NSView(frame: bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.cgColor
        tint.alphaValue = 0
        container.addSubview(tint)

        window.contentView = container
        self.window = window
        self.effectView = effect
        self.tintView = tint
        lastMaskKey = -1
        return window
    }

    /// A small radial gradient image, stretched over the screen, used as the blur mask.
    /// Opaque areas are blurred, transparent areas are sharp.
    private static func unfoldMask(_ mask: UnfoldMask) -> NSImage {
        let size = NSSize(width: 96, height: 96)
        let image = NSImage(size: size, flipped: false) { rect in
            if mask.isFullyBlurred {
                NSColor.black.setFill()
                rect.fill()
                return true
            }
            if mask.isFullyClear { return true }

            var colors: [NSColor] = []
            var locations: [CGFloat] = []
            if mask.centreCoverage > 0 {
                colors.append(NSColor.black.withAlphaComponent(CGFloat(mask.centreCoverage)))
                locations.append(0)
            } else {
                colors.append(.clear)
                locations.append(CGFloat(mask.clearRadius))
            }
            colors.append(.black)
            locations.append(max(CGFloat(mask.blurRadius), locations[0] + 0.001))

            guard let gradient = NSGradient(colors: colors, atLocations: &locations, colorSpace: .deviceRGB) else {
                return false
            }
            let centre = NSPoint(x: rect.midX, y: rect.midY)
            let radius = hypot(rect.width, rect.height) / 2
            NSColor.clear.setFill()
            rect.fill()
            gradient.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: radius,
                          options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
            return true
        }
        image.resizingMode = .stretch
        image.capInsets = NSEdgeInsets()
        return image
    }
}
