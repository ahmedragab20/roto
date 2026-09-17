import Foundation
import Testing
@testable import RotoCore

struct GridNavigationTests {
    @Test func downMovesByColumnCount() {
        #expect(GridNavigation.move(index: 2, count: 20, columns: 8, dx: 0, dy: 1) == 10)
        #expect(GridNavigation.move(index: 2, count: 20, columns: 8, dx: 0, dy: -1) == 2)
    }

    @Test func downOnLastRowGoesToLastItem() {
        #expect(GridNavigation.move(index: 18, count: 20, columns: 8, dx: 0, dy: 1) == 19)
        #expect(GridNavigation.move(index: 19, count: 20, columns: 8, dx: 0, dy: 1) == 19)
    }

    @Test func leftRightStayInRange() {
        #expect(GridNavigation.move(index: 0, count: 10, columns: 4, dx: -1, dy: 0) == 0)
        #expect(GridNavigation.move(index: 0, count: 10, columns: 4, dx: 1, dy: 0) == 1)
        #expect(GridNavigation.move(index: 9, count: 10, columns: 4, dx: 1, dy: 0) == 9)
    }

    @Test func columnCountFromWidth() {
        #expect(GridNavigation.columnCount(width: 416, cell: 52, spacing: 10) == 6)
    }

    @Test func rowsRestartPerSection() {
        #expect(GridNavigation.rows(sectionSizes: [3, 5], columns: 4) == [0..<3, 3..<7, 7..<8])
        #expect(GridNavigation.rows(sectionSizes: [0, 2], columns: 4) == [0..<2])
    }

    @Test func verticalMovesKeepColumnAcrossSections() {
        let rows = GridNavigation.rows(sectionSizes: [3, 5], columns: 4)
        #expect(GridNavigation.move(index: 2, rows: rows, dx: 0, dy: 1) == 5)
        #expect(GridNavigation.move(index: 1, rows: rows, dx: 0, dy: 1) == 4)
        #expect(GridNavigation.move(index: 6, rows: rows, dx: 0, dy: 1) == 7)
        #expect(GridNavigation.move(index: 7, rows: rows, dx: 0, dy: 1) == 7)
        #expect(GridNavigation.move(index: 7, rows: rows, dx: 0, dy: -1) == 3)
        #expect(GridNavigation.move(index: 5, rows: rows, dx: 0, dy: -1) == 2)
        #expect(GridNavigation.move(index: 0, rows: rows, dx: 0, dy: -1) == 0)
    }

    @Test func pageMovesClamp() {
        let rows = GridNavigation.rows(sectionSizes: [20], columns: 4)
        #expect(GridNavigation.move(index: 1, rows: rows, dx: 0, dy: 10) == 17)
        #expect(GridNavigation.move(index: 17, rows: rows, dx: 0, dy: -10) == 1)
    }

    @Test func emptyRowsReturnZero() {
        #expect(GridNavigation.move(index: 3, rows: [], dx: 1, dy: 1) == 0)
    }
}
