import Foundation

/// Persists per-app action counts in UserDefaults for usage-based sorting.
enum UsageTracker {
    private static let key = "appUsageCounts"

    /// Increment the action count for a bundle ID.
    static func recordAction(bundleID: String?) {
        guard let bundleID else { return }
        var counts = allCounts()
        counts[bundleID, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: key)
    }

    /// Get the action count for a bundle ID.
    static func count(for bundleID: String?) -> Int {
        guard let bundleID else { return 0 }
        return allCounts()[bundleID] ?? 0
    }

    /// All stored counts.
    static func allCounts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }
}
