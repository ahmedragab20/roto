import CoreGraphics
import Foundation

/// roto's mark: four tiles turning around a center spot. Spotlight is the spot;
/// the tiles are the tools roto runs around it. One geometry feeds the app icon,
/// the menu bar icon, and the website.
public enum BrandMark {
    /// Long and short side of each tile as a share of the mark's width (they sum to 1).
    static let long: CGFloat = 0.64
    static let short: CGFloat = 0.36

    /// Tile rectangles in a y-up square, turning clockwise.
    /// `gap` is the space between neighboring tiles as a share of the mark's width.
    public static func tiles(in rect: CGRect, gap: CGFloat = 0.06) -> [CGRect] {
        let unit: [CGRect] = [
            CGRect(x: 0, y: long, width: long, height: short),     // top, from the left
            CGRect(x: long, y: short, width: short, height: long), // right, from the top
            CGRect(x: short, y: 0, width: long, height: short),    // bottom, from the right
            CGRect(x: 0, y: 0, width: short, height: long),        // left, from the bottom
        ]
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let inset = gap * side / 2
        return unit.map { tile in
            CGRect(
                x: origin.x + tile.minX * side,
                y: origin.y + tile.minY * side,
                width: tile.width * side,
                height: tile.height * side
            )
            .insetBy(dx: inset, dy: inset)
        }
    }

    /// The center spot, with a little more room around it than between the tiles.
    public static func spot(in rect: CGRect, gap: CGFloat = 0.06) -> CGRect {
        let side = min(rect.width, rect.height)
        let opening = long - short + gap
        let diameter = (opening - 2.4 * gap) * side
        return CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
    }

    /// Tiles with rounded corners, as one path.
    public static func tilesPath(in rect: CGRect, gap: CGFloat = 0.06, cornerRatio: CGFloat = 0.3) -> CGPath {
        let path = CGMutablePath()
        for tile in tiles(in: rect, gap: gap) {
            let radius = min(tile.width, tile.height) * cornerRatio
            path.addRoundedRect(in: tile, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }

    /// The whole mark (tiles and spot) as one path, for template images.
    public static func path(in rect: CGRect, gap: CGFloat = 0.06, cornerRatio: CGFloat = 0.3) -> CGPath {
        let path = CGMutablePath()
        path.addPath(tilesPath(in: rect, gap: gap, cornerRatio: cornerRatio))
        path.addEllipse(in: spot(in: rect, gap: gap))
        return path
    }

    /// Apple's app icon silhouette (a superellipse close to the continuous squircle).
    public static func squirclePath(in rect: CGRect, exponent: CGFloat = 5, points: Int = 256) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2
        let b = rect.height / 2
        for index in 0..<points {
            let angle = CGFloat(index) / CGFloat(points) * 2 * .pi
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = pow(abs(cosine), 2 / exponent) * a * (cosine < 0 ? -1 : 1)
            let y = pow(abs(sine), 2 / exponent) * b * (sine < 0 ? -1 : 1)
            let point = CGPoint(x: rect.midX + x, y: rect.midY + y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
