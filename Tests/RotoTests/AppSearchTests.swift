import Foundation
import Testing
import RotoCore
@testable import Roto

struct AppSearchTests {
    private struct Fixture {
        let root: URL
        let search: AppSearch

        func install(_ name: String) throws {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Applications/\(name).app", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        func uninstall(_ name: String) throws {
            try FileManager.default.removeItem(at: root.appendingPathComponent("Applications/\(name).app"))
        }
    }

    private func makeFixture(_ names: [String]) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roto-search-\(UUID().uuidString)", isDirectory: true)
        let search = AppSearch(
            directory: root.appendingPathComponent("index"),
            frecencyDirectory: root.appendingPathComponent("frecency"),
            roots: [.init(root.appendingPathComponent("Applications").path, depth: 2)],
            extras: []
        )
        let fixture = Fixture(root: root, search: search)
        for name in names {
            try fixture.install(name)
        }
        search.refreshNow()
        return fixture
    }

    @Test func findsAppsByPartialAndMisspeltNames() throws {
        let fixture = try makeFixture(["Safari", "Slack", "System Settings", "Visual Studio Code", "Terminal"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.search.search("saf", limit: 5).first?.name == "Safari")
        #expect(fixture.search.search("termnal", limit: 5).first?.name == "Terminal")
        #expect(fixture.search.search("vscode", limit: 5).first?.name == "Visual Studio Code")
    }

    @Test func emptyQueryPutsOpenedAppsFirstThenTheRestByName() throws {
        let fixture = try makeFixture(["Zed", "Calendar", "Books", "Maps"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.search.search("", limit: .max).map(\.name) == ["Books", "Calendar", "Maps", "Zed"])

        let maps = try #require(fixture.search.search("maps", limit: 1).first)
        fixture.search.recordLaunch(maps)
        fixture.search.waitUntilIdle()
        #expect(fixture.search.search("", limit: .max).map(\.name) == ["Maps", "Books", "Calendar", "Zed"])
    }

    @Test func refreshPicksUpInstalledAndRemovedApps() throws {
        let fixture = try makeFixture(["Safari", "Xcode"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.install("Zed")
        try fixture.uninstall("Xcode")
        #expect(fixture.search.refreshNow())
        #expect(fixture.search.search("zed", limit: 5).first?.name == "Zed")
        #expect(fixture.search.search("xcode", limit: 5).allSatisfy { $0.name != "Xcode" })
        #expect(fixture.search.refreshNow() == false)
    }

    @Test func respectsTheLimit() throws {
        let fixture = try makeFixture(["Alpha", "Alpine", "Altair", "Alto"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.search.search("al", limit: 2).count == 2)
        #expect(fixture.search.search("", limit: 3).count == 3)
    }
}
