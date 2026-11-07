// The envdesk logo, drawn in code so it stays sharp at every size.
// A key whose bow is a pair of braces, on a deep blue-to-teal tile.
import AppKit

enum Logo {
    /// The key glyph alone, filling `rect`, in `color`. Used for the app icon and the menu bar.
    static func drawKey(in rect: NSRect, color: NSColor, lineScale: CGFloat = 1) {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2, oy = rect.minY + (rect.height - s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: oy + y * s) }
        color.setStroke(); color.setFill()

        // The bow: a ring.
        let ring = NSBezierPath(ovalIn: NSRect(x: ox + 0.08 * s, y: oy + 0.34 * s, width: 0.34 * s, height: 0.34 * s))
        ring.lineWidth = 0.075 * s * lineScale
        ring.stroke()

        // Inside the ring, an "=" for KEY=VALUE.
        for y in [0.475, 0.545] as [CGFloat] {
            let bar = NSBezierPath(roundedRect: NSRect(x: ox + 0.175 * s, y: oy + y * s - 0.02 * s, width: 0.17 * s, height: 0.04 * s),
                                   xRadius: 0.02 * s, yRadius: 0.02 * s)
            bar.fill()
        }

        // The shaft and two teeth.
        let shaft = NSBezierPath()
        shaft.lineWidth = 0.075 * s * lineScale
        shaft.lineCapStyle = .round
        shaft.move(to: p(0.42, 0.51)); shaft.line(to: p(0.90, 0.51))
        shaft.move(to: p(0.74, 0.51)); shaft.line(to: p(0.74, 0.37))
        shaft.move(to: p(0.86, 0.51)); shaft.line(to: p(0.86, 0.41))
        shaft.stroke()
    }

    /// The full app icon tile at `size` points.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            // macOS icon grid: the tile is about 80% of the canvas, with a soft shadow.
            let inset = r.width * 0.1
            let tile = r.insetBy(dx: inset, dy: inset)
            let radius = tile.width * 0.225
            let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowOffset = NSSize(width: 0, height: -r.width * 0.012)
            shadow.shadowBlurRadius = r.width * 0.03
            shadow.set()
            NSColor.black.setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(colors: [NSColor(srgbRed: 0.12, green: 0.16, blue: 0.42, alpha: 1),
                                NSColor(srgbRed: 0.05, green: 0.55, blue: 0.62, alpha: 1)])!
                .draw(in: tile, angle: -60)
            // A faint highlight across the top.
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
                .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
            NSGraphicsContext.restoreGraphicsState()

            drawKey(in: tile.insetBy(dx: tile.width * 0.09, dy: tile.height * 0.09), color: .white)
            return true
        }
    }

    /// A template image for the menu bar, so macOS tints it for light and dark.
    static func menuBarIcon() -> NSImage {
        // The glyph sits in the middle third of its square, so draw it larger than the image and let
        // the empty top and bottom fall outside: a 22 by 14 point icon, like the system's own.
        let img = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { _ in
            drawKey(in: NSRect(x: -1.5, y: -5.4, width: 25, height: 25), color: .black)
            return true
        }
        img.isTemplate = true
        return img
    }
}
