import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CoreText

enum AppType {
    static func uiFont(_ style: UIFont.TextStyle, weight: Double = 500) -> UIFont {
        variableFont(size: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
    }
    static func font(_ style: UIFont.TextStyle, weight: Double = 500) -> Font {
        Font(uiFont(style, weight: weight))
    }
    static func fixed(_ size: CGFloat, weight: Double = 500) -> Font {
        Font(variableFont(size: size, weight: weight))
    }
    private static func variableFont(size: CGFloat, weight: Double) -> UIFont {
        guard let base = UIFont(name: "Quicksand-Light", size: size) else { return .systemFont(ofSize: size) }
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [NSNumber(value: 0x77676874): NSNumber(value: weight)]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

let rose = Color(red: 0.87, green: 0.64, blue: 0.75)

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var player: AudioPlayer
    @ObservedObject var studio: StickerStudioStore
    @State private var studioFrames: [String: CGRect] = [:]
    @AppStorage("darkMode") private var dark = true
    @AppStorage("showRemaining") private var remaining = false
    @State private var link = ""
    @State private var folder = ""
    @State private var editing: Recording?
    @State private var exporting = false
    @State private var showingAutoBackup = false
    @EnvironmentObject private var autoBackup: AutomaticBackupStore
    @State private var importing = false
    @State private var importingAudio = false
    @State private var sourceIsFile = false
    @State private var stagedAudio: [URL] = []
    @State private var creatingFolder = false
    @State private var backup = LibraryDocument()
    @State private var pendingRestore: Data?
    @State private var confirmingRestore = false
    @State private var notice: String?
    @State private var scrub: Double?
    @State private var globalListened = false
    @AppStorage("archiveNewestFirst") private var newestFirst = true
    @State private var folderListened: [String: Bool] = [:]
    @State private var expandedFolders: Set<String> = []
    @State private var renamingFolder: String?
    @State private var renamedFolder = ""
    @State private var dropTargetFolder: String?
    @State private var archiveActions: Recording?
    @State private var folderFrames: [String: CGRect] = [:]
    @State private var draggingID: UUID?
    @State private var dragLocation = CGPoint.zero
    @State private var linkFocused = false
    @State private var widgetSleepOptions = false

    private var paper: Color { dark ? Color(red: 0.10, green: 0.09, blue: 0.12) : Color(hex: 0xd8ceca) }
    private var card: Color { dark ? Color(red: 0.16, green: 0.14, blue: 0.18) : Color(red: 0.98, green: 0.96, blue: 0.94) }
    private var metal: [Color] { dark ? [Color(hex: 0x777880), Color(hex: 0x42454d), Color(hex: 0x686b73), Color(hex: 0x34373d)] : [Color(hex: 0xf2f3ee), Color(hex: 0xbfc4bd), Color(hex: 0xe4e6df), Color(hex: 0xa5aca5)] }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Group {
                header
                linkField
                playerCard
                if studio.editing { StickerSheet(studio: studio) }
                library
                if let error = store.storageError { Text(error).font(AppType.font(.footnote)).foregroundStyle(.red).accessibilityIdentifier("storageError") }
            }
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .buttonStyle(.borderless)
        .scrollDismissesKeyboard(.interactively)
        } // ScrollViewReader
        .background(paper.ignoresSafeArea())
        .overlay {
            GeometryReader { geometry in
                if let entry = store.entry(draggingID) {
                    Text(entry.title).font(AppType.font(.subheadline, weight: 600)).lineLimit(2)
                        .padding(15).frame(width: 250, alignment: .leading)
                        .background(card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(rose))
                        .position(x: dragLocation.x - geometry.frame(in: .global).minX,
                                  y: dragLocation.y - geometry.frame(in: .global).minY)
                }
            }.allowsHitTesting(false)
        }
        .overlay { StickerTouchLayer(studio: studio, frames: studioFrames).allowsHitTesting(studio.editing) }
        .onPreferenceChange(StudioFramesKey.self) { frames in
            studioFrames = frames
            studio.updateLayout(stereo: frames["stereo"], decoration: frames["decoration"], obstacles: frames.filter { $0.key.hasPrefix("protected-") }.sorted { $0.key < $1.key }.map { $0.value })
        }
        .onChange(of: studio.error) { _, error in if let error { notice = error } }
        .tint(rose)
        .font(AppType.font(.body))
        .sheet(isPresented: $showingAutoBackup) { AutomaticBackupSettings(backup: autoBackup, savePosition: player.savePosition) }
        .sheet(item: $editing) { entry in
            NameEditor(entry: entry, folders: store.data.folders) { title, folder in
                store.rename(entry.id, title: title, show: entry.show)
                store.move(entry.id, to: store.addFolder(folder))
                player.updateNowPlaying()
            }
        }
        .confirmationDialog("Audio options", isPresented: Binding(get: { archiveActions != nil }, set: { if !$0 { archiveActions = nil } }), titleVisibility: .hidden, presenting: archiveActions) { entry in
            Button(entry.isFeed ? "Refresh feed" : "Load in player") {
                player.load(entry)
                if entry.localFilename == nil { sourceIsFile = false; link = entry.url.absoluteString }
            }
            Button("Add to queue") { store.enqueue(entry.id) }
            Button("Rename") { editing = entry }
            Button(entry.listened == true ? "Mark as unlistened" : "Mark as listened") {
                store.setListened(entry.listened != true, for: entry.id)
            }
            Button("Delete", role: .destructive) {
                if player.currentID == entry.id { player.stop() }
                store.delete(entry.id)
            }
            Button("Cancel", role: .cancel) { }
        }
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "earmark-library") { result in
            if case .failure(let error) = result { notice = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importingAudio ? [.audio, .mpeg4Movie] : [.json], allowsMultipleSelection: importingAudio) { result in
            do {
                let urls = try result.get()
                if importingAudio {
                    let staged = try AudioSelection.stage(urls)
                    clearStagedAudio()
                    stagedAudio = staged
                } else if let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    pendingRestore = try Data(contentsOf: url)
                    confirmingRestore = true
                }
            } catch { notice = "Couldn’t import: \(error.localizedDescription)" }
        }
        .onDisappear { clearStagedAudio() }
        .onChange(of: sourceIsFile) { _, isFile in if !isFile { clearStagedAudio() } }
        .onOpenURL { url in
            if url.scheme == "earmark", url.host == "widget" {
                switch url.lastPathComponent {
                case "decorate": studio.begin()
                case "sleep": widgetSleepOptions = true
                default: player.handleWidgetAction(url.lastPathComponent)
                }
                return
            }
            guard url.isFileURL else { return }
            do { player.load(try store.importAudio(url)) }
            catch { notice = "Couldn’t import audio: \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace your library with this backup?", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) {
                guard let bytes = pendingRestore else { return }
                do { player.stop(); try store.restore(bytes); player.restoreLast(); notice = "Library restored." }
                catch { notice = error.localizedDescription }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { Text("Your current links, folders, and positions will be replaced. Export them first if you want to keep them.") }
        .alert("Earmark", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
        .safeAreaInset(edge: .bottom) {
            if store.canUndoDelete {
                HStack {
                    Text("deleted").font(AppType.font(.subheadline))
                    Spacer()
                    Button("undo") { store.undoDelete() }.accessibilityIdentifier("undoDelete")
                }.padding(14).background(.regularMaterial)
            }
        }
        .confirmationDialog("Sleep timer", isPresented: $widgetSleepOptions) {
            ForEach([5, 15, 30], id: \.self) { minutes in
                Button("\(minutes) minutes") { player.setSleepTimer(seconds: Double(minutes * 60)) }
            }
            if player.sleepActive { Button("Cancel", role: .destructive) { player.cancelSleepTimer() } }
        }
        .alert("New folder", isPresented: $creatingFolder) {
            TextField("Folder name", text: $folder).accessibilityIdentifier("folderName")
            Button("Create", action: createFolder)
            Button("Cancel", role: .cancel) { folder = "" }
        }
        .alert("Rename folder", isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            TextField("Folder name", text: $renamedFolder)
            Button("Save") {
                if let old = renamingFolder {
                    if let name = store.renameFolder(old, to: renamedFolder) {
                        if expandedFolders.remove(old) != nil { expandedFolders.insert(name) }
                    } else { notice = "Choose a unique, nonempty folder name." }
                }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Disc().frame(width: 72, height: 72).accessibilityHidden(true)
            Image("Wordmark").resizable().renderingMode(.template).scaledToFit().frame(maxWidth: 190).frame(height: 72).accessibilityLabel("earmark")
            Spacer(minLength: 8)
            Button { dark.toggle() } label: {
                Image(systemName: dark ? "sun.max" : "moon").font(.system(size: 21)).frame(width: 44, height: 44)
                    .background(card, in: Circle()).overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dark ? "Switch to light mode" : "Switch to dark mode")
            .accessibilityIdentifier("themeToggle")
        }
        .padding(.bottom, 6)
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    sourceToggle("link", file: false)
                    sourceToggle("file", file: true)
                }
                .padding(3).frame(width: 80, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.35)))
                .accessibilityElement(children: .contain).accessibilityLabel("Audio source")
                if sourceIsFile {
                    Button { linkFocused = false; importingAudio = true; importing = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                            Text(stagedAudio.first.map { stagedAudio.count == 1 ? $0.lastPathComponent : "\(stagedAudio.count) files" } ?? "add file")
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .font(AppType.fixed(11)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).frame(height: 34)
                        .background(card, in: RoundedRectangle(cornerRadius: 11))
                        .frame(height: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("importAudio")
                } else {
                    LinkInput(text: $link, focused: Binding(get: { linkFocused }, set: { linkFocused = $0 }), onSubmit: loadLink) { _ in }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(minWidth: 30, maxWidth: .infinity).frame(height: 34)
                        .background(card, in: RoundedRectangle(cornerRadius: 11))
                }
                Button("load") { performSource(load: true) }
                    .font(AppType.fixed(11, weight: 650)).foregroundStyle(Color(hex: 0x563243))
                    .frame(width: 43, height: 34).background(rose, in: RoundedRectangle(cornerRadius: 11))
                    .frame(height: 44).buttonStyle(.plain).accessibilityIdentifier("loadLink")
                Button { performSource(load: false) } label: {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 15))
                        .frame(width: 32, height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(rose.opacity(0.65)))
                        .frame(height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Save to archive").accessibilityIdentifier("saveArchive")
            }
            if let duplicate = store.duplicateNotice {
                Text(duplicate).font(AppType.font(.caption1)).foregroundStyle(rose).accessibilityIdentifier("duplicateNotice")
            }
            if let message = player.message {
                Text(message) .font(AppType.font(.caption1)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func sourceToggle(_ title: String, file: Bool) -> some View {
        Button { linkFocused = false; sourceIsFile = file } label: {
            Text(title).font(AppType.fixed(10, weight: 600)).frame(maxWidth: .infinity).frame(height: 28)
                .background(sourceIsFile == file ? card : .clear, in: RoundedRectangle(cornerRadius: 7))
                .frame(height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(file ? "sourceFile" : "sourceLink")
            .accessibilityAddTraits(sourceIsFile == file ? .isSelected : [])
    }
    private func clearStagedAudio() {
        AudioSelection.remove(stagedAudio); stagedAudio = []
    }
    private func performSource(load: Bool) {
        do {
            let entries: [Recording]
            if sourceIsFile {
                guard !stagedAudio.isEmpty else { importingAudio = true; importing = true; return }
                entries = try stagedAudio.map { try store.importAudio($0) }
            } else { entries = [try store.remember(link)] }
            if load, let first = entries.first { player.load(first) }
            linkFocused = false
        } catch { notice = error.localizedDescription }
    }
    private func loadLink() { performSource(load: true) }

    private var playerCard: some View {
        VStack(spacing: 12) {
            Gems(count: 11).padding(.horizontal, 22).protectedStereo("rhinestones").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(player.current?.title ?? "A little listening time")
                    .font(.system(size: 19, weight: .semibold, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nowPlayingTitle")
                if let current = player.current {
                    HStack(alignment: .firstTextBaseline) {
                        Text(current.folder ?? "inbox")
                            .font(.system(size: 11, design: .monospaced))
                            .accessibilityIdentifier("nowPlayingFolder")
                        Spacer(minLength: 8)
                        sleepCountdown
                    }
                }
                if player.current == nil { sleepCountdown }
                if let show = player.current?.show, !show.isEmpty, show != player.current?.folder {
                    Text(show)
                        .font(.system(size: 11, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color(red: 0.18, green: 0.24, blue: 0.15))
            .padding(15).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [Color(hex: 0xb1bca4).opacity(0.92), Color(hex: 0x97a48d).opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.24), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 17).clipShape(UnevenRoundedRectangle(topLeadingRadius: 13, topTrailingRadius: 13)).allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(LinearGradient(colors: [Color(hex: 0x383c40).opacity(0.8), Color(hex: 0x9a9f98).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 5))
            .shadow(color: .white.opacity(dark ? 0.16 : 0.45), radius: 0, x: 0, y: 1)
            .protectedStereo("screen")
            .padding(.horizontal, 18)
            VStack(spacing: 0) {
                SilverScrubber(value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }), duration: player.duration, enabled: player.duration > 0 && !player.loading, savedPositions: player.scrubNotches.map(\.position), onReturn: { player.returnToSavedPosition($0); scrub = nil }) {
                    if let scrub { player.seek(scrub) }; scrub = nil
                }.protectedStereo("scrubber")
                HStack {
                    Text(Self.time(scrub ?? player.position))
                    Spacer()
                    Button { remaining.toggle() } label: {
                        Text(remaining ? "−\(Self.time(max(0, player.duration - (scrub ?? player.position))))" : Self.time(player.duration))
                            .frame(minHeight: 24)
                    }.buttonStyle(.plain).accessibilityLabel(remaining ? "Show total time" : "Show time remaining")
                }.font(AppType.fixed(12)).monospacedDigit()
                    .protectedStereo("time")
                HStack(spacing: 4) {
                    SleepControl(player: player, active: player.sleepActive, dark: dark).equatable().protectedStereo("sleep")
                    Spacer(minLength: 0)
                    controls.protectedStereo("playback")
                    Spacer(minLength: 0)
                    Button {
                        store.duplicateNotice = nil
                        player.reset(); scrub = nil; link = ""; linkFocused = false
                    } label: {
                        Text("reset").font(AppType.fixed(10))
                            .frame(width: 50, height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: dark ? 0x928693 : 0x858c82)))
                            .frame(width: 50, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("resetPlayer").protectedStereo("reset")
                }.padding(.top, -3)
            }
            Color.clear.frame(height: 36)
                .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: ["decoration": geometry.frame(in: .global)]) })
            HStack(spacing: 10) {
                Circle().fill(RadialGradient(colors: player.playing ? [Color(hex: 0xffd5cf), Color(hex: 0xff243d), Color(hex: 0x9a0020)] : [Color(hex: 0x653039), Color(hex: 0x401c25), Color(hex: 0x29151c)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
                    .shadow(color: player.playing ? .red.opacity(0.85) : .clear, radius: 5)
                    .accessibilityLabel(player.playing ? "Audio playing" : "Audio stopped")
                    .accessibilityIdentifier("loadedLight").protectedStereo("light")
                    .frame(width: 28, height: 44)
                Speaker(dark: dark).frame(height: 22)
                    .protectedStereo("mesh").accessibilityIdentifier("speakerMesh").accessibilityHidden(true)
                    .padding(.horizontal, 28)
                Button { studio.editing ? studio.finish() : studio.begin() } label: {
                    StickerSheetIcon().frame(width: 23, height: 23)
                        .frame(width: 38, height: 30)
                        .frame(height: 44)
                }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel("Decorate stereo")
                    .accessibilityIdentifier("decorateStereo").protectedStereo("decorate")
            }.frame(height: 88, alignment: .bottom)

        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
        .background(LinearGradient(colors: metal, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.gray.opacity(0.8)))
        .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: ["stereo": geometry.frame(in: .global)]) })
        .overlay { StickerDisplay(studio: studio) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("stereoPlayer")
    }
    private var controls: some View {
        HStack(spacing: 8) {
            control("« 15", label: "Back 15 seconds", size: 32) { player.skip(-15) }
            control(player.playing ? "pause.fill" : "play.fill", label: player.playing ? "Pause" : "Play", size: 42, main: true) { player.toggle() }
            control("15 »", label: "Forward 15 seconds", size: 32) { player.skip(15) }
        }
        .frame(minHeight: 44)
        .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: ["controls": geometry.frame(in: .global)]) })
    }
    private func control(_ icon: String, label: String, size: CGFloat, main: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if main {
                    Image(systemName: icon).font(.system(size: 17, weight: .medium))
                } else {
                    HStack(spacing: 3) {
                        if icon.hasPrefix("«") { Text("«") }
                        Text("15")
                        if icon.hasSuffix("»") { Text("»") }
                    }.font(AppType.fixed(11, weight: 650)).fixedSize()
                        .multilineTextAlignment(.center)
                }
            }
                .frame(width: size, height: size, alignment: .center)
                .foregroundStyle(main ? Color(hex: 0x583346) : Color(hex: dark ? 0xfaf2f7 : 0x303831))
                .background(RadialGradient(colors: [Color(hex: main ? 0xe6afc9 : (dark ? 0x74737c : 0xe0e3dc)), Color(hex: main ? 0xdfa3bf : (dark ? 0x66656e : 0xd3d7ce)), Color(hex: main ? 0xd99bb8 : (dark ? 0x605f68 : 0xcbd0c7))], center: .init(x: 0.4, y: 0.3), startRadius: 0, endRadius: size), in: Circle())
                .overlay(Circle().strokeBorder(Color(hex: main ? 0xb97998 : (dark ? 0x928693 : 0x858c82)), lineWidth: main ? 3 : 1))
        }.frame(height: 44).buttonStyle(.plain).accessibilityLabel(label).disabled(player.currentID == nil)
    }
    @ViewBuilder private var sleepCountdown: some View {
        if player.sleepActive {
            Text("sleep \(Self.time(ceil(player.sleepRemaining)))").font(.system(size: 10, design: .monospaced)).monospacedDigit()
                .fixedSize().accessibilityIdentifier("sleepCountdown")
        }
    }

    private var library: some View {
        Group {
            HStack {
                Text("archive").font(AppType.font(.title2, weight: 600))
                Spacer()
                Button { folder = ""; creatingFolder = true } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }.accessibilityLabel("Create folder")
                Menu {
                    Button(newestFirst ? "Newest first ✓" : "Newest first") { newestFirst = true }
                    Button(!newestFirst ? "Oldest first ✓" : "Oldest first") { newestFirst = false }
                } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 36, height: 44) }
                    .accessibilityLabel("Sort by date added").accessibilityIdentifier("archiveSort")
                Menu {
                    Button("Automatic backups", systemImage: "icloud.and.arrow.up") { showingAutoBackup = true }
                    Button("Export library", systemImage: "square.and.arrow.up") {
                        do { player.savePosition(); backup = LibraryDocument(data: try store.exportData()); exporting = true }
                        catch { notice = error.localizedDescription }
                    }
                    Button("Restore backup", systemImage: "square.and.arrow.down") { importingAudio = false; importing = true }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Library options")
            }
            if store.data.entries.isEmpty && store.data.folders.isEmpty {
                Text("Your pasted links will appear here.").font(AppType.font(.subheadline)).foregroundStyle(.secondary).padding(.vertical, 10)
            }
            if !store.queuedEntries.isEmpty {
                HStack {
                    Text("queue").font(AppType.font(.subheadline, weight: 600))
                    Spacer()
                    Button("clear") { store.clearQueue() }.accessibilityLabel("Clear queue")
                }
                ForEach(store.queuedEntries) { entry in
                    HStack {
                        Button { store.removeFromQueue(entry.id); player.load(entry, autoplay: true) } label: {
                            Text(entry.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button { store.removeFromQueue(entry.id) } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Remove from queue")
                    }.font(AppType.font(.subheadline)).frame(minHeight: 44)
                }
            }
            ForEach(store.data.folders, id: \.self) { folderView($0) }
            folderView(nil)
            statusTabs(store.data.entries, selected: $globalListened, scope: "global")
                .padding(.top, 8)
            ForEach(ordered(store.data.entries.filter { ($0.listened == true) == globalListened })) { entry in
                archiveRow(entry, showFolder: true)
            }
        }
    }
    private func ordered(_ entries: [Recording]) -> [Recording] {
        // Legacy records retain their archive order; no guessed dates are written.
        let indices = Dictionary(uniqueKeysWithValues: store.data.entries.enumerated().map { ($0.element.id, $0.offset) })
        return entries.sorted {
            let a = $0.addedAt ?? .distantPast, b = $1.addedAt ?? .distantPast
            if a != b { return newestFirst ? a > b : a < b }
            return newestFirst ? indices[$0.id, default: 0] < indices[$1.id, default: 0] : indices[$0.id, default: 0] > indices[$1.id, default: 0]
        }
    }
    private func createFolder() { _ = store.addFolder(folder); folder = "" }
    @ViewBuilder private func folderView(_ folder: String?) -> some View {
        let entries = store.data.entries.filter { $0.folder == folder }
        let key = folder ?? ""
        let title = "\(folder ?? "inbox") · \(entries.count)"
        if folder != nil || !entries.isEmpty {
            HStack(spacing: 8) {
                Button { toggleFolder(key) } label: {
                    Text(title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("folderHeader-\(key)")
                if let folder {
                    Menu {
                        Button("Rename folder", systemImage: "pencil") {
                            renamedFolder = folder; renamingFolder = folder
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.accessibilityLabel("Options for folder \(folder)")
                        .accessibilityIdentifier("folderMenu-\(folder)")
                }
                Button { toggleFolder(key) } label: {
                    Image(systemName: expandedFolders.contains(key) ? "chevron.down" : "chevron.right")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("\(expandedFolders.contains(key) ? "Collapse" : "Expand") \(folder ?? "inbox")")
            }
            .font(AppType.font(.subheadline, weight: 600)).foregroundStyle(.primary)
            .buttonStyle(.plain)
            .padding(.horizontal, 15).padding(.vertical, 4)
            .background(card, in: RoundedRectangle(cornerRadius: 17))
            .background {
                if let folder {
                    GeometryReader { geometry in
                        let frame = geometry.frame(in: .global)
                        Color.clear
                            .onAppear { folderFrames[folder] = frame }
                            .onChange(of: frame) { _, frame in folderFrames[folder] = frame }
                            .onDisappear { folderFrames.removeValue(forKey: folder) }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(dropTargetFolder == folder && folder != nil ? rose : .clear, lineWidth: 2))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let folder {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.deleteFolder(folder); expandedFolders.remove(key)
                    }.buttonStyle(.automatic).accessibilityIdentifier("deleteFolder-\(folder)")
                }
            }
            if expandedFolders.contains(key) {
                statusTabs(entries, selected: Binding(get: { folderListened[key] ?? false }, set: { folderListened[key] = $0 }), scope: "folder-\(key)")
                    .padding(.horizontal, 15)
                ForEach(ordered(entries.filter { ($0.listened == true) == (folderListened[key] ?? false) })) { entry in
                    archiveRow(entry)
                }
            }
        }
    }
    private func statusTabs(_ entries: [Recording], selected: Binding<Bool>, scope: String) -> some View {
        HStack(spacing: 24) {
            ForEach([false, true], id: \.self) { listened in
                Button { selected.wrappedValue = listened } label: {
                    HStack(spacing: 5) {
                        Text(listened ? "listened" : "listening")
                        Text("\(entries.filter { ($0.listened == true) == listened }.count)").font(AppType.font(.caption2)).foregroundStyle(.secondary)
                    }
                    .font(AppType.font(.subheadline)).foregroundStyle(selected.wrappedValue == listened ? .primary : .secondary)
                    .frame(minHeight: 40)
                    .overlay(alignment: .bottom) { if selected.wrappedValue == listened { Capsule().fill(rose).frame(height: 2) } }
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("status-\(listened ? "listened" : "listening")-\(scope)")
                    .accessibilityAddTraits(selected.wrappedValue == listened ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
    private func archiveRow(_ entry: Recording, showFolder: Bool = false) -> some View {
        let progress = entry.id == player.currentID && player.duration > 0 ? min(1, max(0, player.position / player.duration)) : entry.progressFraction
        let percent = progress.map { "\(Int(($0 * 100).rounded(.down)))%" } ?? "—%"
        return VStack(spacing: 0) {
            Divider().padding(.bottom, 10)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(entry.title).font(AppType.font(.subheadline, weight: 600)).lineLimit(2)
                            .foregroundStyle(entry.listened == true ? Color(hex: dark ? 0x9fc8c2 : 0x49796f) : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 4) {
                        if entry.listened != true && !entry.isFeed {
                            HStack(spacing: 5) {
                                GeometryReader { geometry in
                                    Capsule().fill(.secondary.opacity(0.25))
                                    Capsule().fill(rose).frame(width: geometry.size.width * (progress ?? 0))
                                }.frame(width: 41, height: 3)
                                Text(percent).font(AppType.fixed(9, weight: 600)).monospacedDigit()
                                    .foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                            }.accessibilityHidden(true)
                        }
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(showFolder ? (entry.folder ?? "inbox") : (entry.show.isEmpty ? (entry.localFilename == nil ? (entry.url.host ?? "Audio") : "Audio file") : entry.show))
                            .font(AppType.font(.caption1)).lineLimit(1)
                        Spacer(minLength: 0)
                        if let added = entry.addedAt {
                            Text(added, format: .dateTime.month(.abbreviated).day().year()).font(AppType.fixed(9)).lineLimit(1).fixedSize()
                        }
                    }.foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if entry.listened == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: dark ? 0x9fc8c2 : 0x49796f))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 6)
        .contentShape(Rectangle()).foregroundStyle(.primary)
        .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
        .accessibilityAction { archiveActions = entry }
        .accessibilityLabel(showFolder ? "Options for \(entry.title), \(entry.folder ?? "inbox")" : "Options for \(entry.title)")
        .accessibilityValue(entry.listened == true ? "Listened" : (entry.isFeed ? "Not listened" : "Not listened, \(percent) played"))
        .accessibilityIdentifier("\(showFolder ? "globalArchiveEntry" : "archiveEntry")-\(entry.id)")
        .opacity(draggingID == entry.id ? 0.4 : 1)
        .onTapGesture { archiveActions = entry }
        .background(ArchiveHoldDrag(changed: { point in
            draggingID = entry.id; dragLocation = point
            dropTargetFolder = folderFrames.first(where: { $0.value.contains(point) })?.key
        }, ended: { point in
            if let point, let folder = folderFrames.first(where: { $0.value.contains(point) })?.key,
               store.entry(entry.id) != nil, store.data.folders.contains(folder) { store.move(entry.id, to: folder) }
            draggingID = nil; dropTargetFolder = nil
        }))
    }
    private func toggleFolder(_ key: String) {
        withAnimation {
            if !expandedFolders.insert(key).inserted { expandedFolders.remove(key) }
        }
    }
    static func time(_ value: Double) -> String {
        let seconds = Int(value.isFinite ? max(0, value) : 0)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}


extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

private struct LinkInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let onSubmit: () -> Void
    let onPaste: (String) -> Void

    final class Field: UITextField {
        var pasted: ((String) -> Void)?
        override func paste(_ sender: Any?) {
            super.paste(sender)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pasted?(self.text ?? "")
            }
        }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LinkInput
        init(_ parent: LinkInput) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) { if !parent.focused { parent.focused = true } }
        func textFieldDidEndEditing(_ textField: UITextField) { if parent.focused { parent.focused = false } }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { parent.onSubmit(); return true }
        func textFieldShouldClear(_ textField: UITextField) -> Bool { parent.text = ""; return true }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.placeholder = "enter link"
        field.clearButtonMode = .whileEditing
        field.accessibilityIdentifier = "linkField"
        field.font = AppType.uiFont(.subheadline)
        field.adjustsFontForContentSizeCategory = true
        field.keyboardType = .URL; field.returnKeyType = .go
        field.autocapitalizationType = .none; field.autocorrectionType = .no
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.font = AppType.uiFont(.subheadline)
        field.pasted = onPaste
        if field.text != text { field.text = text }
        if focused && !field.isFirstResponder { field.becomeFirstResponder() }
        else if !focused && field.isFirstResponder { field.resignFirstResponder() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Field, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: uiView.intrinsicContentSize.height)
    }
}

// Keep the open system menu stable while the LCD countdown updates every second.
private struct SleepControl: View, Equatable {
    let player: AudioPlayer
    let active: Bool
    let dark: Bool
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.player === rhs.player && lhs.active == rhs.active && lhs.dark == rhs.dark }
    var body: some View {
        Menu {
            ForEach([5, 15, 30], id: \.self) { minutes in
                Button("\(minutes) minutes") { player.setSleepTimer(seconds: Double(minutes * 60)) }
            }
            if active {
                Button("Cancel", role: .destructive) { player.cancelSleepTimer() }.buttonStyle(.automatic)
            }
        } label: {
            Text("sleep").font(AppType.fixed(10)).frame(width: 50, height: 26)
                .foregroundStyle(active ? Color(hex: 0x583346) : Color.primary)
                .background(active ? rose : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: dark ? 0x928693 : 0x858c82)))
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Sleep timer").accessibilityIdentifier("sleepTimer")
    }
}

private struct Disc: View {
    var body: some View {
        Image("Disc").resizable().renderingMode(.original).scaledToFit().environment(\.colorScheme, .light)
    }
}

private struct SilverScrubber: View {
    @Binding var value: Double
    let duration: Double
    let enabled: Bool
    let savedPositions: [Double]
    let onReturn: (Double) -> Void
    let onEnd: () -> Void
    private var fraction: Double { min(1, max(0, value / max(1, duration))) }
    @State private var snapped: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x8f988b)).frame(height: 6)
                    .overlay(alignment: .bottom) { Capsule().fill(.white.opacity(0.45)).frame(height: 1).offset(y: 1) }
                Capsule().fill(Color(hex: 0xb85280)).frame(width: 8 + width * fraction, height: 6)
                ForEach(Array(savedPositions.enumerated()), id: \.offset) { _, saved in
                    let ratio = CGFloat(min(1.0, max(0.0, saved / max(1.0, duration))))
                    let notchX = min(geometry.size.width - 6.0, max(0.0, 5.0 + width * ratio))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(LinearGradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0.25), Color.white.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
                        .frame(width: 6, height: 6)
                        .offset(x: notchX)
                        .accessibilityHidden(true)
                }
                Circle().fill(RadialGradient(colors: [Color.white, Color(hex: 0xdce0df), Color(hex: 0xaeb5b7), Color(hex: 0x737c80)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 12))
                    .overlay(Circle().strokeBorder(Color(hex: 0x7b8588), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 2)
                    .frame(width: 16, height: 16).offset(x: width * fraction)
            }
            .frame(height: 24).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard enabled else { return }
                let target = ScrubTrack.target(x: gesture.location.x, width: geometry.size.width, duration: duration, notches: savedPositions)
                if target.notch != snapped, target.notch != nil { UISelectionFeedbackGenerator().selectionChanged() }
                snapped = target.notch; value = target.time
            }.onEnded { gesture in
                guard enabled else { return }
                let target = ScrubTrack.target(x: gesture.location.x, width: geometry.size.width, duration: duration, notches: savedPositions)
                value = target.time; snapped = nil
                if let notch = target.notch { onReturn(notch) } else { onEnd() }
            })
        }
        .frame(height: 24)
        .allowsHitTesting(enabled)
        .accessibilityElement().accessibilityLabel("Playback position")
        .accessibilityValue("\(ContentView.time(value)) of \(ContentView.time(duration))")
        .accessibilityAction(named: "Return to saved position") { if let saved = savedPositions.first { onReturn(saved) } }
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            value = min(duration, max(0, value + (direction == .increment ? 15 : -15)))
            onEnd()
        }
    }
}
private struct Gems: View {
    var count: Int
    var body: some View {
        HStack {
            ForEach(0..<count, id: \.self) { i in
                Image("RoundRhinestone").resizable().scaledToFit().frame(width: 13, height: 13)
                if i < count - 1 { Spacer(minLength: 2) }
            }
        }.frame(height: 14)
    }
}
private struct Speaker: View {
    let dark: Bool
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 8)
    }
    var body: some View {
        Canvas { context, size in
            for x in stride(from: 0.0, to: size.width, by: 5) {
                for y in stride(from: 0.0, to: size.height, by: 5) {
                    let hole = CGRect(x: x - 1.7, y: y - 1.7, width: 3.4, height: 3.4)
                    context.fill(Path(ellipseIn: hole), with: .radialGradient(Gradient(stops: [
                        .init(color: Color(hex: dark ? 0x111117 : 0x3e493e), location: 0),
                        .init(color: Color(hex: dark ? 0x111117 : 0x3e493e), location: 0.58),
                        .init(color: .clear, location: 1)
                    ]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 1.7))
                }
            }
        }
        .background(Color(hex: dark ? 0x51525c : 0x9fa89b))
        .overlay(alignment: .top) { LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom).frame(height: 6) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}

private struct ClearableNameInput: UIViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "Episode or audio title"
        field.accessibilityIdentifier = "renameTitle"
        field.font = AppType.uiFont(.body)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let clear = UIButton(type: .system)
        clear.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clear.tintColor = .secondaryLabel
        clear.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        clear.accessibilityLabel = "Clear name"; clear.accessibilityIdentifier = "clearRenameTitle"
        clear.addTarget(context.coordinator, action: #selector(Coordinator.clear), for: .touchUpInside)
        field.rightView = clear; field.rightViewMode = .always
        context.coordinator.field = field
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
        field.rightView?.isHidden = text.isEmpty
    }
    final class Coordinator: NSObject {
        var text: Binding<String>
        weak var field: UITextField?
        init(text: Binding<String>) { self.text = text }
        @objc func changed(_ field: UITextField) { text.wrappedValue = field.text ?? "" }
        @objc func clear() { field?.text = ""; text.wrappedValue = ""; field?.becomeFirstResponder() }
    }
}

private struct NameEditor: View {
    @Environment(\.dismiss) var dismiss
    @State private var title: String
    @State private var folder: String
    @State private var makingFolder = false
    @State private var newFolder = ""
    let folders: [String]
    let save: (String, String) -> Void
    init(entry: Recording, folders: [String], save: @escaping (String, String) -> Void) {
        _title = State(initialValue: entry.title)
        _folder = State(initialValue: entry.folder ?? "")
        self.folders = folders; self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                ClearableNameInput(text: $title).frame(height: 44)
                Menu {
                    Button("inbox") { folder = "" }.accessibilityIdentifier("chooseFolder-unarchived")
                    ForEach(folders, id: \.self) { name in
                        Button(name) { folder = name }.accessibilityIdentifier("chooseFolder-\(name)")
                    }
                    if !folder.isEmpty && !folders.contains(folder) {
                        Button(folder) { }
                    }
                    Divider()
                    Button("New folder…", systemImage: "plus") { newFolder = ""; makingFolder = true }
                        .accessibilityIdentifier("renameNewFolder")
                } label: {
                    HStack {
                        Text("Folder"); Spacer()
                        Text(folder.isEmpty ? "inbox" : folder).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("renameFolderPicker")
            }.tint(rose).navigationTitle("Rename").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(title, folder); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("New folder", isPresented: $makingFolder) {
                TextField("Folder name", text: $newFolder).accessibilityIdentifier("renameNewFolderName")
                Button("Create") { folder = newFolder.trimmingCharacters(in: .whitespacesAndNewlines); newFolder = folder }
                    .disabled(newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}
struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private extension View {
    func protectedStereo(_ name: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: StudioFramesKey.self, value: ["protected-" + name: geometry.frame(in: .global)])
        })
    }
}

// UIKit recognizes a held drag without claiming ordinary vertical swipes from the list.
private struct ArchiveHoldDrag: UIViewRepresentable {
    let changed: (CGPoint) -> Void
    let ended: (CGPoint?) -> Void
    func makeUIView(context: Context) -> ArchiveHoldView { ArchiveHoldView() }
    func updateUIView(_ view: ArchiveHoldView, context: Context) { view.changed = changed; view.ended = ended }
}
private final class ArchiveHoldView: UIView, UIGestureRecognizerDelegate {
    var changed: ((CGPoint) -> Void)?
    var ended: ((CGPoint?) -> Void)?
    private weak var scroll: UIScrollView?
    private lazy var hold: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(dragged(_:)))
        gesture.minimumPressDuration = 0.35; gesture.allowableMovement = 10; gesture.delegate = self
        return gesture
    }()
    override func willMove(toWindow newWindow: UIWindow?) {
        window?.removeGestureRecognizer(hold)
        scroll?.isScrollEnabled = true; scroll = nil
        if newWindow == nil { ended?(nil) }
        super.willMove(toWindow: newWindow)
    }
    override func didMoveToWindow() { super.didMoveToWindow(); window?.addGestureRecognizer(hold) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard window != nil, !isHidden else { return false }
        return bounds.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other.view is UIScrollView
    }
    @objc private func dragged(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: window)
        switch gesture.state {
        case .began:
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView { self.scroll = scroll; scroll.isScrollEnabled = false; break }
                ancestor = view.superview
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            changed?(point)
        case .changed: changed?(point)
        case .ended: scroll?.isScrollEnabled = true; scroll = nil; ended?(point)
        case .cancelled, .failed: scroll?.isScrollEnabled = true; scroll = nil; ended?(nil)
        default: break
        }
    }
}
