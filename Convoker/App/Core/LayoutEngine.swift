import Foundation

// MARK: - Layout Preferences

enum GatherLayout: String, CaseIterable {
    case grid           // Default: 1=fill, 2=split, 3=1+2, 4+=NxM
    case cascade        // Offset stacking from top-left
    case sideBySide     // Force equal columns regardless of count
}

enum SplitRatio: String, CaseIterable {
    case equal          // 50/50
    case sixtyForty     // 60/40
    case seventyThirty  // 70/30

    var leftFraction: CGFloat {
        switch self {
        case .equal: return 0.5
        case .sixtyForty: return 0.6
        case .seventyThirty: return 0.7
        }
    }
}

enum LayoutPreferences {
    static var gatherLayout: GatherLayout {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "gatherLayout"),
                  let val = GatherLayout(rawValue: raw) else { return .grid }
            return val
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "gatherLayout") }
    }

    static var splitRatio: SplitRatio {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "splitRatio"),
                  let val = SplitRatio(rawValue: raw) else { return .equal }
            return val
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "splitRatio") }
    }
}

/// Computes window frames for arranging N windows in a screen area.
/// All coordinates are in AX/screen coordinate space (origin top-left, y increases downward).
enum LayoutEngine {
    /// Calculate layout frames for a given window count within a screen rect.
    /// - Parameters:
    ///   - windowCount: Number of windows to arrange
    ///   - screenFrame: The visible screen area in AX/screen coordinates
    ///   - gap: Spacing between windows and edges
    /// - Returns: Array of CGRect frames, one per window
    static func layout(windowCount: Int, in screenFrame: CGRect, gap: CGFloat = 10) -> [CGRect] {
        guard windowCount > 0 else { return [] }

        let area = screenFrame.insetBy(dx: gap, dy: gap)

        // Single window always fills regardless of layout preference
        if windowCount == 1 { return [area] }

        switch LayoutPreferences.gatherLayout {
        case .grid:
            switch windowCount {
            case 2:  return sideBySide(in: area, gap: gap)
            case 3:  return threeLayout(in: area, gap: gap)
            default: return gridLayout(count: windowCount, in: area, gap: gap)
            }
        case .cascade:
            return cascadeLayout(count: windowCount, in: area)
        case .sideBySide:
            return columnLayout(count: windowCount, in: area, gap: gap)
        }
    }

    /// Equal-width columns for multi-app split (2-4 apps).
    /// Distinct from the per-window layouts above — this gives each app its own column.
    /// For 4 apps, uses a 2x2 grid instead.
    static func splitLayout(appCount: Int, in screenFrame: CGRect, gap: CGFloat = 0, rightSide: Bool = false) -> [CGRect] {
        guard appCount > 0 else { return [] }
        let area = screenFrame.insetBy(dx: gap, dy: gap)

        if appCount == 1 {
            // Single app: left or right portion based on split ratio
            let ratio = LayoutPreferences.splitRatio.leftFraction
            let width = rightSide ? area.width * (1 - ratio) : area.width * ratio
            let x = rightSide ? area.maxX - width : area.minX
            return [CGRect(x: x, y: area.minY, width: width, height: area.height)]
        } else if appCount == 2 {
            // 2-app split respects split ratio preference
            let ratio = LayoutPreferences.splitRatio.leftFraction
            let leftWidth = area.width * ratio - gap / 2
            let rightWidth = area.width * (1 - ratio) - gap / 2
            return [
                CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height),
                CGRect(x: area.minX + leftWidth + gap, y: area.minY, width: rightWidth, height: area.height),
            ]
        } else if appCount == 3 {
            // 3-app: equal columns (ratio doesn't apply cleanly)
            let colWidth = (area.width - gap * 2) / 3
            return (0..<3).map { i in
                CGRect(
                    x: area.minX + CGFloat(i) * (colWidth + gap),
                    y: area.minY,
                    width: colWidth,
                    height: area.height
                )
            }
        } else {
            // 4 apps: 2x2 grid
            return gridLayout(count: appCount, in: area, gap: gap)
        }
    }

    // MARK: - Layout Strategies

    /// Two windows: left and right halves
    private static func sideBySide(in area: CGRect, gap: CGFloat) -> [CGRect] {
        let halfWidth = (area.width - gap) / 2
        return [
            CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height),
            CGRect(x: area.minX + halfWidth + gap, y: area.minY, width: halfWidth, height: area.height),
        ]
    }

    /// Three windows: left half + right top/bottom
    private static func threeLayout(in area: CGRect, gap: CGFloat) -> [CGRect] {
        let halfWidth = (area.width - gap) / 2
        let halfHeight = (area.height - gap) / 2
        return [
            // Left half (full height)
            CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height),
            // Right top (AX coords: smaller y = higher on screen)
            CGRect(x: area.minX + halfWidth + gap, y: area.minY,
                   width: halfWidth, height: halfHeight),
            // Right bottom
            CGRect(x: area.minX + halfWidth + gap, y: area.minY + halfHeight + gap,
                   width: halfWidth, height: halfHeight),
        ]
    }

    /// Cascade: offset stacking from top-left, each window 70% of area
    private static func cascadeLayout(count: Int, in area: CGRect) -> [CGRect] {
        let windowWidth = area.width * 0.7
        let windowHeight = area.height * 0.7
        let offset: CGFloat = 30
        return (0..<count).map { i in
            let x = min(area.minX + CGFloat(i) * offset, area.maxX - windowWidth)
            let y = min(area.minY + CGFloat(i) * offset, area.maxY - windowHeight)
            return CGRect(x: x, y: y, width: windowWidth, height: windowHeight)
        }
    }

    /// Equal columns: force side-by-side regardless of window count
    private static func columnLayout(count: Int, in area: CGRect, gap: CGFloat) -> [CGRect] {
        let colWidth = (area.width - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map { i in
            CGRect(
                x: area.minX + CGFloat(i) * (colWidth + gap),
                y: area.minY,
                width: colWidth,
                height: area.height
            )
        }
    }

    /// Dynamic grid for 4+ windows
    private static func gridLayout(count: Int, in area: CGRect, gap: CGFloat) -> [CGRect] {
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))

        let cellWidth = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cellHeight = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

        var frames: [CGRect] = []
        for i in 0..<count {
            let col = i % cols
            let row = i / cols
            // AX coordinate system: origin at top-left, y increases downward
            // Row 0 at top (smallest y), last row at bottom (largest y)
            let x = area.minX + CGFloat(col) * (cellWidth + gap)
            let y = area.minY + CGFloat(row) * (cellHeight + gap)
            frames.append(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        }
        return frames
    }
}
