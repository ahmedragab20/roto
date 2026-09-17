import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Developer-only. Renders every brand asset from BrandMark's geometry:
//   brand/AppIcon.icns, docs/assets/{icon-*.png, favicon-32.png, apple-touch-icon.png,
//   social-preview.png, mark.svg}
// Run with `make brand` from the repo root.

enum Palette {
    static let inkTop = rgb(0x2A2F3A)
    static let inkBottom = rgb(0x0C0E13)
    static let amber = rgb(0xFFB547)
    static let vermilion = rgb(0xFF5A36)
    static let spot = rgb(0xFFF4E2)
    static let paper = rgb(0xF4F1EA)
    static let mist = rgb(0xA9B0BD)
    static let slate = rgb(0x7B8394)

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func hex(_ color: CGColor) -> String {
        let c = color.components ?? [0, 0, 0]
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

@main
struct MakeBrand {
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let assets = root.appendingPathComponent("docs/assets")
    static let brand = root.appendingPathComponent("brand")

    static func main() throws {
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)

        for size in [128, 256, 512, 1024] {
            try writePNG(render(size: size, draw: drawIcon), to: assets.appendingPathComponent("icon-\(size).png"))
        }
        try writePNG(render(size: 180, draw: drawIcon), to: assets.appendingPathComponent("apple-touch-icon.png"))
        try writePNG(render(size: 32, draw: drawIcon), to: assets.appendingPathComponent("favicon-32.png"))
        try writePNG(renderSocialPreview(), to: assets.appendingPathComponent("social-preview.png"))
        try markSVG().write(to: assets.appendingPathComponent("mark.svg"), atomically: true, encoding: .utf8)
        try makeICNS()
        print("Wrote brand assets to \(assets.path) and \(brand.path)")
    }

    // MARK: - Icon

    static func drawIcon(_ ctx: CGContext, _ size: CGFloat) {
        let unit = size / 1024
        let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
        let squircle = BrandMark.squirclePath(in: body)

        // Drop shadow on the Big Sur icon grid.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 28 * unit, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(squircle)
        ctx.setFillColor(Palette.inkBottom)
        ctx.fillPath()
        ctx.restoreGState()

        // Body: ink gradient, a warm glow behind the mark, and a soft top sheen.
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        linear(ctx, [Palette.inkTop, Palette.inkBottom], from: CGPoint(x: body.midX, y: body.maxY), to: CGPoint(x: body.midX, y: body.minY))
        let glow = CGGradient(colorsSpace: nil, colors: [Palette.rgb(0xFF8A3D, alpha: 0.30), Palette.rgb(0xFF8A3D, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: body.midX, y: body.midY), startRadius: 0, endCenter: CGPoint(x: body.midX, y: body.midY), endRadius: body.width * 0.5, options: [])
        linear(ctx, [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)], from: CGPoint(x: body.midX, y: body.maxY), to: CGPoint(x: body.midX, y: body.midY))
        ctx.restoreGState()

        // Hairline edge, like light catching glass.
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        ctx.addPath(squircle)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        ctx.setLineWidth(max(1, 5 * unit))
        ctx.strokePath()
        ctx.restoreGState()

        drawMark(ctx, in: body.insetBy(dx: body.width * 0.2, dy: body.height * 0.2), unit: unit)
    }

    static func drawMark(_ ctx: CGContext, in rect: CGRect, unit: CGFloat) {
        let tiles = BrandMark.tilesPath(in: rect)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * unit), blur: 20 * unit, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(tiles)
        ctx.setFillColor(Palette.vermilion)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tiles)
        ctx.clip()
        linear(ctx, [Palette.amber, Palette.vermilion], from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY))
        linear(ctx, [CGColor(gray: 1, alpha: 0.30), CGColor(gray: 1, alpha: 0)], from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.midY))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 36 * unit, color: Palette.rgb(0xFFB547, alpha: 0.9))
        ctx.addEllipse(in: BrandMark.spot(in: rect))
        ctx.setFillColor(Palette.spot)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - Social preview (GitHub, 1280 × 640)

    static func renderSocialPreview() -> CGImage {
        let width = 1280
        let height = 640
        let ctx = context(width: width, height: height)
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        linear(ctx, [Palette.inkTop, Palette.inkBottom], from: CGPoint(x: 0, y: canvas.maxY), to: CGPoint(x: 0, y: 0))

        let iconSize: CGFloat = 400
        ctx.saveGState()
        ctx.translateBy(x: 90, y: (canvas.height - iconSize) / 2)
        drawIcon(ctx, iconSize)
        ctx.restoreGState()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let left: CGFloat = 540
        draw("roto", font: .systemFont(ofSize: 150, weight: .bold), color: Palette.paper, at: CGPoint(x: left, y: 330))
        draw("Spotlight searches.", font: .systemFont(ofSize: 44, weight: .semibold), color: Palette.paper, at: CGPoint(x: left + 6, y: 262))
        draw("roto does the rest.", font: .systemFont(ofSize: 44, weight: .semibold), color: Palette.amber, at: CGPoint(x: left + 6, y: 208))
        draw("Windows · apps · clipboard · emoji", font: .systemFont(ofSize: 28, weight: .medium), color: Palette.mist, at: CGPoint(x: left + 6, y: 140))
        draw("Native · local-only · open source", font: .systemFont(ofSize: 28, weight: .medium), color: Palette.slate, at: CGPoint(x: left + 6, y: 100))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    static func draw(_ text: String, font: NSFont, color: CGColor, at point: CGPoint) {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: color) ?? .white,
            .kern: font.pointSize > 100 ? -4 : 0,
        ]).draw(at: point)
    }

    // MARK: - SVG mark (website favicon and inline logo)

    static func markSVG() -> String {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let flip = { (r: CGRect) in CGRect(x: r.minX, y: box.height - r.maxY, width: r.width, height: r.height) }
        let tiles = BrandMark.tiles(in: box).map(flip).map { tile in
            let radius = min(tile.width, tile.height) * 0.3
            return String(format: "<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"%.2f\"/>", tile.minX, tile.minY, tile.width, tile.height, radius)
        }
        let spot = flip(BrandMark.spot(in: box))
        return """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="roto">
              <defs>
                <linearGradient id="roto-tiles" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0" stop-color="\(Palette.hex(Palette.amber))"/>
                  <stop offset="1" stop-color="\(Palette.hex(Palette.vermilion))"/>
                </linearGradient>
              </defs>
              <g fill="url(#roto-tiles)">
                \(tiles.joined(separator: "\n    "))
              </g>
              <circle cx="\(String(format: "%.2f", spot.midX))" cy="\(String(format: "%.2f", spot.midY))" r="\(String(format: "%.2f", spot.width / 2))" fill="\(Palette.hex(Palette.amber))"/>
            </svg>

            """
    }

    // MARK: - ICNS

    static func makeICNS() throws {
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            try writePNG(render(size: base, draw: drawIcon), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
            try writePNG(render(size: base * 2, draw: drawIcon), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", brand.appendingPathComponent("AppIcon.icns").path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "make-brand", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
        }
    }

    // MARK: - Drawing helpers

    static func render(size: Int, draw: (CGContext, CGFloat) -> Void) -> CGImage {
        let ctx = context(width: size, height: size)
        draw(ctx, CGFloat(size))
        return ctx.makeImage()!
    }

    static func context(width: Int, height: Int) -> CGContext {
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        return ctx
    }

    static func linear(_ ctx: CGContext, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "make-brand", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "make-brand", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
        }
    }
}
