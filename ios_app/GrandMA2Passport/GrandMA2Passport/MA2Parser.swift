import Foundation

final class MA2Parser: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private var text = ""

    private var cueDataChannel: [String: String] = [:]
    private var cueDataPreset: [String: String] = [:]
    private var presetNoParts: [String] = []
    private var presetMap: [String: [String]] = [:]
    private var presetNames: [String: String] = [:]
    private var presetOrder: [String] = []

    private var partRows: [PartRow] = []
    private var cueNumber = ""
    private var cueSubNumber = ""
    private var cueTrigger = "Go"
    private var cueTriggerTime = ""
    private var cueInfo = ""
    private var cueCommand = ""
    private var inCue = false

    private var currentPart: [String: String]?
    private var currentPartInfo = ""
    private var currentPartCommand = ""

    static func parsePresets(_ url: URL) throws -> [PresetItem] {
        let parser = MA2Parser()
        parser.parse(url)
        return parser.presetOrder.flatMap { key -> [PresetItem] in
            let parts = key.components(separatedBy: "\n")
            let no = parts.first ?? ""
            let name = (parser.presetNames[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !no.isEmpty else { return [] }
            return (parser.presetMap[key] ?? []).map { PresetItem(presetLabel: name, fixtureId: $0, presetNo: no) }
        }
    }

    static func parsePartitura(_ url: URL) throws -> [PartRow] {
        let parser = MA2Parser()
        parser.parse(url)
        return parser.partRows
    }

    private func parse(_ url: URL) {
        guard let xml = XMLParser(contentsOf: url) else { return }
        xml.delegate = self
        xml.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        stack.append(elementName)
        text = ""
        if elementName == "Cue" {
            inCue = true
            cueNumber = ""
            cueSubNumber = ""
            cueTrigger = "Go"
            cueTriggerTime = ""
            cueInfo = ""
            cueCommand = ""
        } else if elementName == "CuePart", inCue {
            currentPart = attributeDict
            currentPartInfo = ""
            currentPartCommand = ""
        } else if elementName == "Channel", stack.contains("CueData") {
            cueDataChannel = attributeDict
        } else if elementName == "Preset", stack.contains("CueData") {
            cueDataPreset = attributeDict
            presetNoParts = []
        } else if elementName == "Number", inCue {
            cueNumber = attributeDict["number"] ?? ""
            cueSubNumber = attributeDict["sub_number"] ?? ""
        } else if elementName == "Trigger", inCue {
            cueTrigger = attributeDict["type"] ?? "Go"
            cueTriggerTime = attributeDict["data_f"] ?? ""
        } else if ["Command", "Cmd", "CueCommand", "CLI", "CommandLine"].contains(elementName) {
            let command = firstNonEmpty(attributeDict["command"], attributeDict["cmd"], attributeDict["command_text"])
            if currentPart != nil { currentPartCommand = command } else if inCue { cueCommand = command }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "No", stack.contains("Preset"), !trimmed.isEmpty {
            presetNoParts.append(trimmed)
        } else if elementName == "CueData" {
            let fixture = firstNonEmpty(cueDataChannel["fixture_id"], cueDataChannel["channel_id"])
            let name = (cueDataPreset["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let no = presetNoParts.joined(separator: ".")
            if !fixture.isEmpty, !name.isEmpty, !no.isEmpty {
                let key = "\(no)\n\(name)"
                if presetMap[key] == nil {
                    presetMap[key] = []
                    presetOrder.append(key)
                }
                if !(presetMap[key] ?? []).contains(fixture) {
                    presetMap[key]?.append(fixture)
                }
                presetNames[key] = name
            }
            cueDataChannel = [:]
            cueDataPreset = [:]
            presetNoParts = []
        } else if elementName == "Info", inCue {
            if currentPart != nil { currentPartInfo = trimmed } else { cueInfo = trimmed }
        } else if ["Command", "Cmd", "CueCommand", "CLI", "CommandLine"].contains(elementName), !trimmed.isEmpty {
            if currentPart != nil { currentPartCommand = trimmed } else if inCue { cueCommand = trimmed }
        } else if elementName == "CuePart", let part = currentPart {
            let index = part["index"] ?? "0"
            if index.isEmpty || index == "0" {
                partRows.append(PartRow(
                    number: formattedCueNumber(),
                    name: part["name"] ?? "cue",
                    fade: part["basic_fade"] ?? "0",
                    downfade: part["basic_downfade"] ?? "",
                    delay: part["basic_delay"] ?? "",
                    trigger: cueTrigger.isEmpty ? "Go" : cueTrigger,
                    triggerTime: cueTriggerTime,
                    info: currentPartInfo.isEmpty ? cueInfo : currentPartInfo,
                    command: currentPartCommand.isEmpty ? cueCommand : currentPartCommand
                ))
            }
            currentPart = nil
        } else if elementName == "Cue" {
            inCue = false
        }
        if !stack.isEmpty { stack.removeLast() }
        text = ""
    }

    private func formattedCueNumber() -> String {
        guard !cueSubNumber.isEmpty, cueSubNumber != "0" else { return cueNumber }
        if let value = Int(cueSubNumber) {
            if value % 100 == 0 { return "\(cueNumber).\(value / 100)" }
            if value % 10 == 0 { return "\(cueNumber).\(value / 10)" }
        }
        return "\(cueNumber).\(cueSubNumber)"
    }
}

func firstNonEmpty(_ values: String?...) -> String {
    for value in values {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return text }
    }
    return ""
}
