import Foundation
import Testing
@testable import Roto

struct FFFIndexTests {
    private static let names = [
        "Safari", "Slack", "System Settings", "Visual Studio Code", "Terminal", "Telegram",
        "Calculator", "Calendar", "Activity Monitor", "App Store", "Xcode", "Ghostty",
    ]

    private func makeIndex(_ names: [String] = names) throws -> (FFFIndex, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roto-fff-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("index", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
        }
        let index = try #require(FFFIndex(directory: directory, frecencyDirectory: root.appendingPathComponent("frecency")))
        #expect(index.rescan(full: false))
        return (index, root)
    }

    @Test func prefixFindsTheApp() throws {
        let (index, root) = try makeIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(index.search("saf", limit: 5).first?.name == "Safari")
        #expect(index.search("term", limit: 5).first?.name == "Terminal")
    }

    @Test func toleratesTypos() throws {
        let (index, root) = try makeIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(index.search("safri", limit: 5).first?.name == "Safari")
        #expect(index.search("calculater", limit: 5).first?.name == "Calculator")
    }

    @Test func matchesWordStarts() throws {
        let (index, root) = try makeIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(index.search("vscode", limit: 5).first?.name == "Visual Studio Code")
        #expect(index.search("activity mon", limit: 5).first?.name == "Activity Monitor")
    }

    @Test func emptyQueryListsEverything() throws {
        let (index, root) = try makeIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(Set(index.search("", limit: 100).map(\.name)) == Set(Self.names))
    }

    @Test func launchesRaiseRank() throws {
        let (index, root) = try makeIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = index.search("cal", limit: 5).map(\.name)
        #expect(Set(before.prefix(2)) == ["Calculator", "Calendar"])
        let second = before[1]
        for _ in 0..<5 {
            #expect(index.track(second))
        }
        #expect(index.search("cal", limit: 5).first?.name == second)
        #expect(index.search("", limit: 100).first?.name == second)
    }

    @Test func rescanPicksUpNewNames() throws {
        let (index, root) = try makeIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("index")
        FileManager.default.createFile(atPath: directory.appendingPathComponent("Zed").path, contents: nil)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("Xcode"))
        #expect(index.rescan(full: true))
        #expect(index.search("zed", limit: 5).first?.name == "Zed")
        #expect(index.search("xcode", limit: 5).allSatisfy { $0.name != "Xcode" })
    }
}
