import Foundation
import Testing
@testable import RotoCore

struct FuzzyTests {
    @Test func midWordSubsequenceDoesNotMatch() {
        #expect(Fuzzy.score(query: "grin", in: "grinning face") != nil)
        #expect(Fuzzy.score(query: "grin", in: "migraine") == nil)
    }

    @Test func cryDoesNotMatchGrinning() {
        #expect(Fuzzy.score(query: "cry", in: "grinning face") == nil)
        #expect(Fuzzy.score(query: "cry", in: "grinning face with smiling eyes") == nil)
        #expect(Fuzzy.score(query: "cry", in: "crying face") != nil)
        #expect(Fuzzy.score(query: "cry", in: "loudly crying face") != nil)
        #expect(Fuzzy.score(query: "cry", in: "Smileys & Emotion") == nil)
    }

    @Test func pointMatchesPointing() {
        #expect(Fuzzy.score(query: "point", in: "backhand index pointing left") != nil)
        #expect(Fuzzy.score(query: "point", in: "grinning face") == nil)
    }

    @Test func toleratesSubstitutionOnLongQueries() {
        #expect(Fuzzy.score(query: "hexlo", in: "Hello World") != nil)
    }

    @Test func toleratesTranspositionOnLongQueries() {
        #expect(Fuzzy.score(query: "poitn", in: "pointing") != nil)
    }

    @Test func toleratesDroppedCharacterOnLongQueries() {
        #expect(Fuzzy.score(query: "grnning", in: "grinning face") != nil)
    }

    @Test func rejectsUnrelated() {
        #expect(Fuzzy.score(query: "zzzz", in: "hello") == nil)
    }

    @Test func ranksCollection() {
        let items = ["fire", "grinning face", "red heart"]
        let ranked = Fuzzy.ranked(items, query: "grin") { [$0] }
        #expect(ranked == ["grinning face"])
    }

    @Test func multiWordQueryMatchesAnyOrder() {
        #expect(Fuzzy.score(query: "heart red", in: "red heart") != nil)
        #expect(Fuzzy.score(query: "red heart", in: "red heart")! > Fuzzy.score(query: "heart red", in: "red heart")!)
    }

    @Test func everyTokenMustMatch() {
        #expect(Fuzzy.score(query: "red zzz", in: "red heart") == nil)
    }

    @Test func foldsCaseAndDiacritics() {
        #expect(Fuzzy.score(query: "cafe", in: "Café au lait") != nil)
        #expect(Fuzzy.score(query: "CAFÉ", in: "cafe") != nil)
    }

    @Test func matchesWordInitials() {
        #expect(Fuzzy.score(query: "rh", in: "red heart") != nil)
    }

    @Test func shortTokensDoNotUseTypos() {
        #expect(Fuzzy.score(query: "cat", in: "bat") == nil)
    }

    @Test func singleCharacterNeedsWordStart() {
        #expect(Fuzzy.score(query: "x", in: "box") == nil)
        #expect(Fuzzy.score(query: "x", in: "x-ray") != nil)
    }

    @Test func handlesHugeText() {
        let big = String(repeating: "lorem ipsum dolor ", count: 50_000)
        #expect(Fuzzy.score(query: "lorme ipsum", in: big) != nil)
    }

    @Test func blankQueryScoresZero() {
        #expect(Fuzzy.score(query: "  ", in: "anything") == 0)
    }

    @Test func rankedKeepsInputOrderOnTies() {
        #expect(Fuzzy.ranked(["zeta alpha", "beta alpha"], query: "alpha") { [$0] } == ["zeta alpha", "beta alpha"])
    }
}

struct EmojiPolicyTests {
    @Test func excludesIsraelAndReligiousSigns() {
        #expect(EmojiPolicy.isExcluded(emoji: "🇮🇱", name: "flag: Israel", keywords: []))
        #expect(EmojiPolicy.isExcluded(emoji: "✡️", name: "star of David", keywords: []))
        #expect(EmojiPolicy.isExcluded(emoji: "✝️", name: "latin cross", keywords: ["christian"]))
        #expect(EmojiPolicy.isExcluded(emoji: "⛪", name: "church", keywords: []))
        #expect(EmojiPolicy.isExcluded(emoji: "🎅", name: "Santa Claus", keywords: ["christmas"]))
        #expect(EmojiPolicy.isExcluded(emoji: "🎄", name: "Christmas tree", keywords: []))
        #expect(!EmojiPolicy.isExcluded(emoji: "😀", name: "grinning face", keywords: ["smile"]))
        #expect(!EmojiPolicy.isExcluded(emoji: "🙏", name: "folded hands", keywords: ["please"]))
        #expect(!EmojiPolicy.isExcluded(emoji: "🔔", name: "bell", keywords: ["church", "sound"]))
    }
}
