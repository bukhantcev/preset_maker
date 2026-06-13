import Foundation
import SwiftSFTP

struct RemoteServerSettings: Codable, Equatable {
    var remoteMode: Bool = false
    var provider: String = "sftp"
    var url: String = ""
    var port: Int = 22
    var username: String = ""
    var password: String = ""
    var remoteDir: String = RemoteSFTPService.rootName
    var yandexAccessToken: String = ""
    var yandexRefreshToken: String = ""

    init(
        remoteMode: Bool = false,
        provider: String = "sftp",
        url: String = "",
        port: Int = 22,
        username: String = "",
        password: String = "",
        remoteDir: String = RemoteSFTPService.rootName,
        yandexAccessToken: String = "",
        yandexRefreshToken: String = ""
    ) {
        self.remoteMode = remoteMode
        self.provider = provider
        self.url = url
        self.port = port
        self.username = username
        self.password = password
        self.remoteDir = remoteDir
        self.yandexAccessToken = yandexAccessToken
        self.yandexRefreshToken = yandexRefreshToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remoteMode = try container.decodeIfPresent(Bool.self, forKey: .remoteMode) ?? false
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "sftp"
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        remoteDir = try container.decodeIfPresent(String.self, forKey: .remoteDir) ?? RemoteSFTPService.rootName
        yandexAccessToken = try container.decodeIfPresent(String.self, forKey: .yandexAccessToken) ?? ""
        yandexRefreshToken = try container.decodeIfPresent(String.self, forKey: .yandexRefreshToken) ?? ""
    }
}

struct TransferProgress: Sendable {
    let done: Int
    let total: Int
    let name: String
}

enum RemoteSFTPService {
    static let rootName = "MA2_passports"
    static let yandexRoot = "app:/MA2_passports"

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
        if settings.provider == "yandex_disk" {
            try await yandexRefreshRemoteCache(settings: settings, progress: progress)
            return yandexRoot
        }
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
        if settings.provider == "yandex_disk" {
            return try await yandexDownloadProject(projectName, settings: settings, progress: progress)
        }
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

    static func refreshProjectFiles(_ projectName: String, kind: String, settings: RemoteServerSettings) async throws -> URL {
        let target = try remoteCacheRoot().appendingPathComponent(projectName, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        if settings.provider == "yandex_disk" {
            let projectPath = yandexProjectPath(projectName)
            for entry in try await yandexList(projectPath, settings: settings) {
                guard (entry["type"] as? String) == "file",
                      let fileName = entry["name"] as? String,
                      isProjectOutputFile(fileName, kind: kind) else { continue }
                try await yandexGetFile(from: "\(projectPath)/\(fileName)", to: target.appendingPathComponent(fileName), settings: settings)
            }
            return target
        }
        let client = try await openClient(settings: settings)
        defer { Task { try? await client.close() } }
        let remoteProject = join(remoteRoot(settings), projectName)
        for entry in try await list(client, remoteProject) where !entry.isDirectory && isProjectOutputFile(entry.fileName, kind: kind) {
            try await client.download(from: join(remoteProject, entry.fileName), to: target.appendingPathComponent(entry.fileName)) { _, _, _, _ in true }
        }
        return target
    }

    static func uploadProject(_ projectDir: URL, settings: RemoteServerSettings, remoteRoot: String? = nil, progress: (@Sendable (TransferProgress) async -> Void)? = nil) async throws {
        _ = try requireProjectXml(projectDir)
        if settings.provider == "yandex_disk" {
            try await yandexUploadProject(projectDir, settings: settings, progress: progress)
            try mirrorProjectToCache(projectDir)
            return
        }
        let client = try await openClient(settings: settings)
        defer { Task { try? await client.close() } }
        let root = remoteRoot ?? Self.remoteRoot(settings)
        try await client.createDirectory(path: root, makePath: true, mode: .serverDefault)
        let target = join(root, projectDir.lastPathComponent)
        try await uploadDirectoryAtomic(client: client, local: projectDir, remote: target, progress: progress)
        try mirrorProjectToCache(projectDir)
    }

    static func deleteProject(_ projectName: String, settings: RemoteServerSettings, remoteRoot: String? = nil) async throws {
        if settings.provider == "yandex_disk" {
            try await yandexDelete(path: yandexProjectPath(projectName), settings: settings)
            return
        }
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

    static func yandexAuthorizeURL() throws -> URL {
        guard !YandexOAuth.clientID.isEmpty else {
            throw NSError(domain: "Cloud", code: 30, userInfo: [NSLocalizedDescriptionKey: "Не задан YANDEX_CLIENT_ID для iOS"])
        }
        var components = URLComponents(string: "https://oauth.yandex.ru/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: YandexOAuth.clientID),
            URLQueryItem(name: "redirect_uri", value: "https://oauth.yandex.ru/verification_code"),
            URLQueryItem(name: "scope", value: "cloud_api:disk.app_folder"),
            URLQueryItem(name: "force_confirm", value: "yes")
        ]
        guard let url = components.url else {
            throw NSError(domain: "Cloud", code: 31, userInfo: [NSLocalizedDescriptionKey: "Не удалось собрать ссылку Yandex OAuth"])
        }
        return url
    }

    static func exchangeYandexCode(_ code: String) async throws -> (accessToken: String, refreshToken: String) {
        guard !YandexOAuth.clientID.isEmpty, !YandexOAuth.clientSecret.isEmpty else {
            throw NSError(domain: "Cloud", code: 32, userInfo: [NSLocalizedDescriptionKey: "Не заданы YANDEX_CLIENT_ID/YANDEX_CLIENT_SECRET для iOS"])
        }
        var request = URLRequest(url: URL(string: "https://oauth.yandex.ru/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "grant_type": "authorization_code",
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "client_id": YandexOAuth.clientID,
            "client_secret": YandexOAuth.clientSecret
        ].map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        request.httpBody = Data(form.utf8)
        let json = try await yandexJSON(request)
        guard let accessToken = json["access_token"] as? String else {
            let message = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "Yandex не вернул access_token"
            throw NSError(domain: "Cloud", code: 33, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return (accessToken, json["refresh_token"] as? String ?? "")
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

    private static func yandexProjectPath(_ projectName: String) -> String {
        "\(yandexRoot)/\(projectName)"
    }

    private static func yandexRequest(_ path: String, settings: RemoteServerSettings, method: String = "GET") throws -> URLRequest {
        guard !settings.yandexAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Cloud", code: 40, userInfo: [NSLocalizedDescriptionKey: "Яндекс.Диск не подключен"])
        }
        var components = URLComponents(string: "https://cloud-api.yandex.net/v1/disk/resources")!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("OAuth \(settings.yandexAccessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func yandexJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status < 200 || status >= 300 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Cloud", code: status, userInfo: [NSLocalizedDescriptionKey: "Яндекс.Диск: \(status) \(body)"])
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func yandexEnsureDir(_ path: String, settings: RemoteServerSettings) async throws {
        var request = try yandexRequest(path, settings: settings, method: "PUT")
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if [201, 202, 204, 409].contains(status) { return }
        request.httpMethod = "GET"
        _ = try await yandexJSON(request)
    }

    private static func yandexList(_ path: String, settings: RemoteServerSettings) async throws -> [[String: Any]] {
        let request = try yandexRequest(path, settings: settings)
        let json = try await yandexJSON(request)
        guard let embedded = json["_embedded"] as? [String: Any],
              let items = embedded["items"] as? [[String: Any]] else {
            return []
        }
        return items.sorted { (($0["name"] as? String) ?? "") < (($1["name"] as? String) ?? "") }
    }

    private static func yandexHref(path: String, settings: RemoteServerSettings, upload: Bool, overwrite: Bool = true) async throws -> String {
        var components = URLComponents(string: "https://cloud-api.yandex.net/v1/disk/resources/\(upload ? "upload" : "download")")!
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "overwrite", value: overwrite ? "true" : "false")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("OAuth \(settings.yandexAccessToken)", forHTTPHeaderField: "Authorization")
        let json = try await yandexJSON(request)
        guard let href = json["href"] as? String else {
            throw NSError(domain: "Cloud", code: 41, userInfo: [NSLocalizedDescriptionKey: "Яндекс.Диск не вернул ссылку передачи"])
        }
        return href
    }

    private static func yandexPutFile(_ file: URL, to path: String, settings: RemoteServerSettings) async throws {
        let href = try await yandexHref(path: path, settings: settings, upload: true)
        var request = URLRequest(url: URL(string: href)!)
        request.httpMethod = "PUT"
        request.httpBody = try Data(contentsOf: file)
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status >= 200 && status < 300 else {
            throw NSError(domain: "Cloud", code: status, userInfo: [NSLocalizedDescriptionKey: "Загрузка на Яндекс.Диск: \(status)"])
        }
    }

    private static func yandexGetFile(from path: String, to target: URL, settings: RemoteServerSettings) async throws {
        let href = try await yandexHref(path: path, settings: settings, upload: false)
        let (data, response) = try await URLSession.shared.data(from: URL(string: href)!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status >= 200 && status < 300 else {
            throw NSError(domain: "Cloud", code: status, userInfo: [NSLocalizedDescriptionKey: "Скачивание с Яндекс.Диска: \(status)"])
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    private static func yandexUploadProject(_ projectDir: URL, settings: RemoteServerSettings, progress: (@Sendable (TransferProgress) async -> Void)?) async throws {
        try await yandexEnsureDir(yandexRoot, settings: settings)
        let projectPath = yandexProjectPath(projectDir.lastPathComponent)
        try await yandexEnsureDir(projectPath, settings: settings)
        let files = localFiles(in: projectDir)
        for (offset, file) in files.enumerated() {
            let relative = relativePath(root: projectDir, file: file)
            await progress?(TransferProgress(done: offset + 1, total: files.count, name: relative))
            try await yandexPutFile(file, to: "\(projectPath)/\(relative)", settings: settings)
        }
    }

    private static func yandexRefreshRemoteCache(settings: RemoteServerSettings, progress: (@Sendable (TransferProgress) async -> Void)?) async throws {
        try await yandexEnsureDir(yandexRoot, settings: settings)
        let cache = try remoteCacheRoot()
        if FileManager.default.fileExists(atPath: cache.path) {
            try FileManager.default.removeItem(at: cache)
        }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let projects = try await yandexList(yandexRoot, settings: settings).filter { ($0["type"] as? String) == "dir" }
        for project in projects {
            guard let name = project["name"] as? String else { continue }
            let projectPath = yandexProjectPath(name)
            let entries = try await yandexList(projectPath, settings: settings)
            guard entries.contains(where: { (($0["name"] as? String) ?? "").lowercased().hasSuffix(".xml") }) else { continue }
            let local = cache.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        }
    }

    private static func isProjectOutputFile(_ name: String, kind: String) -> Bool {
        let lower = name.lowercased()
        if kind == "partitura" {
            return lower.hasSuffix("_партитура.xlsx") || lower.hasSuffix("_партитура.pdf") || lower.hasSuffix("_new.xml")
        }
        return lower.hasSuffix("_пресеты.xlsx") || lower.hasSuffix("_пресеты.pdf")
    }

    private static func yandexRemoteFiles(path: String, relative: String = "", settings: RemoteServerSettings) async throws -> [(path: String, relative: String)] {
        var result: [(String, String)] = []
        for entry in try await yandexList(path, settings: settings) {
            guard let name = entry["name"] as? String else { continue }
            let childPath = "\(path)/\(name)"
            let childRelative = relative.isEmpty ? name : "\(relative)/\(name)"
            if (entry["type"] as? String) == "dir" {
                result += try await yandexRemoteFiles(path: childPath, relative: childRelative, settings: settings)
            } else {
                result.append((childPath, childRelative))
            }
        }
        return result
    }

    private static func yandexDownloadProject(_ projectName: String, settings: RemoteServerSettings, progress: (@Sendable (TransferProgress) async -> Void)?) async throws -> URL {
        let target = try remoteCacheRoot().appendingPathComponent(projectName, isDirectory: true)
        let temp = target.deletingLastPathComponent().appendingPathComponent(".\(projectName).download", isDirectory: true)
        if FileManager.default.fileExists(atPath: temp.path) { try FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let files = try await yandexRemoteFiles(path: yandexProjectPath(projectName), settings: settings)
        do {
            for (offset, file) in files.enumerated() {
                await progress?(TransferProgress(done: offset + 1, total: files.count, name: file.relative))
                try await yandexGetFile(from: file.path, to: temp.appendingPathComponent(file.relative), settings: settings)
            }
            _ = try requireProjectXml(temp)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: temp, to: target)
            return target
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    private static func yandexDelete(path: String, settings: RemoteServerSettings) async throws {
        var request = try yandexRequest(path, settings: settings, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if [200, 202, 204, 404].contains(status) { return }
        request.httpMethod = "GET"
        _ = try await yandexJSON(request)
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

enum YandexOAuth {
    static let clientID = clean(Bundle.main.object(forInfoDictionaryKey: "YANDEX_CLIENT_ID") as? String
        ?? ProcessInfo.processInfo.environment["YANDEX_CLIENT_ID"]
        ?? "")
    static let clientSecret = clean(Bundle.main.object(forInfoDictionaryKey: "YANDEX_CLIENT_SECRET") as? String
        ?? ProcessInfo.processInfo.environment["YANDEX_CLIENT_SECRET"]
        ?? "")

    private static func clean(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("$(") ? "" : text
    }
}
