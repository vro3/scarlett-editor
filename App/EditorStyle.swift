import SwiftUI

enum EditorStyle {
    // Breakbeat DesignTokens.swift: Midnight palette and semantic mute color.
    static let sidebar = Color(white: 10/255)
    static let mute = Color(red: 0.957, green: 0.247, blue: 0.369)
    static let canvas = Color.black
    static let panel = Color(white: 15/255)
    static let edge = Color(white: 28/255)
    static let muted = Color(white: 153/255)
    static let accent = Color(red: 43/255, green: 60/255, blue: 240/255)
    static func font(_ size: CGFloat) -> Font { .custom("AtkinsonHyperlegibleNext-Regular", size: size, relativeTo: .body) }
}

func sourceName(_ value: UInt64) -> String {
    switch value {
    case 0: return "Off"
    case 0x80...0x83: return "Analog \(value - 0x80 + 1)"
    case 0x300...0x305: return "Mix \(value - 0x300 + 1)"
    case 0x600...0x603: return "Playback \(value - 0x600 + 1)"
    default: return String(format: "Unknown 0x%llx", value)
    }
}
