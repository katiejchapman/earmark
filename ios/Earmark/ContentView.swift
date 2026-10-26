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
    @State private var importing = false
    @State private var importingAudio = false
    @State private var archiveOnlyImport = false
    @State private var creatingFolder = false
    @State private var backup = LibraryDocument()
    @State private var pendingRestore: Data?
    @State private var confirmingRestore = false
    @State private var notice: String?
    @State private var scrub: Double?
    @State private var globalListened = false
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
            studio.updateLayout(stereo: frames["stereo"], obstacles: frames.filter { $0.key.hasPrefix("protected-") }.sorted { $0.key < $1.key }.map { $0.value })
        }
        .onChange(of: studio.error) { _, error in if let error { notice = error } }
        .tint(rose)
        .font(AppType.font(.body))
        .sheet(item: $editing) { entry in
            NameEditor(entry: entry) { title, folder in
                store.rename(entry.id, title: title, show: entry.show)
                store.move(entry.id, to: store.addFolder(folder))
                player.updateNowPlaying()
            }
        }
        .confirmationDialog("Audio options", isPresented: Binding(get: { archiveActions != nil }, set: { if !$0 { archiveActions = nil } }), titleVisibility: .hidden, presenting: archiveActions) { entry in
            Button(entry.isFeed ? "Refresh feed" : "Load in player") {
                player.load(entry)
                if entry.localFilename == nil { link = entry.url.absoluteString }
            }
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
                    var first: Recording?
                    for url in urls {
                        let entry = try store.importAudio(url)
                        if first == nil { first = entry }
                    }
                    if let first, !archiveOnlyImport { player.load(first) }
                } else if let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    pendingRestore = try Data(contentsOf: url)
                    confirmingRestore = true
                }
            } catch { notice = "Couldn’t import: \(error.localizedDescription)" }
        }
        .onOpenURL { url in
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
                LinkInput(text: $link, focused: Binding(get: { linkFocused }, set: { linkFocused = $0 }), onSubmit: loadLink) { _ in }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .frame(minWidth: 60, maxWidth: .infinity).frame(height: 34)
                    .background(card, in: RoundedRectangle(cornerRadius: 11))
                Button { archiveOnlyImport = player.currentID != nil; importingAudio = true; importing = true } label: {
                    HStack(spacing: 3) { Image(systemName: "folder.badge.plus"); Text("add file") }
                        .font(AppType.fixed(11, weight: 600)).frame(width: 66, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(rose.opacity(0.65)))
                        .frame(height: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("importAudio")
                Button("load", action: loadLink).font(AppType.fixed(11, weight: 600))
                    .frame(width: 44, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(rose.opacity(0.65)))
                    .frame(height: 44).buttonStyle(.plain).accessibilityIdentifier("loadLink")
                Menu {
                    Button("Save link to archive", systemImage: "link") { saveLink() }
                        .accessibilityIdentifier("archiveLink")
                    Button("Save files to archive", systemImage: "folder.badge.plus") {
                        archiveOnlyImport = true; importingAudio = true; importing = true
                    }.accessibilityIdentifier("archiveFile")
                } label: {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 15))
                        .frame(width: 34, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(rose.opacity(0.65)))
                        .frame(height: 44)
                }.buttonStyle(.borderless).accessibilityLabel("Save to archive").accessibilityIdentifier("saveArchive")
            }
            if let duplicate = store.duplicateNotice {
                Text(duplicate).font(AppType.font(.caption1)).foregroundStyle(rose).accessibilityIdentifier("duplicateNotice")
            }
            if let message = player.message {
                Text(message) .font(AppType.font(.caption1)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func saveLink() {
        do { _ = try store.remember(link); linkFocused = false }
        catch { notice = error.localizedDescription }
    }
    private func loadLink() {
        do { let entry = try store.remember(link); player.load(entry); linkFocused = false }
        catch { notice = error.localizedDescription }
    }

    private var playerCard: some View {
        VStack(spacing: 12) {
            Gems(count: 11).padding(.horizontal, 22).protectedStereo("rhinestones").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(player.current?.title ?? "A little listening time")
                    .font(.system(size: 19, weight: .semibold, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nowPlayingTitle")
                if let current = player.current {
                    HStack(alignment: .firstTextBaseline) {
                        Text(current.folder ?? "Unarchived")
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
            VStack(spacing: 0) {
                SilverScrubber(value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }), duration: player.duration, enabled: player.duration > 0 && !player.loading, savedPosition: player.visibleScrubReturnPosition, onReturn: { player.returnToSavedPosition(); scrub = nil }) {
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
                controls.padding(.top, -3).protectedStereo("playback")
            }
            Color.clear.frame(height: 26)
            HStack {
                SleepControl(player: player, active: player.sleepDeadline != nil, dark: dark).equatable().protectedStereo("sleep")
                Spacer()
            Button {
                store.duplicateNotice = nil
                player.reset(); scrub = nil; link = ""; linkFocused = false
            } label: {
                Text("reset").font(AppType.fixed(11))
                    .frame(width: 58, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: dark ? 0x928693 : 0x858c82)))
                    .frame(width: 58, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("resetPlayer").protectedStereo("reset")
            }
            HStack(spacing: 10) {
                Group {
                    if player.currentID != nil {
                        Circle().fill(RadialGradient(colors: [Color(hex: 0xffd5cf), Color(hex: 0xff243d), Color(hex: 0x9a0020)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1))
                            .shadow(color: .red.opacity(0.85), radius: 5)
                            .accessibilityLabel("Audio loaded").accessibilityIdentifier("loadedLight")
                    } else { Color.clear.frame(width: 10, height: 10).accessibilityHidden(true) }
                }.frame(width: 28, height: 44).protectedStereo("light")
                Speaker(dark: dark).frame(height: 22)
                    .protectedStereo("mesh").accessibilityIdentifier("speakerMesh").accessibilityHidden(true)
                Button { studio.editing ? studio.finish() : studio.begin() } label: {
                    StickerSheetIcon().frame(width: 23, height: 23)
                        .frame(width: 38, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color(hex: dark ? 0xaaa3ac : 0x777e75)))
                        .frame(height: 44)
                }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel("Decorate stereo")
                    .accessibilityIdentifier("decorateStereo").protectedStereo("decorate")
            }

        }
        .padding(20)
        .background(LinearGradient(colors: metal, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.gray.opacity(0.8)))
        .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: ["stereo": geometry.frame(in: .global)]) })
        .overlay { StickerDisplay(studio: studio) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("stereoPlayer")
    }
    private var controls: some View {
        HStack(spacing: 18) {
            control("« 15", label: "Back 15 seconds", size: 44) { player.skip(-15) }
            control(player.playing ? "pause.fill" : "play.fill", label: player.playing ? "Pause" : "Play", size: 58, main: true) { player.toggle() }
            control("15 »", label: "Forward 15 seconds", size: 44) { player.skip(15) }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: ["controls": geometry.frame(in: .global)]) })
    }
    private func control(_ icon: String, label: String, size: CGFloat, main: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if main {
                    Image(systemName: icon).font(.system(size: 20, weight: .medium))
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
                .background(Color(hex: main ? 0xdfa3bf : (dark ? 0x66656e : 0xd3d7ce)), in: Circle())
                .overlay(Circle().strokeBorder(Color(hex: main ? 0xb97998 : (dark ? 0x928693 : 0x858c82)), lineWidth: main ? 3 : 1))
        }.buttonStyle(.plain).accessibilityLabel(label).disabled(player.currentID == nil)
    }
    @ViewBuilder private var sleepCountdown: some View {
        if player.sleepDeadline != nil {
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
            ForEach(store.data.folders, id: \.self) { folderView($0) }
            folderView(nil)
            statusTabs(store.data.entries, selected: $globalListened, scope: "global")
                .padding(.top, 8)
            ForEach(store.data.entries.filter { ($0.listened == true) == globalListened }) { entry in
                archiveRow(entry, showFolder: true)
            }
        }
    }
    private func createFolder() { _ = store.addFolder(folder); folder = "" }
    @ViewBuilder private func folderView(_ folder: String?) -> some View {
        let entries = store.data.entries.filter { $0.folder == folder }
        let key = folder ?? ""
        let title = "\(folder ?? "Unarchived") · \(entries.count)"
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
                }.accessibilityLabel("\(expandedFolders.contains(key) ? "Collapse" : "Expand") \(folder ?? "Unarchived")")
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
                ForEach(entries.filter { ($0.listened == true) == (folderListened[key] ?? false) }) { entry in
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
                    Text(entry.title).font(AppType.font(.subheadline, weight: 600)).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(entry.listened == true ? Color(hex: dark ? 0x9fc8c2 : 0x49796f) : .primary)
                    Text(showFolder ? (entry.folder ?? "Unarchived") : (entry.show.isEmpty ? (entry.localFilename == nil ? (entry.url.host ?? "Audio") : "Audio file") : entry.show))
                         .font(AppType.font(.caption1)).foregroundStyle(.secondary)
                    if entry.listened != true && !entry.isFeed {
                        HStack(spacing: 8) {
                            ProgressView(value: progress ?? 0).tint(rose).frame(maxWidth: .infinity)
                            Text(percent).font(AppType.fixed(10, weight: 600)).monospacedDigit()
                                .foregroundStyle(.secondary).frame(minWidth: 29, alignment: .trailing)
                        }.padding(.top, 2).accessibilityHidden(true)
                    }
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
        .accessibilityLabel(showFolder ? "Options for \(entry.title), \(entry.folder ?? "Unarchived")" : "Options for \(entry.title)")
        .accessibilityValue(entry.listened == true ? "Listened" : (entry.isFeed ? "Not listened" : "Not listened, \(percent) played"))
        .accessibilityIdentifier("\(showFolder ? "globalArchiveEntry" : "archiveEntry")-\(entry.id)")
        .opacity(draggingID == entry.id ? 0.4 : 1)
        .highPriorityGesture(archiveDrag(entry).simultaneously(with: TapGesture().onEnded { archiveActions = entry }))
    }
    private func toggleFolder(_ key: String) {
        withAnimation {
            if !expandedFolders.insert(key).inserted { expandedFolders.remove(key) }
        }
    }
    private func archiveDrag(_ entry: Recording) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                draggingID = entry.id; dragLocation = drag.location
                dropTargetFolder = folderFrames.first(where: { $0.value.contains(drag.location) })?.key
            }
            .onEnded { value in
                if case .second(true, let drag?) = value,
                   let folder = folderFrames.first(where: { $0.value.contains(drag.location) })?.key,
                   store.data.folders.contains(folder), store.entry(entry.id) != nil {
                    withAnimation { store.move(entry.id, to: folder) }
                }
                draggingID = nil; dropTargetFolder = nil
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
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.placeholder = "link"
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
                Button("Cancel sleep timer", role: .destructive) { player.cancelSleepTimer() }.buttonStyle(.automatic)
            }
        } label: {
            Text("sleep").font(AppType.fixed(11)).frame(width: 58, height: 26)
                .foregroundStyle(active ? Color(hex: 0x583346) : Color.primary)
                .background(active ? rose : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: dark ? 0x928693 : 0x858c82)))
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.automatic).accessibilityLabel("Sleep timer").accessibilityIdentifier("sleepTimer")
    }
}

private struct Disc: View {
    var body: some View {
        Image("Disc").resizable().scaledToFit()
    }
}

private struct SilverScrubber: View {
    @Binding var value: Double
    let duration: Double
    let enabled: Bool
    let savedPosition: Double?
    let onReturn: () -> Void
    let onEnd: () -> Void
    private var fraction: Double { min(1, max(0, value / max(1, duration))) }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x8f988b)).frame(height: 4)
                    .overlay(alignment: .bottom) { Capsule().fill(.white.opacity(0.45)).frame(height: 1).offset(y: 1) }
                Capsule().fill(Color(hex: 0xb85280)).frame(width: 8 + width * fraction, height: 4)
                if let saved = savedPosition, duration > 0 {
                    Rectangle().fill(Color.black.opacity(0.65)).frame(width: 2, height: 4)
                        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.55)).frame(width: 0.5) }
                        .offset(x: min(geometry.size.width - 2, max(0, 7 + width * min(1, max(0, saved / duration)))))
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
                if let saved = savedPosition, abs(gesture.startLocation.x - (8 + width * saved / max(1, duration))) < 12,
                   hypot(gesture.translation.width, gesture.translation.height) < 6 { return }
                value = min(1, max(0, (gesture.location.x - 8) / width)) * duration
            }.onEnded { gesture in
                guard enabled else { return }
                if let saved = savedPosition, abs(gesture.startLocation.x - (8 + width * saved / max(1, duration))) < 12,
                   hypot(gesture.translation.width, gesture.translation.height) < 6 { onReturn() }
                else { onEnd() }
            })
        }
        .frame(height: 24)
        .allowsHitTesting(enabled)
        .accessibilityElement().accessibilityLabel("Playback position")
        .accessibilityValue("\(ContentView.time(value)) of \(ContentView.time(duration))")
        .accessibilityAction(named: "Return to saved position") { if savedPosition != nil { onReturn() } }
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

private struct NameEditor: View {
    @Environment(\.dismiss) var dismiss
    @State private var title: String
    @State private var folder: String
    let save: (String, String) -> Void
    init(entry: Recording, save: @escaping (String, String) -> Void) { _title = State(initialValue: entry.title); _folder = State(initialValue: entry.folder ?? ""); self.save = save }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Episode or audio title", text: $title)
                TextField("Folder name (optional)", text: $folder)
            }.navigationTitle("Rename").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(title, folder); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
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
