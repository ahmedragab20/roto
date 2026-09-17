import Foundation

public enum GridNavigation {
    /// Row-major 2D movement that does not wrap off the first or last row.
    /// Left/right walk linearly through the items so the last short row still works.
    public static func move(index: Int, count: Int, columns: Int, dx: Int, dy: Int) -> Int {
        move(index: index, rows: rows(sectionSizes: [count], columns: columns), dx: dx, dy: dy)
    }

    /// Row ranges for sections laid out one after another; each section starts a new row.
    public static func rows(sectionSizes: [Int], columns: Int) -> [Range<Int>] {
        let cols = max(1, columns)
        var rows: [Range<Int>] = []
        var start = 0
        for size in sectionSizes where size > 0 {
            var rowStart = start
            while rowStart < start + size {
                let rowEnd = min(rowStart + cols, start + size)
                rows.append(rowStart..<rowEnd)
                rowStart = rowEnd
            }
            start += size
        }
        return rows
    }

    /// Moves across rows of possibly different lengths, keeping the column when it can.
    /// Down from the last row lands on the last item; up from the first row stays put.
    public static func move(index: Int, rows: [Range<Int>], dx: Int, dy: Int) -> Int {
        guard let count = rows.last?.upperBound, count > 0 else { return 0 }
        var current = min(max(index, 0), count - 1)

        if dx != 0 {
            current = min(max(current + dx, 0), count - 1)
        }

        if dy != 0, let row = rows.firstIndex(where: { $0.contains(current) }) {
            let column = current - rows[row].lowerBound
            if dy > 0 && row == rows.count - 1 {
                current = count - 1
            } else if dy < 0 && row == 0 {
                // Already on the first row.
            } else {
                let target = rows[min(max(row + dy, 0), rows.count - 1)]
                current = min(target.lowerBound + column, target.upperBound - 1)
            }
        }

        return current
    }

    public static func columnCount(width: Double, cell: Double, spacing: Double) -> Int {
        guard cell + spacing > 0 else { return 1 }
        return max(1, Int((width + spacing) / (cell + spacing)))
    }
}
