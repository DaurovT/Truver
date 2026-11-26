/// Playing orders for scale playback (FB-8): indices into a position's `notes`.
public enum PlaybackPattern: Hashable, Sendable {
    case up
    case down
    /// Pairs a third apart: 1-3, 2-4, 3-5 …
    case thirds
    /// Overlapping groups of 3 or 4 notes: 1-2-3, 2-3-4 …
    case sequence(groupSize: Int)

    /// Order of note indices for `noteCount` notes; `descending` plays the pattern from the top.
    public func order(noteCount n: Int, descending: Bool = false) -> [Int] {
        guard n > 0 else { return [] }
        var result: [Int]
        switch self {
        case .up:
            return Array(0..<n)
        case .down:
            return Array((0..<n).reversed())
        case .thirds:
            result = n < 3 ? Array(0..<n) : (0..<(n - 2)).flatMap { [$0, $0 + 2] }
        case .sequence(let size):
            let size = max(2, size)
            result = n < size ? Array(0..<n) : (0...(n - size)).flatMap { start in Array(start..<(start + size)) }
        }
        return descending ? result.map { n - 1 - $0 } : result
    }
}

/// Direction of scale playback (FB-8, user request): up, down, or up and back down.
public enum PlaybackDirection: String, CaseIterable, Sendable, Codable {
    case up, down, upDown
}

extension PlaybackPattern {
    /// One cycle of playback. `loop` makes the cycle seamless when repeated: «вверх-вниз» по кругу does not repeat
    /// the turning notes (1…n…2, then 1 again), «вверх» по кругу jumps back to the bottom.
    public func cycle(noteCount n: Int, direction: PlaybackDirection, loop: Bool) -> [Int] {
        guard n > 0 else { return [] }
        let line = self == .up || self == .down
        let up = line ? Array(0..<n) : order(noteCount: n)
        let down = line ? Array((0..<n).reversed()) : order(noteCount: n, descending: true)
        switch direction {
        case .up: return up
        case .down: return down
        case .upDown:
            guard line, n > 1 else { return up + down }
            // Line: don't play the top note twice; in a loop also skip the bottom one at the end of the cycle.
            let back = Array(down.dropFirst())
            return up + (loop ? Array(back.dropLast()) : back)
        }
    }
}
