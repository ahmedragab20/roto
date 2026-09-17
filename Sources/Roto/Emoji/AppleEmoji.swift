import CoreText
import Foundation

enum AppleEmoji {
    private static let charset: CharacterSet = {
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, 18, nil)
        return CTFontCopyCharacterSet(font) as CharacterSet
    }()

    static func isAvailable(_ string: String) -> Bool {
        var sawEmoji = false
        for scalar in string.unicodeScalars {
            let value = scalar.value
            if isIgnorable(value) { continue }
            if value >= 0x80 || scalar.properties.isEmoji {
                sawEmoji = true
                if !charset.contains(scalar) {
                    return false
                }
            }
        }
        return sawEmoji
    }

    private static func isIgnorable(_ value: UInt32) -> Bool {
        value == 0x200D
            || value == 0xFE0F
            || value == 0x20E3
            || (0x1F3FB...0x1F3FF).contains(value)
            || (0xE0020...0xE007F).contains(value)
    }
}
