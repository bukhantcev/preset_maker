import Foundation
import SwiftSFTP

struct RemoteServerSettings: Codable, Equatable {
    var remoteMode: Bool = false
    var url: String = ""
    var port: Int = 22
    var username: String = ""
    var password: String = ""
    var remoteDir: String = RemoteSFTPService.rootName
}

struct TransferProgress: Sendable {
    let done: Int
    let total: Int
    let name: String
}

enum RemoteSFTPService {
    static let rootName = "MA2_passports"

    static func remoteCacheRoot() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("remote_cache", isDirectory: true).appendingPathComponent(rootName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static func localRoot() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent(rootName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static func loadSettings() -> RemoteServerSettings {
        guard let data = UserDefaults.standard.data(forKey: "cloud_settings"),
              var settings = try? JSONDecoder().decode(RemoteServerSettings.self, from: data) else {
            return RemoteServerSettings()
        }
        if settings.port == 0 { settings.port = 22 }
        if settings.remoteDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.remoteDir = rootName
        }
        return settings
    }

    static func saveSettings(_ settings: RemoteServerSettings) {
        var normalized = settings
        if normalized.port == 0 { normalized.port = 22 }
        if normalized.remoteDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.remoteDir = rootName
        }
        let data = try? JSONEncoder().encode(normalized)
        UserDefaults.standard.set(data, forKey: "cloud_settings")
    }

    static func refreshRemoteCache(settings: RemoteServerSettings, progress: (@Sendable (TransferProgress) async -> Void)? = nil) async throws -> String {
        let client = try await openClient(settings: settings)
        defer { Task { try? await client.close() } }
        let root = remoteRoot(settings)
        try await client.createDirectory(path: root, makePath: true, mode: .serverDefault)
        let cache = try remoteCacheRoot()
        if FileManager.default.fileExists(atPath: cache.path) {
            try FileManager.default.removeItem(at: cache)
        }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try await downloadProjectIndex(client: client, remoteRoot: root, localRoot: cache, progress: progress)
        return root
    }

    static func refreshProject(_ projectName: String, settings: RemoteServerSettings, remoteRoot: String? = nil, progress: (@Sendable (TransferProgress) async -> Void)? = nil) async throws -> URL {
        let client = try await openClient(settings: settings)
        defer { Task { try? await client.close() } }
        let root = remoteRoot ?? Self.remoteRoot(settings)
        try await client.createDirectory(path: root, makePath: true, mode: .serverDefault)
        let target = try remoteCacheRoot().appendingPathComponent(projectName, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try await downloadDirectory(client: client, remote: join(root, projectName), local: target, progress: progress)
        return target
    }

    static func uploadProject(_ projectDir: URL, settings: RemoteServerSettings, remoteRoot: String? = nil, progress: (@Sendable (TransferProgress) async -> Void)? = nil) async throws {
        _ = try requireProjectXml(projectDir)
        let client = try await openClient(settings: settings)
        defer { Task { try? await client.close() } }
        let root = remoteRoot ?? Self.remoteRoot(settings)
        try await client.createDirectory(path: root, makePath: true, mode: .serverDefault)
        let target = join(root, projectDir.lastPathComponent)
        try await uploadDirectoryAtomic(client: client, local: projectDir, remote: target, progress: progress)
        try mirrorProjectToCache(projectDir)
    }

    static func deleteProject(_ projectName: String, settings: RemoteServerSettings, remoteRoot: String? = nil) async throws {
        let client = try await openClient(settings: settings)
        defer { Task { try? await client.close() } }
        let root = remoteRoot ?? Self.remoteRoot(settings)
        try await client.delete(path: join(root, projectName))
    }

    static func copyProjectToLocal(_ projectDir: URL, replace: Bool) throws {
        let target = try localRoot().appendingPathComponent(projectDir.lastPathComponent, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            if !replace { return }
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: projectDir, to: target)
    }

    static func downloadProjectToLocal(_ projectName: String, settings: RemoteServerSettings, remoteRoot: String? = nil, replace: Bool, progress: (@Sendable (TransferProgress) async -> Void)? = nil) async throws {
        let fullProject = try await refreshProject(projectName, settings: settings, remoteRoot: remoteRoot, progress: progress)
        try copyProjectToLocal(fullProject, replace: replace)
    }

    private static func openClient(settings: RemoteServerSettings) async throws -> SFTPClient {
        let host = cleanHost(settings.url)
        guard !host.isEmpty else {
            throw NSError(domain: "Cloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "Заполни SFTP сервер"])
        }
        guard !settings.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Cloud", code: 2, userInfo: [NSLocalizedDescriptionKey: "Заполни пользователя"])
        }
        let client = try SFTPClient(
            openSocketIn: .init(hostname: host, port: settings.port == 0 ? 22 : settings.port),
            hostKeyAcceptance: .acceptAny,
            authentication: .init(name: settings.username, auth: .password(settings.password))
        )
        try await client.login(timeOut: 15)
        return client
    }

    private static func cleanHost(_ value: String) -> String {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["sftp://", "ssh://"] where host.lowercased().hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        return host
    }

    private static func remoteRoot(_ settings: RemoteServerSettings) -> String {
        let raw = settings.remoteDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? rootName : raw
    }

    private static func join(_ base: String, _ child: String) -> String {
        var left = base.replacingOccurrences(of: "\\", with: "/")
        var right = child.replacingOccurrences(of: "\\", with: "/")
        while left.hasSuffix("/") && left.count > 1 { left.removeLast() }
        while right.hasPrefix("/") { right.removeFirst() }
        return left.isEmpty ? right : "\(left)/\(right)"
    }

    private static func list(_ client: SFTPClient, _ path: String) async throws -> [FileMetadata] {
        try await client.listDirectory(path: path, recursive: false)
            .filter { $0.fileName != "." && $0.fileName != ".." }
            .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    private static func localFiles(in root: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        var files: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory { files.append(file) }
        }
        return files.sorted {
            let leftXml = $0.pathExtension.lowercased() == "xml"
            let rightXml = $1.pathExtension.lowercased() == "xml"
            if leftXml != rightXml { return leftXml }
            return relativePath(root: root, file: $0).localizedCaseInsensitiveCompare(relativePath(root: root, file: $1)) == .orderedAscending
        }
    }

    private static func relativePath(root: URL, file: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return file.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func remoteFiles(client: SFTPClient, remote: String, relative: String = "") async throws -> [(remote: String, relative: String)] {
        var result: [(String, String)] = []
        for entry in try await list(client, remote) {
            let childRemote = join(remote, entry.fileName)
            let childRelative = relative.isEmpty ? entry.fileName : "\(relative)/\(entry.fileName)"
            if entry.isDirectory {
                result += try await remoteFiles(client: client, remote: childRemote, relative: childRelative)
            } else {
                result.append((childRemote, childRelative))
            }
        }
        return result
    }

    private static func uploadDirectoryAtomic(client: SFTPClient, local: URL, remote: String, progress: (@Sendable (TransferProgress) async -> Void)?) async throws {
        _ = try requireProjectXml(local)
        let temp = "\(remote).upload"
        try? await client.delete(path: temp)
        try await client.createDirectory(path: temp, makePath: true, mode: .serverDefault)
        let files = localFiles(in: local)
        do {
            for (offset, file) in files.enumerated() {
                let relative = relativePath(root: local, file: file)
                await progress?(TransferProgress(done: offset + 1, total: files.count, name: relative))
                try await client.upload(from: file, to: join(temp, relative)) { _, _, _, _ in true }
            }
            try? await client.delete(path: remote)
            try await client.rename(from: temp, to: remote)
        } catch {
            try? await client.delete(path: temp)
            throw error
        }
    }

    private static func downloadDirectory(client: SFTPClient, remote: String, local: URL, progress: (@Sendable (TransferProgress) async -> Void)?) async throws {
        let files = try await remoteFiles(client: client, remote: remote)
        let temp = local.deletingLastPathComponent().appendingPathComponent(".\(local.lastPathComponent).download", isDirectory: true)
        if FileManager.default.fileExists(atPath: temp.path) {
            try FileManager.default.removeItem(at: temp)
        }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            for (offset, file) in files.enumerated() {
                await progress?(TransferProgress(done: offset + 1, total: files.count, name: file.relative))
                let target = temp.appendingPathComponent(file.relative, isDirectory: false)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await client.download(from: file.remote, to: target) { _, _, _, _ in true }
            }
            if try requireProjectXml(temp).path.isEmpty { throw NSError() }
            if FileManager.default.fileExists(atPath: local.path) {
                try FileManager.default.removeItem(at: local)
            }
            try FileManager.default.moveItem(at: temp, to: local)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    private static func downloadProjectIndex(client: SFTPClient, remoteRoot: String, localRoot: URL, progress: (@Sendable (TransferProgress) async -> Void)?) async throws {
        try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        for project in try await list(client, remoteRoot) where project.isDirectory {
            let remoteProject = join(remoteRoot, project.fileName)
            let entries = try await list(client, remoteProject)
            guard entries.contains(where: { !$0.isDirectory && $0.fileName.lowercased().hasSuffix(".xml") }) else { continue }
            let localProject = localRoot.appendingPathComponent(project.fileName, isDirectory: true)
            try FileManager.default.createDirectory(at: localProject, withIntermediateDirectories: true)
            let topFiles = entries.filter { !$0.isDirectory }
            for (offset, entry) in topFiles.enumerated() {
                await progress?(TransferProgress(done: offset + 1, total: topFiles.count, name: "\(project.fileName)/\(entry.fileName)"))
                try await client.download(from: join(remoteProject, entry.fileName), to: localProject.appendingPathComponent(entry.fileName)) { _, _, _, _ in true }
            }
        }
    }

    private static func mirrorProjectToCache(_ projectDir: URL) throws {
        let target = try remoteCacheRoot().appendingPathComponent(projectDir.lastPathComponent, isDirectory: true)
        if target.standardizedFileURL == projectDir.standardizedFileURL { return }
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: projectDir, to: target)
    }

    private static func requireProjectXml(_ projectDir: URL) throws -> URL {
        let files = (try? FileManager.default.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)) ?? []
        if let xml = files.first(where: { $0.pathExtension.lowercased() == "xml" }) {
            return xml
        }
        throw NSError(domain: "Cloud", code: 10, userInfo: [NSLocalizedDescriptionKey: "В папке проекта нет XML"])
    }
}
