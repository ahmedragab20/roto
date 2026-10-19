import Testing
@testable import RotoCore

struct LauncherSearchTests {
    private func app(_ name: String, aliases: [String] = []) -> AppRecord {
        AppRecord(name: name, path: "/Applications/\(name).app", aliases: aliases)
    }

    @Test func emptyQueryKeepsLearnedAppOrderAndListsCommandsLast() {
        let apps = [app("Zed"), app("Books")]
        #expect(LauncherSearch.merge(apps: apps, commands: [.sleepDisplay], query: " \n", limit: 40)
            == [.app(apps[0]), .app(apps[1]), .command(.sleepDisplay)])
    }

    @Test(arguments: ["sleep", "screen off", "off screen", "display sleep", "slep display", "MONITOR OFF"])
    func findsDisplaySleepByNameKeywordsAndTypos(query: String) {
        #expect(LauncherSearch.merge(apps: [], commands: [.sleepDisplay], query: query, limit: 40)
            == [.command(.sleepDisplay)])
    }

    @Test func exactAppNamesAndAliasesBeatCommandKeywords() {
        let command = LauncherCommand(name: "Sleep Display", command: "true", keywords: ["Safari"])
        let apps = [app("Safari"), app("Browser", aliases: ["Safari"])]
        #expect(LauncherSearch.merge(apps: apps, commands: [command], query: "safari", limit: 40)
            == [.app(apps[0]), .app(apps[1]), .command(command)])
    }

    @Test func strongCommandsPrecedeWeakAppMatchesWithoutReorderingApps() {
        let apps = [app("Sleepy"), app("Sleeper")]
        #expect(LauncherSearch.merge(apps: apps, commands: [.sleepDisplay], query: "sleep", limit: 40)
            == [.command(.sleepDisplay), .app(apps[0]), .app(apps[1])])
    }

    @Test func laterStrongAppStillWinsWhenFrecencyPromotesAWeakerApp() {
        let apps = [app("Sleeper"), app("Sleep")]
        #expect(LauncherSearch.merge(apps: apps, commands: [.sleepDisplay], query: "sleep", limit: 40)
            == [.app(apps[0]), .app(apps[1]), .command(.sleepDisplay)])
    }

    @Test func commandsRankByRelevanceAndConfigOrderBreaksTies() {
        let commands = [
            LauncherCommand(name: "Other", command: "true", keywords: ["sleep"]),
            LauncherCommand.sleepDisplay,
            LauncherCommand(name: "Sleep", command: "true"),
            LauncherCommand(name: "Another", command: "true", keywords: ["sleep"]),
        ]
        #expect(LauncherSearch.merge(apps: [], commands: commands, query: "sleep", limit: 40)
            == [commands[2], commands[1], commands[0], commands[3]].map(LauncherResult.command))
    }

    @Test func missesDoNotMatchShellTextOrSingleLetterKeywords() {
        let commands = [LauncherCommand(name: "Example", command: "private executable", keywords: ["other"])]
        for query in ["private", "executable", "o", "example missing", "$(touch /tmp/never)"] {
            #expect(LauncherSearch.merge(apps: [], commands: commands, query: query, limit: 40).isEmpty)
        }
    }

    @Test func limitsApplyToTheCombinedList() {
        let apps = [app("Sleepy"), app("Sleeper")]
        #expect(LauncherSearch.merge(apps: apps, commands: [.sleepDisplay], query: "sleep", limit: 1)
            == [.command(.sleepDisplay)])
        #expect(LauncherSearch.merge(apps: apps, commands: [.sleepDisplay], query: "", limit: 1)
            == [.app(apps[0])])
        for limit in [0, -1] {
            #expect(LauncherSearch.merge(apps: apps, commands: [.sleepDisplay], query: "sleep", limit: limit).isEmpty)
        }
    }

    @Test func appAndCommandWithTheSameNameHaveDifferentIDs() {
        #expect(LauncherResult.app(app("Sleep Display")).id != LauncherResult.command(.sleepDisplay).id)
    }
}
