import Foundation
import SwiftUI

enum Screen {
    case start
    case projectSource
    case presetSetup
    case partituraSetup
    case projectList(ProjectMode)
    case projectMode(Project)
    case projectFiles(ProjectMode)
    case presetWorkspace
    case camera
    case loading(String)
}

enum ProjectMode: String {
    case presets
    case partitura
}

struct PresetItem: Identifiable, Hashable {
    let id = UUID()
    var presetLabel: String
    var fixtureId: String
    var presetNo: String
}

struct PassportRow: Identifiable, Hashable {
    let id = UUID()
    var presetLabel: String
    var fixtureId: String
    var presetNo: String
    var photoName: String?
    var description: String
}

struct PartituraField: Identifiable, Hashable {
    var id: String
    var title: String
    var enabled: Bool
}

struct PartRow: Identifiable {
    let id = UUID()
    var number: String
    var name: String
    var fade: String
    var downfade: String
    var delay: String
    var trigger: String
    var triggerTime: String
    var info: String
    var command: String

    func value(_ field: String) -> String {
        switch field {
        case "number": return number
        case "name": return name
        case "fade": return fade
        case "downfade": return downfade
        case "delay": return delay
        case "trigger": return trigger
        case "trigger_time": return triggerTime
        case "info": return info
        case "command": return command
        default: return ""
        }
    }
}

struct Project: Identifiable, Hashable {
    var id: URL { dir }
    var dir: URL
    var title: String
    var xml: URL
}

struct ReplacePrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var action: () -> Void
}

enum Brand {
    static let black = Color.black
    static let panel = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let panelAlt = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let yellow = Color(red: 1.0, green: 0.72, blue: 0.0)
    static let yellowDark = Color(red: 0.54, green: 0.40, blue: 0.0)
    static let silver = Color(red: 0.83, green: 0.83, blue: 0.83)
    static let silverDark = Color(red: 0.47, green: 0.47, blue: 0.47)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let muted = Color(red: 0.72, green: 0.72, blue: 0.72)
}

func safe(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя_.-")
    let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return result.isEmpty ? "show" : result
}

func displayTitle(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ")
}
