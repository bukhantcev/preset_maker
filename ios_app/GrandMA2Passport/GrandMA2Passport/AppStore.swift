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
    @Published var remoteSettings: RemoteServerSettings = RemoteSFTPService.loadSettings()
    @Published var remoteConnected: Bool = false
    @Published var remoteStatus: String = ""
    @Published var replacePrompt: ReplacePrompt?
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
    var projectModeProject: Project?
    var projectModeCloud: Bool = false
    var remoteRootPath: String?

    private struct PassportState: Codable {
        var rows: [PassportStateRow]
    }

    private struct PassportStateRow: Codable {
        var presetLabel: String
        var fixtureId: String
        var presetNo: String
        var photoName: String?
        var description: String
    }

    init() {
        _ = try? passportsRoot()
        reloadProjects()
        if remoteSettings.provider == "yandex_disk", !remoteSettings.yandexAccessToken.isEmpty {
            connectRemote(showLoading: false)
        } else if !remoteSettings.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !remoteSettings.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            connectRemote(showLoading: false)
        }
    }

    var currentRow: PassportRow? {
        guard rows.indices.contains(currentIndex) else { return nil }
        return rows[currentIndex]
    }

    func passportsRoot() throws -> URL {
        if remoteSettings.remoteMode {
            return try RemoteSFTPService.remoteCacheRoot()
        }
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
                guard dir.hasDirectoryPath else { return nil }
                if remoteSettings.remoteMode {
                    return Project(dir: dir, title: projectTitle(from: dir), xml: dir.appendingPathComponent("\(projectTitle(from: dir)).xml"))
                }
                guard let xml = findXml(in: dir) else { return nil }
                return Project(dir: dir, title: projectTitle(from: dir), xml: xml)
            }.sorted { displayTitle($0.title) < displayTitle($1.title) }
            if selectedPartituraProject == nil {
                selectedPartituraProject = projects.first
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func setRemoteMode(_ enabled: Bool) {
        remoteSettings.remoteMode = enabled
        RemoteSFTPService.saveSettings(remoteSettings)
        remoteStatus = enabled ? (remoteConnected ? "✓ \(cloudTitle()) подключено" : "✕ нет подключения") : "Локально"
        reloadProjects()
    }

    func openProjectSource() {
        screen = .projectSource
    }

    func openLocalProjects() {
        remoteSettings.remoteMode = false
        RemoteSFTPService.saveSettings(remoteSettings)
        reloadProjects()
        screen = .projectList(.presets)
    }

    func openCloudProjects() {
        remoteSettings.remoteMode = true
        RemoteSFTPService.saveSettings(remoteSettings)
        openProjectList(.presets)
    }

    func openProjectList(_ mode: ProjectMode) {
        lastProjectListMode = mode
        if remoteSettings.remoteMode {
            screen = .loading("Обновляю проекты из облака...")
            let settings = remoteSettings
            Task {
                do {
                    let root = try await RemoteSFTPService.refreshRemoteCache(settings: settings) { progress in
                        await MainActor.run {
                            self.remoteStatus = "Скачиваю \(progress.done)/\(progress.total): \(progress.name)"
                        }
                    }
                    await MainActor.run {
                        self.remoteRootPath = root
                        self.remoteConnected = true
                        self.remoteStatus = "✓ \(self.cloudTitle()) подключено"
                        self.reloadProjects()
                        self.screen = .projectList(mode)
                    }
                } catch {
                    await MainActor.run {
                        self.remoteConnected = false
                        self.remoteStatus = "✕ нет подключения"
                        self.errorText = "Облако: \(error.localizedDescription)"
                        self.screen = .projectSource
                    }
                }
            }
        } else {
            reloadProjects()
            screen = .projectList(mode)
        }
    }

    func saveRemoteSettings(_ settings: RemoteServerSettings) {
        remoteSettings = settings
        remoteSettings.remoteMode = true
        remoteSettings.provider = "sftp"
        RemoteSFTPService.saveSettings(remoteSettings)
        connectRemote()
    }

    func connectYandexDisk(code: String) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else {
            errorText = "Введи код Яндекса"
            return
        }
        screen = .loading("Подключаю Яндекс.Диск...")
        Task {
            do {
                let token = try await RemoteSFTPService.exchangeYandexCode(cleanCode)
                var settings = self.remoteSettings
                settings.remoteMode = true
                settings.provider = "yandex_disk"
                settings.yandexAccessToken = token.accessToken
                settings.yandexRefreshToken = token.refreshToken
                RemoteSFTPService.saveSettings(settings)
                await MainActor.run {
                    self.remoteSettings = settings
                    self.connectRemote()
                }
            } catch {
                await MainActor.run {
                    self.remoteConnected = false
                    self.remoteStatus = "✕ нет подключения"
                    self.errorText = "Яндекс.Диск: \(error.localizedDescription)"
                    self.screen = .start
                }
            }
        }
    }

    func cloudTitle() -> String {
        remoteSettings.provider == "yandex_disk" ? "Яндекс.Диск" : "SFTP"
    }

    func connectRemote(showLoading: Bool = true) {
        let settings = remoteSettings
        if settings.provider == "yandex_disk" {
            guard !settings.yandexAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        } else {
            guard !settings.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !settings.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        }
        if showLoading { screen = .loading("Подключаюсь к облаку...") }
        Task {
            do {
                let root = try await RemoteSFTPService.refreshRemoteCache(settings: settings) { progress in
                    await MainActor.run {
                        self.remoteStatus = "Скачиваю \(progress.done)/\(progress.total): \(progress.name)"
                    }
                }
                await MainActor.run {
                    self.remoteRootPath = root
                    self.remoteConnected = true
                    self.remoteStatus = "✓ \(self.cloudTitle()) подключено"
                    self.reloadProjects()
                    if showLoading { self.screen = .start }
                }
            } catch {
                await MainActor.run {
                    self.remoteConnected = false
                    self.remoteStatus = "✕ нет подключения"
                    self.errorText = "Облако: \(error.localizedDescription)"
                    if showLoading { self.screen = .start }
                }
            }
        }
    }

    func syncProjectToRemote(_ dir: URL?) {
        guard remoteSettings.remoteMode, let dir else { return }
        let settings = remoteSettings
        let root = remoteRootPath
        Task.detached {
            do {
                try await RemoteSFTPService.uploadProject(dir, settings: settings, remoteRoot: root)
            } catch {
                DebugLog.write("Cloud sync error \(error.localizedDescription)")
            }
        }
    }

    func requestSaveProjectToRemote(_ project: Project) {
        if remoteProjectExistsInCache(project) {
            replacePrompt = ReplacePrompt(
                title: "Заменить проект?",
                message: "В облаке уже есть проект «\(displayTitle(project.title))». Заменить его этой версией?",
                confirmTitle: "Заменить"
            ) { [weak self] in
                self?.saveProjectToRemote(project)
            }
        } else {
            saveProjectToRemote(project)
        }
    }

    func saveProjectToRemote(_ project: Project) {
        let settings = remoteSettings
        let root = remoteRootPath
        screen = .loading("Загружаю проект в облако...")
        Task {
            do {
                try await RemoteSFTPService.uploadProject(project.dir, settings: settings, remoteRoot: root) { progress in
                    await MainActor.run {
                        self.remoteStatus = "Загружаю \(progress.done)/\(progress.total): \(progress.name)"
                    }
                }
                await MainActor.run {
                    self.remoteConnected = true
                    self.remoteStatus = "✓ \(self.cloudTitle()) подключено"
                    self.reloadProjects()
                    if let selfProject = self.projectModeProject {
                        self.screen = .projectMode(selfProject)
                    } else {
                        self.screen = .projectList(.presets)
                    }
                }
            } catch {
                await MainActor.run {
                    self.remoteConnected = false
                    self.remoteStatus = "✕ нет подключения"
                    self.errorText = "Облако: \(error.localizedDescription)"
                    if let selfProject = self.projectModeProject {
                        self.screen = .projectMode(selfProject)
                    } else {
                        self.screen = .projectList(.presets)
                    }
                }
            }
        }
    }

    func openProjectMode(_ project: Project) {
        projectModeProject = project
        projectModeCloud = remoteSettings.remoteMode
        screen = .projectMode(project)
    }

    func openProjectFiles(_ project: Project, mode: ProjectMode) {
        if projectModeCloud {
            screen = .loading("Загружаю файлы проекта...")
            let settings = remoteSettings
            let projectName = project.dir.lastPathComponent
            Task {
                do {
                    let dir = try await RemoteSFTPService.refreshProjectFiles(projectName, kind: mode == .partitura ? "partitura" : "presets", settings: settings)
                    await MainActor.run {
                        if mode == .partitura { self.selectedPartituraProject = Project(dir: dir, title: project.title, xml: project.xml) }
                        self.filesProjectDir = dir
                        self.lastFilesMode = mode
                        self.screen = .projectFiles(mode)
                    }
                } catch {
                    await MainActor.run {
                        self.errorText = "Файлы: \(error.localizedDescription)"
                        self.screen = .projectMode(project)
                    }
                }
            }
            return
        }
        if mode == .partitura { selectedPartituraProject = project }
        filesProjectDir = project.dir
        lastFilesMode = mode
        screen = .projectFiles(mode)
    }

    func openProjectBuilder(_ project: Project, mode: ProjectMode) {
        guard !projectModeCloud else { return }
        remoteSettings.remoteMode = false
        RemoteSFTPService.saveSettings(remoteSettings)
        if mode == .partitura {
            selectedPartituraProject = project
            screen = .partituraSetup
        } else {
            openPresetProject(project)
        }
    }

    func requestSaveProjectToLocal(_ project: Project) {
        if localProjectExists(project) {
            replacePrompt = ReplacePrompt(
                title: "Заменить проект?",
                message: "На устройстве уже есть проект «\(displayTitle(project.title))». Заменить его версией из облака?",
                confirmTitle: "Заменить"
            ) { [weak self] in
                self?.saveProjectToLocal(project, replace: true)
            }
        } else {
            saveProjectToLocal(project, replace: false)
        }
    }

    func saveProjectToLocal(_ project: Project, replace: Bool = true) {
        if remoteSettings.remoteMode {
            let settings = remoteSettings
            let root = remoteRootPath
            screen = .loading("Скачиваю проект...")
            Task {
                do {
                    try await RemoteSFTPService.downloadProjectToLocal(project.dir.lastPathComponent, settings: settings, remoteRoot: root, replace: replace) { progress in
                        await MainActor.run {
                            self.remoteStatus = "Скачиваю \(progress.done)/\(progress.total): \(progress.name)"
                        }
                    }
                    await MainActor.run {
                        self.remoteSettings.remoteMode = false
                        RemoteSFTPService.saveSettings(self.remoteSettings)
                        self.reloadProjects()
                        self.screen = .projectList(.presets)
                    }
                } catch {
                    await MainActor.run {
                        self.errorText = "Локально: \(error.localizedDescription)"
                        self.screen = .projectMode(project)
                    }
                }
            }
        } else {
            do {
                try RemoteSFTPService.copyProjectToLocal(project.dir, replace: replace)
            } catch {
                errorText = "Локально: \(error.localizedDescription)"
            }
        }
    }

    private func remoteProjectExistsInCache(_ project: Project) -> Bool {
        guard let cache = try? RemoteSFTPService.remoteCacheRoot() else { return false }
        return FileManager.default.fileExists(atPath: cache.appendingPathComponent(project.dir.lastPathComponent, isDirectory: true).path)
    }

    private func localProjectExists(_ project: Project) -> Bool {
        guard let root = try? RemoteSFTPService.localRoot() else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(project.dir.lastPathComponent, isDirectory: true).path)
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
                    let project = Project(dir: dir, title: safeTitle, xml: targetXml)
                    self.projectModeProject = project
                    self.projectModeCloud = false
                    if mode == .partitura {
                        self.selectedPartituraProject = project
                        self.screen = .partituraSetup
                    } else {
                        self.openPresetProject(project)
                    }
                }
            } catch {
                await MainActor.run {
                    DebugLog.write("AppStore createProject error \(error.localizedDescription)")
                    self.errorText = "XML: \(error.localizedDescription)"
                    self.screen = .projectList(.presets)
                }
            }
        }
    }

    func openPresetProject(_ project: Project) {
        DebugLog.write("AppStore openPresetProject start \(project.xml.path)")
        screen = .loading("Открываю проект...")
        Task.detached {
            do {
                var workProject = project
                DebugLog.write("AppStore parsePresets before")
                let parsed = try MA2Parser.parsePresets(workProject.xml)
                DebugLog.write("AppStore parsePresets after count=\(parsed.count)")
                let table = workProject.dir.appendingPathComponent("\(safe(workProject.title))_пресеты.xlsx")
                let stateRows = Self.readPassportState(projectDir: workProject.dir)
                let tableRows = (try? Xlsx.readPassportRows(table)) ?? []
                let existing = Self.mergeExistingRows(stateRows: stateRows, tableRows: tableRows)
                DebugLog.write("AppStore existing rows count=\(existing.count)")
                let loaded = await Self.mergeRows(parsed: parsed, existing: existing, photosDir: workProject.dir.appendingPathComponent("photos", isDirectory: true))
                DebugLog.write("AppStore loaded rows count=\(loaded.count)")
                await MainActor.run {
                    DebugLog.write("AppStore openPresetProject main set rows")
                    self.projectDir = workProject.dir
                    self.photosDir = workProject.dir.appendingPathComponent("photos", isDirectory: true)
                    self.showTitle = workProject.title
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

    nonisolated private static func mergeExistingRows(stateRows: [PassportRow]?, tableRows: [PassportRow]) -> [PassportRow] {
        guard let stateRows, !stateRows.isEmpty else { return tableRows }
        guard !tableRows.isEmpty else { return stateRows }

        var tableByOccurrence: [String: PassportRow] = [:]
        var tableCounts: [String: Int] = [:]
        for row in tableRows {
            let baseKey = "\(row.presetLabel)\n\(row.fixtureId)"
            let index = tableCounts[baseKey, default: 0]
            tableCounts[baseKey] = index + 1
            tableByOccurrence["\(baseKey)\n\(index)"] = row
        }

        var usedTableRows = Set<String>()
        var stateCounts: [String: Int] = [:]
        var merged: [PassportRow] = stateRows.map { row in
            var copy = row
            let baseKey = "\(row.presetLabel)\n\(row.fixtureId)"
            let index = stateCounts[baseKey, default: 0]
            stateCounts[baseKey] = index + 1
            let occurrence = "\(baseKey)\n\(index)"
            if let tableRow = tableByOccurrence[occurrence] {
                copy.description = tableRow.description
                usedTableRows.insert(occurrence)
            }
            return copy
        }

        tableCounts.removeAll()
        for row in tableRows {
            let baseKey = "\(row.presetLabel)\n\(row.fixtureId)"
            let index = tableCounts[baseKey, default: 0]
            tableCounts[baseKey] = index + 1
            let occurrence = "\(baseKey)\n\(index)"
            if !usedTableRows.contains(occurrence) {
                merged.append(row)
            }
        }
        return merged
    }

    static func mergeRows(parsed: [PresetItem], existing: [PassportRow], photosDir: URL) -> [PassportRow] {
        let byKey = Dictionary(uniqueKeysWithValues: parsed.map { ("\($0.presetLabel)\n\($0.fixtureId)", $0) })
        let normalized = existing.map { row -> PassportRow in
            var copy = row
            if let item = byKey["\(row.presetLabel)\n\(row.fixtureId)"] {
                copy.presetNo = item.presetNo
            }
            return copy
        }
        var result = cleanExistingRows(normalized, photosDir: photosDir)
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

    nonisolated private static func stateURL(projectDir: URL) -> URL {
        projectDir.appendingPathComponent("passport_state.json")
    }

    nonisolated private static func readPassportState(projectDir: URL) -> [PassportRow]? {
        let url = stateURL(projectDir: projectDir)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PassportState.self, from: data) else {
            return nil
        }
        let photosDir = projectDir.appendingPathComponent("photos", isDirectory: true)
        return state.rows.map {
            let photoName = ($0.photoName != nil && FileManager.default.fileExists(atPath: photosDir.appendingPathComponent($0.photoName!).path)) ? $0.photoName : nil
            return PassportRow(
                presetLabel: $0.presetLabel,
                fixtureId: $0.fixtureId,
                presetNo: $0.presetNo,
                photoName: photoName,
                description: $0.description
            )
        }
    }

    nonisolated private static func writePassportState(projectDir: URL, rows: [PassportRow]) throws {
        let state = PassportState(rows: rows.map {
            PassportStateRow(
                presetLabel: $0.presetLabel,
                fixtureId: $0.fixtureId,
                presetNo: $0.presetNo,
                photoName: $0.photoName,
                description: $0.description
            )
        })
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL(projectDir: projectDir), options: .atomic)
    }

    private static func cleanExistingRows(_ rows: [PassportRow], photosDir: URL) -> [PassportRow] {
        var seenCount: [String: Int] = [:]
        var result: [PassportRow] = []
        for row in rows {
            let key = "\(row.presetLabel)\n\(row.fixtureId)"
            let index = seenCount[key, default: 0]
            seenCount[key] = index + 1
            let statePhoto = row.photoName.flatMap { FileManager.default.fileExists(atPath: photosDir.appendingPathComponent($0).path) ? $0 : nil }
            let photo = statePhoto ?? existingPhotoName(for: row, at: index, photosDir: photosDir)
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
        var stems: [String] = []
        let no = row.presetNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !no.isEmpty { stems.append("\(safe(no))_\(safe(row.fixtureId))") }
        stems.append("\(safe(row.presetLabel))_\(safe(row.fixtureId))")
        for stem in Array(Set(stems)) {
            let names = index == 0 ? ["\(stem).jpg"] : ["\(stem)_\(index + 1).jpg", "\(stem).jpg"]
            for name in names where FileManager.default.fileExists(atPath: photosDir.appendingPathComponent(name).path) {
                return name
            }
        }
        return nil
    }

    func usePendingPhoto() {
        guard let image = pendingPhoto, rows.indices.contains(currentIndex), let photosDir else { return }
        do {
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
            let row = rows[currentIndex]
            let presetPart = row.presetNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? row.presetLabel : row.presetNo
            let name = uniquePhotoName(base: "\(safe(presetPart))_\(safe(row.fixtureId))", photosDir: photosDir)
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
                try Self.writePassportState(projectDir: projectDir, rows: rows)
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

    func savePartituraShowXml() {
        guard let project = selectedPartituraProject else {
            errorText = "Выбери проект"
            return
        }
        do {
            let target = project.dir.appendingPathComponent("\(safe(project.title))_new.xml")
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: project.xml, to: target)
            filesProjectDir = project.dir
            selectedPartituraProject = project
            lastFilesMode = .partitura
            screen = .projectFiles(.partitura)
        } catch {
            errorText = "XML: \(error.localizedDescription)"
        }
    }

    func projectFiles(mode: ProjectMode) -> [URL] {
        let dir = filesProjectDir ?? (mode == .partitura ? selectedPartituraProject?.dir : projectDir)
        guard let dir else { return [] }
        let suffixes = mode == .partitura ? ["_партитура.xlsx", "_партитура.pdf", "_new.xml"] : ["_пресеты.xlsx", "_пресеты.pdf"]
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
            if remoteSettings.remoteMode {
                syncProjectToRemote(newDir)
            }
        } catch {
            errorText = "Переименование: \(error.localizedDescription)"
        }
    }

    func goBack() {
        switch screen {
        case .camera:
            screen = .presetWorkspace
        case .projectFiles(let mode):
            if let projectModeProject {
                screen = .projectMode(projectModeProject)
            } else {
                lastProjectListMode = mode
                screen = .projectList(mode)
            }
        case .projectMode:
            screen = .projectList(.presets)
        case .projectList(let mode):
            screen = .projectSource
        case .projectSource:
            screen = .start
        case .presetSetup, .partituraSetup:
            if let projectModeProject {
                screen = .projectMode(projectModeProject)
            } else {
                screen = .start
            }
        case .presetWorkspace:
            savePassportQuietly()
            if let projectModeProject {
                screen = .projectMode(projectModeProject)
            } else {
                screen = .start
            }
        default:
            screen = .start
        }
    }
}
