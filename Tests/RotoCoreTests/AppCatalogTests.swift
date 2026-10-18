import Foundation
import Testing
@testable import RotoCore

struct AppCatalogTests {
    /// A folder tree of fake bundles; `.app` directories are all a scan looks at.
    private func makeTree(_ paths: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roto-apps-\(UUID().uuidString)", isDirectory: true)
        for path in paths {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    @Test func listsAppsAndOneLevelOfSubfolders() throws {
        let root = try makeTree([
            "Applications/Safari.app",
            "Applications/Utilities/Terminal.app",
            "Applications/Vendor/Deep/Hidden.app",
            "Applications/Xcode.app/Contents/Applications/Instruments.app",
            "Applications/.Secret.app",
            "Applications/NotAnApp",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let apps = AppCatalog.scan(roots: [.init(root.appendingPathComponent("Applications").path, depth: 2)], extras: [])
        #expect(apps.map(\.name) == ["Safari", "Xcode", "Terminal"])
    }

    @Test func earlierRootsComeFirstAndSymlinkedBundlesCountOnce() throws {
        let root = try makeTree(["System/Safari.app", "Applications"])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Applications/Safari.app"),
            withDestinationURL: root.appendingPathComponent("System/Safari.app")
        )

        let apps = AppCatalog.scan(
            roots: [
                .init(root.appendingPathComponent("Applications").path, depth: 1),
                .init(root.appendingPathComponent("System").path, depth: 1),
            ],
            extras: []
        )
        #expect(apps.count == 1)
        #expect(apps.first?.path.hasSuffix("Applications/Safari.app") == true)
        #expect(apps.first?.resolvedPath.hasSuffix("System/Safari.app") == true)
    }

    @Test func extrasAreAddedWhenPresent() throws {
        let root = try makeTree(["CoreServices/Finder.app"])
        defer { try? FileManager.default.removeItem(at: root) }
        let finder = root.appendingPathComponent("CoreServices/Finder.app").path
        let apps = AppCatalog.scan(roots: [], extras: [finder, root.appendingPathComponent("Missing.app").path])
        #expect(apps.map(\.name) == ["Finder"])
    }

    @Test func indexNamesKeepTheFirstAppPerName() {
        let apps = [
            AppRecord(name: "Notes", path: "/Applications/Notes.app"),
            AppRecord(name: "notes", path: "/System/Applications/notes.app"),
            AppRecord(name: "Rechner", path: "/System/Applications/Calculator.app", aliases: ["Calculator"]),
        ]
        #expect(AppCatalog.indexNames(for: apps) == ["Notes": 0, "Rechner": 2, "Calculator": 2])
    }

    @Test func indexFileNamesAreSafe() {
        #expect(AppCatalog.indexFileName("AC/DC Player") == "AC DC Player")
        #expect(AppCatalog.indexFileName(".hidden") == "hidden")
        #expect(AppCatalog.indexFileName("  Spaced  ") == "Spaced")
        #expect(AppCatalog.indexFileName("...") == nil)
        #expect(AppCatalog.indexFileName("") == nil)
    }
}
