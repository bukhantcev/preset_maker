import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published var screen: Screen = .start
    @Published var projects: [Project] = []
    @Published var selectedPartituraProject: Project?
    @Published var rows: [PassportRow] = []
    @Published var currentIndex: Int = 0
    @Published var pendingPhoto: UIImage?
    @Published var showTitle: String = "show"
    @Published var errorText: String?
    @Published var partituraFields: [PartituraField] = [
        PartituraField(id: "number", title: "Номер", enabled: true),
        PartituraField(id: "name", title: "Реплика", enabled: true),
        PartituraField(id: "trigger", title: "Trigger", enabled: false),
        PartituraField(id: "trigger_time", title: "Trigger time", enabled: false),
        PartituraField(id: "fade", title: "Fade", enabled: true),
        PartituraField(id: "downfade", title: "Downfade", enabled: false),
        PartituraField(id: "delay", title: "Delay", enabled: false),
        PartituraField(id: "info", title: "Инфо", enabled: true),
        PartituraField(id: "command", title: "Command", enabled: false)
    ]

    var projectDir: URL?
    var photosDir: URL?
    var filesProjectDir: URL?
    var lastProjectListMode: ProjectMode = .presets
    var lastFilesMode: ProjectMode = .presets

    init() {
        _ = try? passportsRoot()
        reloadProjects()
    }

    var currentRow: PassportRow? {
        guard rows.indices.contains(currentIndex) else { return nil }
        return rows[currentIndex]
    }

    func passportsRoot() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("MA2_passports", isDirectory: true)
        let oldRoot = docs.appendingPathComponent("MA2_pasports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path), FileManager.default.fileExists(atPath: oldRoot.path) {
            try? FileManager.default.moveItem(at: oldRoot, to: root)
        }
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    func reloadProjects() {
        do {
            let root = try passportsRoot()
            let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            projects = dirs.compactMap { dir in
                guard dir.hasDirectoryPath, let xml = findXml(in: dir) else { return nil }
                return Project(dir: dir, title: projectTitle(from: dir), xml: xml)
            }.sorted { displayTitle($0.title) < displayTitle($1.title) }
            if selectedPartituraProject == nil {
                selectedPartituraProject = projects.first
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func findXml(in dir: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.pathExtension.lowercased() == "xml" }
    }

    func projectTitle(from dir: URL) -> String {
        let name = dir.deletingPathExtension().lastPathComponent
        return name.hasSuffix("_passport") ? String(name.dropLast("_passport".count)) : name
    }

    func createProject(from importedXml: URL, title: String, mode: ProjectMode) {
        DebugLog.write("AppStore createProject start title=\(title) mode=\(mode.rawValue) xml=\(importedXml.path)")
        screen = .loading("Загружаю XML...")
        Task.detached {
            do {
                DebugLog.write("AppStore createProject task")
                let root = try await MainActor.run { try self.passportsRoot() }
                DebugLog.write("AppStore root \(root.path)")
                let safeTitle = safe(title)
                let dir = root.appendingPathComponent("\(safeTitle)_passport", isDirectory: true)
                let photos = dir.appendingPathComponent("photos", isDirectory: true)
                try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
                DebugLog.write("AppStore created photos \(photos.path)")
                let targetXml = dir.appendingPathComponent("\(safeTitle).xml")
                if FileManager.default.fileExists(atPath: targetXml.path) {
                    try FileManager.default.removeItem(at: targetXml)
                }
                try FileManager.default.copyItem(at: importedXml, to: targetXml)
                DebugLog.write("AppStore copied target xml \(targetXml.path)")
                await MainActor.run {
                    DebugLog.write("AppStore createProject main open mode")
                    self.reloadProjects()
                    if mode == .partitura {
                        self.selectedPartituraProject = Project(dir: dir, title: safeTitle, xml: targetXml)
                        self.screen = .partituraSetup
                    } else {
                        self.openPresetProject(Project(dir: dir, title: safeTitle, xml: targetXml))
                    }
                }
            } catch {
                await MainActor.run {
                    DebugLog.write("AppStore createProject error \(error.localizedDescription)")
                    self.errorText = "XML: \(error.localizedDescription)"
                    self.screen = mode == .partitura ? .partituraSetup : .presetSetup
                }
            }
        }
    }

    func openPresetProject(_ project: Project) {
        DebugLog.write("AppStore openPresetProject start \(project.xml.path)")
        screen = .loading("Открываю проект...")
        Task.detached {
            do {
                DebugLog.write("AppStore parsePresets before")
                let parsed = try MA2Parser.parsePresets(project.xml)
                DebugLog.write("AppStore parsePresets after count=\(parsed.count)")
                let table = project.dir.appendingPathComponent("\(safe(project.title))_пресеты.xlsx")
                let existing = (try? Xlsx.readPassportRows(table)) ?? []
                DebugLog.write("AppStore existing rows count=\(existing.count)")
                let loaded = await Self.mergeRows(parsed: parsed, existing: existing, photosDir: project.dir.appendingPathComponent("photos", isDirectory: true))
                DebugLog.write("AppStore loaded rows count=\(loaded.count)")
                await MainActor.run {
                    DebugLog.write("AppStore openPresetProject main set rows")
                    self.projectDir = project.dir
                    self.photosDir = project.dir.appendingPathComponent("photos", isDirectory: true)
                    self.showTitle = project.title
                    self.rows = loaded
                    self.currentIndex = 0
                    self.pendingPhoto = nil
                    self.screen = .presetWorkspace
                    self.savePassportQuietly()
                    DebugLog.write("AppStore openPresetProject main done")
                }
            } catch {
                await MainActor.run {
                    DebugLog.write("AppStore openPresetProject error \(error.localizedDescription)")
                    self.errorText = "Проект: \(error.localizedDescription)"
                    self.screen = .projectList(.presets)
                }
            }
        }
    }

    static func mergeRows(parsed: [PresetItem], existing: [PassportRow], photosDir: URL) -> [PassportRow] {
        var result = cleanExistingRows(existing, photosDir: photosDir)
        var seen = Set(result.map { "\($0.presetLabel)\n\($0.fixtureId)" })
        for item in parsed {
            let key = "\(item.presetLabel)\n\(item.fixtureId)"
            if !seen.contains(key) {
                result.append(PassportRow(presetLabel: item.presetLabel, fixtureId: item.fixtureId, presetNo: item.presetNo, photoName: nil, description: ""))
                seen.insert(key)
            }
        }
        return attachPhotos(to: result, photosDir: photosDir)
    }

    private static func cleanExistingRows(_ rows: [PassportRow], photosDir: URL) -> [PassportRow] {
        var seenCount: [String: Int] = [:]
        var result: [PassportRow] = []
        for row in rows {
            let key = "\(row.presetLabel)\n\(row.fixtureId)"
            let index = seenCount[key, default: 0]
            seenCount[key] = index + 1
            let photo = existingPhotoName(for: row, at: index, photosDir: photosDir)
            let hasContent = photo != nil || !row.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if index == 0 || hasContent {
                var copy = row
                copy.photoName = photo
                result.append(copy)
            }
        }
        return result
    }

    private static func attachPhotos(to rows: [PassportRow], photosDir: URL) -> [PassportRow] {
        var seenCount: [String: Int] = [:]
        return rows.map { row in
            var copy = row
            let key = "\(row.presetLabel)\n\(row.fixtureId)"
            let index = seenCount[key, default: 0]
            seenCount[key] = index + 1
            if copy.photoName == nil {
                copy.photoName = existingPhotoName(for: row, at: index, photosDir: photosDir)
            }
            return copy
        }
    }

    private static func existingPhotoName(for row: PassportRow, at index: Int, photosDir: URL) -> String? {
        let stem = "\(safe(row.presetLabel))_\(safe(row.fixtureId))"
        let name = index == 0 ? "\(stem).jpg" : "\(stem)_\(index + 1).jpg"
        return FileManager.default.fileExists(atPath: photosDir.appendingPathComponent(name).path) ? name : nil
    }

    func usePendingPhoto() {
        guard let image = pendingPhoto, rows.indices.contains(currentIndex), let photosDir else { return }
        do {
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
            let row = rows[currentIndex]
            let name = uniquePhotoName(base: "\(safe(row.presetLabel))_\(safe(row.fixtureId))", photosDir: photosDir)
            let url = photosDir.appendingPathComponent(name)
            guard let data = image.jpegData(compressionQuality: 0.9) else { return }
            try data.write(to: url)
            rows[currentIndex].photoName = name
            pendingPhoto = nil
            savePassportQuietly()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func uniquePhotoName(base: String, photosDir: URL) -> String {
        var name = "\(base).jpg"
        var counter = 2
        while FileManager.default.fileExists(atPath: photosDir.appendingPathComponent(name).path) {
            name = "\(base)_\(counter).jpg"
            counter += 1
        }
        return name
    }

    func deletePhoto() {
        guard rows.indices.contains(currentIndex), let photosDir, let name = rows[currentIndex].photoName else { return }
        try? FileManager.default.removeItem(at: photosDir.appendingPathComponent(name))
        rows[currentIndex].photoName = nil
        savePassportQuietly()
    }

    func addRowAfterCurrent() {
        guard rows.indices.contains(currentIndex) else { return }
        let base = rows[currentIndex]
        rows.insert(PassportRow(presetLabel: base.presetLabel, fixtureId: base.fixtureId, presetNo: base.presetNo, photoName: nil, description: ""), at: currentIndex + 1)
        currentIndex += 1
        savePassportQuietly()
    }

    func deleteCurrentRow() {
        guard rows.indices.contains(currentIndex), rows.count > 1 else { return }
        rows.remove(at: currentIndex)
        currentIndex = min(currentIndex, rows.count - 1)
        savePassportQuietly()
    }

    func savePassportQuietly() {
        guard let projectDir else { return }
        let rows = rows
        let title = showTitle
        let xlsx = projectDir.appendingPathComponent("\(safe(title))_пресеты.xlsx")
        let pdf = projectDir.appendingPathComponent("\(safe(title))_пресеты.pdf")
        DebugLog.write("AppStore savePassport start rows=\(rows.count)")
        Task.detached {
            do {
                DebugLog.write("AppStore savePassport xlsx before")
                try Xlsx.writePassport(xlsx, title: displayTitle(title), rows: rows, projectDir: projectDir)
                DebugLog.write("AppStore savePassport xlsx after")
                await MainActor.run {
                    do {
                        DebugLog.write("AppStore savePassport pdf before")
                        try PdfWriter.writePassport(pdf, title: displayTitle(title), rows: rows, projectDir: projectDir)
                        DebugLog.write("AppStore savePassport pdf after")
                    } catch {
                        DebugLog.write("AppStore savePassport pdf error \(error.localizedDescription)")
                    }
                }
            } catch {
                DebugLog.write("AppStore savePassport xlsx error \(error.localizedDescription)")
            }
        }
    }

    func createPartitura() {
        guard let project = selectedPartituraProject else {
            errorText = "Выбери проект"
            return
        }
        let fields = partituraFields.filter(\.enabled)
        guard !fields.isEmpty else {
            errorText = "Включи хотя бы одно поле"
            return
        }
        do {
            let rows = try MA2Parser.parsePartitura(project.xml)
            try Xlsx.writePartitura(project.dir.appendingPathComponent("\(safe(project.title))_партитура.xlsx"), title: displayTitle(project.title), rows: rows, fields: fields)
            try PdfWriter.writePartitura(project.dir.appendingPathComponent("\(safe(project.title))_партитура.pdf"), title: displayTitle(project.title), rows: rows, fields: fields)
            filesProjectDir = project.dir
            selectedPartituraProject = project
            lastFilesMode = .partitura
            screen = .projectFiles(.partitura)
        } catch {
            errorText = "Партитура: \(error.localizedDescription)"
        }
    }

    func projectFiles(mode: ProjectMode) -> [URL] {
        let dir = filesProjectDir ?? (mode == .partitura ? selectedPartituraProject?.dir : projectDir)
        guard let dir else { return [] }
        let suffixes = mode == .partitura ? ["_партитура.xlsx", "_партитура.pdf"] : ["_пресеты.xlsx", "_пресеты.pdf"]
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { file in suffixes.contains { file.lastPathComponent.hasSuffix($0) } }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func renameProject(_ project: Project, to title: String) {
        let newTitle = safe(title)
        guard !newTitle.isEmpty else { return }
        let newDir = project.dir.deletingLastPathComponent().appendingPathComponent("\(newTitle)_passport", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: newDir.path) {
                throw NSError(domain: "Project", code: 1, userInfo: [NSLocalizedDescriptionKey: "Такой проект уже есть"])
            }
            try FileManager.default.moveItem(at: project.dir, to: newDir)
            if let xml = findXml(in: newDir) {
                let newXml = newDir.appendingPathComponent("\(newTitle).xml")
                if xml.lastPathComponent != newXml.lastPathComponent {
                    try? FileManager.default.moveItem(at: xml, to: newXml)
                }
            }
            reloadProjects()
        } catch {
            errorText = "Переименование: \(error.localizedDescription)"
        }
    }

    func goBack() {
        switch screen {
        case .camera:
            screen = .presetWorkspace
        case .projectFiles(let mode):
            lastProjectListMode = mode
            screen = .projectList(mode)
        case .projectList(let mode):
            screen = mode == .partitura ? .partituraSetup : .presetSetup
        case .presetSetup, .partituraSetup:
            screen = .start
        case .presetWorkspace:
            savePassportQuietly()
            screen = .start
        default:
            screen = .start
        }
    }
}
