import Foundation

/// Carbon virtual key codes. Kept as numbers so RotoCore stays free of Carbon/AppKit.
public enum KeyCodes {
    public static let names: [String: UInt32] = {
        var map: [String: UInt32] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
            "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
            "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "6": 0x16, "5": 0x17, "equal": 0x18, "=": 0x18,
            "9": 0x19, "7": 0x1A, "minus": 0x1B, "-": 0x1B,
            "8": 0x1C, "0": 0x1D, "rightbracket": 0x1E, "]": 0x1E,
            "o": 0x1F, "u": 0x20, "leftbracket": 0x21, "[": 0x21,
            "i": 0x22, "p": 0x23, "enter": 0x24, "return": 0x24,
            "l": 0x25, "j": 0x26, "quote": 0x27, "'": 0x27,
            "k": 0x28, "semicolon": 0x29, ";": 0x29,
            "backslash": 0x2A, "\\": 0x2A, "comma": 0x2B, ",": 0x2B,
            "slash": 0x2C, "/": 0x2C, "n": 0x2D, "m": 0x2E,
            "period": 0x2F, ".": 0x2F, "tab": 0x30, "space": 0x31,
            "grave": 0x32, "`": 0x32, "delete": 0x33, "backspace": 0x33,
            "escape": 0x35, "esc": 0x35,
            "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f3": 0x63, "f8": 0x64,
            "f9": 0x65, "f11": 0x67, "f13": 0x69, "f16": 0x6A, "f14": 0x6B,
            "f10": 0x6D, "f12": 0x6F, "f15": 0x71,
            "help": 0x72, "home": 0x73, "pageup": 0x74,
            "forwarddelete": 0x75, "f4": 0x76, "end": 0x77,
            "f2": 0x78, "pagedown": 0x79, "f1": 0x7A,
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        map["numpad0"] = 0x52
        map["numpad1"] = 0x53
        map["numpad2"] = 0x54
        map["numpad3"] = 0x55
        map["numpad4"] = 0x56
        map["numpad5"] = 0x57
        map["numpad6"] = 0x58
        map["numpad7"] = 0x59
        map["numpad8"] = 0x5B
        map["numpad9"] = 0x5C
        map["numpadclear"] = 0x47
        map["numpaddecimal"] = 0x41
        map["numpadmultiply"] = 0x43
        map["numpadplus"] = 0x45
        map["numpaddivide"] = 0x4B
        map["numpadenter"] = 0x4C
        map["numpadminus"] = 0x4E
        map["numpadequals"] = 0x51
        return map
    }()

    public static func code(for name: String) -> UInt32? {
        names[name.lowercased()]
    }
}
