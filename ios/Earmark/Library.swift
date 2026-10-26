import Foundation
import Combine
import CryptoKit

struct Recording: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var source: URL?
    var title: String
    var show = ""
    var folder: String?
    var manualNames = false
    var manualFolder = false
    var position: Double = 0
    var isFeed = false
    var localFilename: String?
    var contentHash: String?
    var aliases: [URL]?
    var listened: Bool?
    var scrubReturnPosition: Double?
}

struct LibraryData: Codable {
    var version = 1
    var entries: [Recording] = []
    var folders: [String] = []
    var lastID: UUID?
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var data = LibraryData()
    @Published var storageError: String?
    @Published var duplicateNotice: String?
    private let file: URL
    private var readable = true

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Earmark/library.json")
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                data = try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: self.file))
                guard data.version == 1 else { throw LibraryError.unsupported }
            }
        } catch {
            readable = false
            data = LibraryData()
            storageError = "Your saved library couldn’t be read. The original file is preserved. Restore a valid backup to continue."
        }
    }

    enum LibraryError: LocalizedError {
        case invalidURL, unsupported, unsupportedAudio
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Paste a full https:// audio, podcast, or Archive.org link."
            case .unsupported: return "This library backup is not supported."
            case .unsupportedAudio: return "Choose an M4A, MP4, MP3, AAC, WAV, AIFF, CAF, or FLAC file."
            }
        }
    }

    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    @discardableResult func remember(_ text: String, notifyDuplicate: Bool = true) throws -> Recording {
        if notifyDuplicate { duplicateNotice = nil }
        guard let url = Self.webURL(text) else { throw LibraryError.invalidURL }
        if let entry = data.entries.first(where: { matches($0, url: url) }) {
            if notifyDuplicate { duplicateNotice = "File already saved." }
            return entry
        }
        let entry = Recording(url: url, title: url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "Audio")
        data.entries.insert(entry, at: 0)
        save()
        return entry
    }

    // Keep meaningful query parameters (including signed media tokens), but ignore fragments.
    private static func linkKey(_ url: URL) -> String {
        let url = AudioResolver.archiveDownload(url) ?? url
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.fragment = nil
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        if parts.path.isEmpty { parts.path = "/" }
        return parts.string ?? url.absoluteString
    }

    private func matches(_ entry: Recording, url: URL) -> Bool {
        guard entry.localFilename == nil else { return false }
        return ([entry.url] + [entry.source].compactMap { $0 } + (entry.aliases ?? [])).contains { Self.linkKey($0) == Self.linkKey(url) }
    }

    private static func fingerprint(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    var audioDirectory: URL { file.deletingLastPathComponent().appendingPathComponent("Audio", isDirectory: true) }

    func playbackURL(for entry: Recording) -> URL? {
        if let name = entry.localFilename { return audioDirectory.appendingPathComponent(name) }
        return entry.source
    }

    @discardableResult func importAudio(_ incoming: URL) throws -> Recording {
        duplicateNotice = nil
        let supported = ["m4a", "mp4", "mp3", "aac", "wav", "aiff", "aif", "caf", "flac"]
        guard incoming.isFileURL, supported.contains(incoming.pathExtension.lowercased()) else {
            throw LibraryError.unsupportedAudio
        }
        let access = incoming.startAccessingSecurityScopedResource()
        defer { if access { incoming.stopAccessingSecurityScopedResource() } }
        let digest = try Self.fingerprint(incoming)
        // Older libraries gain fingerprints lazily without changing their saved IDs or folders.
        for index in data.entries.indices where data.entries[index].localFilename != nil {
            if data.entries[index].contentHash == nil, let local = playbackURL(for: data.entries[index]) {
                data.entries[index].contentHash = try? Self.fingerprint(local)
            }
            if data.entries[index].contentHash == digest,
               let local = playbackURL(for: data.entries[index]), FileManager.default.fileExists(atPath: local.path) {
                save()
                duplicateNotice = "File already saved."
                return data.entries[index]
            }
        }
        let name = UUID().uuidString + "." + incoming.pathExtension.lowercased()
        let destination = audioDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: incoming, to: destination)
        var entry = Recording(url: destination, title: incoming.deletingPathExtension().lastPathComponent)
        entry.localFilename = name
        entry.contentHash = digest
        data.entries.insert(entry, at: 0)
        save()
        return entry
    }

    func entry(_ id: UUID?) -> Recording? { data.entries.first { $0.id == id } }

    @discardableResult func addFolder(_ name: String) -> String? {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !name.isEmpty else { return nil }
        if let existing = data.folders.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        data.folders.append(name)
        save()
        return name
    }

    func move(_ id: UUID, to folder: String?) {
        update(id) { $0.folder = folder; $0.manualFolder = true }
    }

    func setListened(_ listened: Bool, for id: UUID) {
        update(id) { $0.listened = listened }
    }

    func rename(_ id: UUID, title: String, show: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let entry = entry(id) else { return }
        let show = show.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = entry.manualFolder ? entry.folder : addFolder(show)
        update(id) { $0.title = String(title.prefix(300)); $0.show = String(show.prefix(100)); $0.manualNames = true; $0.folder = folder }
    }

    @discardableResult func apply(_ result: ResolvedAudio, to id: UUID) -> Recording? {
        guard var entry = entry(id) else { return nil }
        if result.episodes.isEmpty, let source = result.source,
           let existing = data.entries.first(where: { $0.id != id && !$0.isFeed && matches($0, url: source) }) {
            duplicateNotice = "File already saved."
            // A page URL and its direct audio URL refer to one recording, in one folder.
            let aliases = (existing.aliases ?? []) + [entry.url] + (entry.aliases ?? [])
            data.entries.removeAll { $0.id == id }
            if data.lastID == id { data.lastID = existing.id }
            update(existing.id) { $0.aliases = Array(Set(aliases)) }
            entry = self.entry(existing.id)!
        }
        let show = entry.manualNames ? entry.show : result.show
        let folder = entry.manualFolder ? entry.folder : addFolder(show)
        update(entry.id) {
            $0.source = result.source
            $0.isFeed = !result.episodes.isEmpty
            if !$0.manualNames {
                if !result.title.isEmpty { $0.title = result.title }
                $0.show = result.show
            }
            $0.folder = folder
        }
        return self.entry(entry.id)
    }

    func delete(_ id: UUID) {
        if let name = entry(id)?.localFilename {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(name))
        }
        data.entries.removeAll { $0.id == id }
        if data.lastID == id { data.lastID = nil }
        save()
    }

    func deleteFolder(_ folder: String) {
        data.folders.removeAll { $0 == folder }
        for i in data.entries.indices where data.entries[i].folder == folder {
            data.entries[i].folder = nil
            data.entries[i].manualFolder = true
        }
        save()
    }

    @discardableResult func renameFolder(_ old: String, to proposed: String) -> String? {
        let name = String(proposed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !name.isEmpty, let index = data.folders.firstIndex(of: old),
              !data.folders.contains(where: { $0 != old && $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        data.folders[index] = name
        for i in data.entries.indices where data.entries[i].folder == old {
            data.entries[i].folder = name
            data.entries[i].manualFolder = true
        }
        save()
        return name
    }

    func setScrubReturnPosition(_ position: Double?, for id: UUID) {
        guard position == nil || (position!.isFinite && position! >= 0) else { return }
        update(id) { $0.scrubReturnPosition = position }
    }

    func select(_ id: UUID?) { data.lastID = id; save() }
    func setPosition(_ position: Double, for id: UUID) {
        guard position.isFinite, position >= 0 else { return }
        update(id) { $0.position = position }
    }
    private func update(_ id: UUID, change: (inout Recording) -> Void) {
        guard let i = data.entries.firstIndex(where: { $0.id == id }) else { return }
        change(&data.entries[i]); save()
    }
    private static func validLocalName(_ name: String?) -> Bool {
        guard let name else { return false }
        return !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }
    func exportData() throws -> Data { try JSONEncoder().encode(data) }
    func restore(_ bytes: Data) throws {
        var incoming = try JSONDecoder().decode(LibraryData.self, from: bytes)
        guard incoming.version == 1,
              Set(incoming.entries.map(\.id)).count == incoming.entries.count,
              incoming.entries.allSatisfy({ ($0.localFilename == nil || Self.validLocalName($0.localFilename)) && (Self.webURL($0.url.absoluteString) != nil || Self.validLocalName($0.localFilename)) && ($0.source == nil || Self.webURL($0.source!.absoluteString) != nil) && $0.position.isFinite && $0.position >= 0 && ($0.scrubReturnPosition == nil || ($0.scrubReturnPosition!.isFinite && $0.scrubReturnPosition! >= 0)) }) else { throw LibraryError.unsupported }
        incoming.folders = Array(Set(incoming.folders)).sorted()
        for i in incoming.entries.indices where !incoming.folders.contains(incoming.entries[i].folder ?? "") {
            incoming.entries[i].folder = nil
        }
        // Persist first: a failed restore must not replace the in-memory library.
        try write(try JSONEncoder().encode(incoming))
        data = incoming; readable = true; storageError = nil
    }
    private func write(_ bytes: Data) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func save() {
        guard readable else { return }
        do { try write(exportData()); storageError = nil }
        catch { storageError = "Couldn’t save your library: \(error.localizedDescription)" }
    }
}
