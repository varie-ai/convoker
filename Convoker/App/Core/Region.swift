import Foundation

/// A normalized rectangle (0-1 space) representing a screen region.
/// Named statics cover the 90% case; custom fractions handle the rest.
/// All values are relative to the screen's visible frame.
struct Region: Codable, Equatable, Hashable {
    let x: CGFloat       // 0.0 - 1.0
    let y: CGFloat       // 0.0 - 1.0
    let width: CGFloat   // 0.0 - 1.0
    let height: CGFloat  // 0.0 - 1.0

    // MARK: - Named Regions

    static let full         = Region(x: 0,    y: 0,   width: 1,    height: 1)
    static let leftHalf     = Region(x: 0,    y: 0,   width: 0.5,  height: 1)
    static let rightHalf    = Region(x: 0.5,  y: 0,   width: 0.5,  height: 1)
    static let leftThird    = Region(x: 0,    y: 0,   width: 1.0/3, height: 1)
    static let centerThird  = Region(x: 1.0/3, y: 0,  width: 1.0/3, height: 1)
    static let rightThird   = Region(x: 2.0/3, y: 0,  width: 1.0/3, height: 1)
    static let topLeft      = Region(x: 0,    y: 0,   width: 0.5,  height: 0.5)
    static let topRight     = Region(x: 0.5,  y: 0,   width: 0.5,  height: 0.5)
    static let bottomLeft   = Region(x: 0,    y: 0.5, width: 0.5,  height: 0.5)
    static let bottomRight  = Region(x: 0.5,  y: 0.5, width: 0.5,  height: 0.5)

    /// All named regions for snap-to matching during save.
    static let namedRegions: [(name: String, region: Region)] = [
        ("Full",          .full),
        ("Left Half",     .leftHalf),
        ("Right Half",    .rightHalf),
        ("Left Third",    .leftThird),
        ("Center Third",  .centerThird),
        ("Right Third",   .rightThird),
        ("Top Left",      .topLeft),
        ("Top Right",     .topRight),
        ("Bottom Left",   .bottomLeft),
        ("Bottom Right",  .bottomRight),
    ]

    /// Human-readable display name (named region or fraction description).
    var displayName: String {
        for (name, region) in Self.namedRegions {
            if self == region { return name }
        }
        let pct = { (v: CGFloat) in "\(Int(v * 100))%" }
        return "\(pct(width)) x \(pct(height))"
    }

    // MARK: - Resolution

    /// Convert this normalized region to an absolute CGRect within a screen frame.
    /// The screen frame should be in AX coordinates (top-left origin).
    func resolve(in screenFrame: CGRect, gap: CGFloat = 0) -> CGRect {
        let resolvedX = screenFrame.minX + x * screenFrame.width
        let resolvedY = screenFrame.minY + y * screenFrame.height
        let resolvedW = width * screenFrame.width
        let resolvedH = height * screenFrame.height

        // Apply gap as inset (half-gap on shared edges, full gap on outer edges)
        let rect = CGRect(x: resolvedX, y: resolvedY, width: resolvedW, height: resolvedH)
        return rect.insetBy(dx: gap / 2, dy: gap / 2)
    }

    // MARK: - Inference

    /// Infer a Region from an absolute window rect within a screen frame.
    /// Normalizes the rect then snaps to the nearest named region if within tolerance.
    static func infer(from windowRect: CGRect, in screenFrame: CGRect, tolerance: CGFloat = 0.1) -> Region {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return .full }

        let normalized = Region(
            x: (windowRect.minX - screenFrame.minX) / screenFrame.width,
            y: (windowRect.minY - screenFrame.minY) / screenFrame.height,
            width: windowRect.width / screenFrame.width,
            height: windowRect.height / screenFrame.height
        )

        // Try snapping to nearest named region
        var bestMatch: Region?
        var bestDistance: CGFloat = .infinity

        for (_, region) in namedRegions {
            let dist = normalized.distance(to: region)
            if dist < bestDistance {
                bestDistance = dist
                bestMatch = region
            }
        }

        if bestDistance <= tolerance, let match = bestMatch {
            return match
        }
        return normalized.clamped
    }

    /// Euclidean distance in normalized space between two regions.
    func distance(to other: Region) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        let dw = width - other.width
        let dh = height - other.height
        return sqrt(dx*dx + dy*dy + dw*dw + dh*dh)
    }

    /// Clamp all values to 0-1 range.
    var clamped: Region {
        Region(
            x: max(0, min(1, x)),
            y: max(0, min(1, y)),
            width: max(0, min(1, width)),
            height: max(0, min(1, height))
        )
    }

    // MARK: - Split Helpers

    /// Generate regions for an N-app split layout.
    static func splitRegions(count: Int, ratio: CGFloat = 0.5) -> [Region] {
        switch count {
        case 0: return []
        case 1: return [.full]
        case 2:
            return [
                Region(x: 0, y: 0, width: ratio, height: 1),
                Region(x: ratio, y: 0, width: 1 - ratio, height: 1),
            ]
        case 3:
            let third = 1.0 / 3.0
            return [
                Region(x: 0, y: 0, width: third, height: 1),
                Region(x: third, y: 0, width: third, height: 1),
                Region(x: 2 * third, y: 0, width: third, height: 1),
            ]
        default:
            // 4+: grid layout
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            let cellW = 1.0 / CGFloat(cols)
            let cellH = 1.0 / CGFloat(rows)
            return (0..<count).map { i in
                let col = i % cols
                let row = i / cols
                return Region(
                    x: CGFloat(col) * cellW,
                    y: CGFloat(row) * cellH,
                    width: cellW,
                    height: cellH
                )
            }
        }
    }
}
