import SwiftUI
import UniformTypeIdentifiers

@MainActor final class AutomaticBackupStore: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "automaticBackupEnabled") } }
    @Published private(set) var folderName: String
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var error: String?
    @Published private(set) var running = false
    private let library: LibraryStore
    private let defaults: UserDefaults
    private var lastAttempt: Date?
    private var bookmark: Data? { defaults.data(forKey: "automaticBackupFolder") }
    var configured: Bool { bookmark != nil }

    init(library: LibraryStore, defaults: UserDefaults? = nil) {
        self.library = library
        let isolated = ProcessInfo.processInfo.environment["EARMARK_UI_TEST_LIBRARY"] ?? (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? "unit-host" : nil)
        let settings = defaults ?? isolated.flatMap { UserDefaults(suiteName: "earmark.backup.tests." + $0) } ?? .standard
        self.defaults = settings
        enabled = settings.bool(forKey: "automaticBackupEnabled")
        folderName = settings.string(forKey: "automaticBackupFolderName") ?? ""
        lastSuccess = settings.object(forKey: "automaticBackupLastSuccess") as? Date
    }
    func choose(_ folder: URL) throws {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let data = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: "automaticBackupFolder")
        folderName = folder.lastPathComponent; defaults.set(folderName, forKey: "automaticBackupFolderName")
        lastSuccess = nil; defaults.removeObject(forKey: "automaticBackupLastSuccess")
        lastAttempt = nil; enabled = true; error = nil
    }
    func runIfDue(now: Date = Date(), force: Bool = false) async {
        guard configured, !running, force || enabled else { return }
        guard force || lastSuccess.map({ now.timeIntervalSince($0) >= 86400 }) ?? true else { return }
        guard force || lastAttempt.map({ now.timeIntervalSince($0) >= 3600 }) ?? true else { return }
        running = true; lastAttempt = now
        defer { running = false }
        do {
            var stale = false
            guard let bookmark else { return }
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            if stale { defaults.set(try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "automaticBackupFolder") }
            let snapshot = library.data, audio = library.audioDirectory
            let file = folder.appendingPathComponent("earmark-" + ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(6) + ".json")
            try await Task.detached(priority: .utility) {
                let bytes = try AudioLibraryBackup.encode(library: snapshot, directory: audio)
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var writeError: Error?
                coordinator.coordinate(writingItemAt: file, options: [], error: &coordinationError) { url in
                    do { try bytes.write(to: url, options: .atomic) } catch { writeError = error }
                }
                if let coordinationError { throw coordinationError }
                if let writeError { throw writeError }
            }.value
            lastSuccess = now; defaults.set(now, forKey: "automaticBackupLastSuccess"); error = nil
        } catch { self.error = "Backup could not be saved. Choose the folder again or retry." }
    }
}

struct AutomaticBackupSettings: View {
    @ObservedObject var backup: AutomaticBackupStore
    let savePosition: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var selectionError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(backup.configured ? "Change backup folder" : "Choose iCloud Drive folder") { choosing = true }
                    if backup.configured {
                        Text(backup.folderName).foregroundStyle(.secondary)
                        Toggle("Daily backup", isOn: $backup.enabled)
                        Button(backup.running ? "Saving…" : "Back up now") {
                            savePosition(); Task { await backup.runIfDue(force: true) }
                        }.disabled(backup.running)
                    }
                    if let date = backup.lastSuccess { LabeledContent("Last saved") { Text(date, format: .dateTime.month().day().hour().minute()) } }
                    if let error = selectionError ?? backup.error { Text(error).foregroundStyle(.red).font(.footnote) }
                } footer: {
                    Text("Choose a folder in iCloud Drive. Saves links, folders, listening progress, and imported audio once a day while earmark is open, or when you reopen it. Restore a saved JSON file with Restore backup.")
                }
            }
            .navigationTitle("Automatic backups").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                do {
                    try backup.choose(result.get()); savePosition(); selectionError = nil
                    Task { await backup.runIfDue(force: true) }
                } catch { selectionError = "Could not access that folder." }
            }
            .tint(rose)
        }
    }
}
