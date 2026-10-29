import AVFoundation
import MediaPlayer
import Combine

struct ScrubNotch: Identifiable {
    let id = UUID()
    let position: Double
    let expiresAt: Date
}

// Only actual playback contributes to the five-second return-point threshold.
struct ListeningDwell {
    private var started: Double?
    private(set) var accumulated: Double = 0
    mutating func setPlaying(_ playing: Bool, now: Double = ProcessInfo.processInfo.systemUptime) {
        if let started { accumulated += max(0, now - started) }
        started = playing ? now : nil
    }
    mutating func reset() { started = nil; accumulated = 0 }
    var eligible: Bool { accumulated >= 5 }
}

enum ScrubTrack {
    static func target(x: Double, width: Double, duration: Double, notches: [Double]) -> (time: Double, notch: Double?) {
        guard width > 16, duration > 0 else { return (0, nil) }
        let span = width - 16
        let valid = notches.filter { $0.isFinite && (0...duration).contains($0) }
        if let nearest = valid.min(by: { abs(8 + span * $0 / duration - x) < abs(8 + span * $1 / duration - x) }),
           abs(8 + span * nearest / duration - x) <= 9 { return (nearest, nearest) }
        return (max(0, min(1, (x - 8) / span)) * duration, nil)
    }
}

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentID: UUID?
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var message: String?
    let store: LibraryStore
    static var widgetInstance: AudioPlayer?
    private let player = AVPlayer()
    private var status: NSKeyValueObservation?
    private var playbackStatus: NSKeyValueObservation?
    private var clock: Any?
    private var notifications: [NSObjectProtocol] = []
    private var loadTask: Task<Void, Never>?
    private var generation = UUID()
    private var seekGeneration = UUID()
    private var restoring = false
    private var wantsPlayback = false
    private var interruptedPlayback = false
    private var lastSaved: Double = -1
    private var source: URL?
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var sleepRemaining: Double = 0
    @Published private(set) var scrubNotches: [ScrubNotch] = []
    private var notchTask: Task<Void, Never>?
    private var listeningDwell = ListeningDwell()
    @Published private(set) var widgetSleepChoosing = false
    var visibleScrubReturnPosition: Double? { scrubNotches.first?.position }
    func clearScrubReturn() {
        scrubNotches = []; notchTask?.cancel(); notchTask = nil
        if let id = currentID { store.setScrubReturnPosition(nil, for: id) }
    }
    func expireScrubNotches(now: Date = Date()) {
        scrubNotches.removeAll { $0.expiresAt <= now }
        if let id = currentID { store.setScrubReturnPosition(scrubNotches.first?.position, for: id) }
    }
    private func rememberScrub(_ position: Double) {
        expireScrubNotches()
        scrubNotches.removeAll { abs($0.position - position) < 1 }
        scrubNotches.append(ScrubNotch(position: position, expiresAt: Date().addingTimeInterval(30)))
        if let id = currentID { store.setScrubReturnPosition(scrubNotches.first?.position, for: id) }
        notchTask?.cancel()
        notchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let next = self.scrubNotches.map(\.expiresAt).min() else { return }
                do { try await Task.sleep(for: .seconds(max(0.01, next.timeIntervalSinceNow))) } catch { return }
                self.expireScrubNotches()
            }
        }
    }
    private var sleepTask: Task<Void, Never>?

    var sleepActive: Bool { sleepRemaining > 0 }

    func setSleepTimer(seconds: Double) {
        cancelSleepTimer()
        guard seconds.isFinite, seconds > 0, seconds <= 86_400 else { return }
        sleepRemaining = seconds
        syncSleepCountdown()
        publishWidget()
    }
    private func pauseSleepCountdown() {
        if let deadline = sleepDeadline { sleepRemaining = max(0, deadline.timeIntervalSinceNow) }
        sleepDeadline = nil
        sleepTask?.cancel(); sleepTask = nil
    }
    private func syncSleepCountdown() {
        guard playing, wantsPlayback else { pauseSleepCountdown(); return }
        guard sleepActive, sleepDeadline == nil else { return }
        sleepDeadline = Date().addingTimeInterval(sleepRemaining)
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let deadline = self.sleepDeadline else { return }
                guard self.playing, self.wantsPlayback else { self.pauseSleepCountdown(); self.publishWidget(); return }
                let remaining = max(0, deadline.timeIntervalSinceNow)
                self.sleepRemaining = remaining
                if remaining <= 0 { self.expireSleepTimer(); return }
                do { try await Task.sleep(for: .seconds(min(1, remaining))) }
                catch { return }
            }
        }
    }
    func cancelSleepTimer() {
        pauseSleepCountdown()
        sleepRemaining = 0
        publishWidget()
    }
    private func expireSleepTimer() {
        pause()
        cancelSleepTimer()
    }


    init(store: LibraryStore) {
        self.store = store
        playbackStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let isPlaying = player.timeControlStatus == .playing
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.listeningDwell.setPlaying(isPlaying && self.wantsPlayback && !self.restoring)
                self.playing = isPlaying
                self.syncSleepCountdown()
                if !self.restoring { self.loading = waiting }
                self.updateNowPlaying()
            }
        }
        clock = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, event.object as? AVPlayerItem === self.player.currentItem else { return }
                self.wantsPlayback = false; self.playing = false; self.syncSleepCountdown()
                if let id = self.currentID { self.store.setPosition(0, for: id) }
                self.updateNowPlaying()
                if let next = self.store.takeNextQueued() { self.load(next, autoplay: true) }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] event in
            let type = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = event.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.interruptedPlayback = self.wantsPlayback; self.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue,
                          AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume), self.interruptedPlayback {
                    self.interruptedPlayback = false; self.play()
                }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] event in
            let reason = event.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pause() }
            }
        })
        configureRemoteCommands()
    }

    var current: Recording? { store.entry(currentID) }

    func restoreLast() { if currentID == nil, let entry = store.entry(store.data.lastID) { load(entry, autoplay: false) } }

    func load(_ entry: Recording, autoplay: Bool = false, refresh: Bool = false) {
        pauseSleepCountdown()
        listeningDwell.reset()
        clearScrubReturn()
        savePosition(); player.pause(); loadTask?.cancel()
        status = nil; player.replaceCurrentItem(with: nil)
        generation = UUID(); let token = generation
        currentID = entry.id; store.select(entry.id)
        source = nil; position = entry.position; duration = 0
        pendingWidgetSkip = nil
        wantsPlayback = autoplay; loading = true; restoring = true; playing = false; message = nil; lastSaved = -1
        loadTask = Task {
            do {
                let result: ResolvedAudio
                if let local = entry.localFilename {
                    let url = store.audioDirectory.appendingPathComponent(local)
                    guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
                    result = ResolvedAudio(source: url, title: entry.title, show: entry.show)
                } else if let cached = entry.source, !refresh, !entry.isFeed {
                    result = ResolvedAudio(source: cached, title: entry.title, show: entry.show)
                } else { result = try await AudioResolver().resolve(entry.url) }
                guard !Task.isCancelled, generation == token, store.entry(entry.id) != nil else { return }
                var selected = entry
                if entry.localFilename == nil, let saved = store.apply(result, to: entry.id) {
                    selected = saved
                    currentID = saved.id
                    position = saved.position
                }
                if !result.episodes.isEmpty {
                    for episode in result.episodes {
                        let saved = try store.remember(episode.source.absoluteString, notifyDuplicate: false)
                        store.apply(ResolvedAudio(source: episode.source, title: episode.title, show: episode.show), to: saved.id)
                    }
                    loading = false; restoring = false; wantsPlayback = false; currentID = nil
                    message = "Feed saved. Choose an episode in your archive."
                    return
                }
                guard let src = result.source else { throw AudioResolver.Failure.noAudio }
                source = src; store.select(selected.id)
                prepare(src, resume: selected.position, token: token)
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                loading = false; restoring = false; wantsPlayback = false
                message = "error"
            }
        }
    }

    private func prepare(_ url: URL, resume: Double, token: UUID) {
        restoring = true; loading = true
        let item = AVPlayerItem(url: url)
        status = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.loading = false; self.restoring = false; self.wantsPlayback = false
                    self.message = "error"
                } else if item.status == .readyToPlay {
                    self.status = nil
                    if let id = self.currentID, let entry = self.store.entry(id) {
                        Task { [weak self] in
                            let metadata = await AudioResolver.metadata(item.asset, fallback: entry.title, folders: self?.store.data.folders ?? [])
                            guard let self, self.generation == token, self.currentID == id,
                                  metadata.title != nil || metadata.show != nil else { return }
                            self.store.apply(ResolvedAudio(source: entry.source ?? url, title: metadata.title ?? entry.title, show: metadata.show ?? entry.show), to: id)
                            self.updateNowPlaying()
                        }
                    }
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : 0
                    if let id = self.currentID { self.store.setDuration(self.duration, for: id) }
                    let target = self.duration > 0 ? min(resume, max(0, self.duration - 0.1)) : resume
                    self.player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == token else { return }
                            self.restoring = false; self.loading = false
                            if completed { self.position = target }
                            else { self.message = "error" }
                            if let offset = self.pendingWidgetSkip { self.pendingWidgetSkip = nil; self.skip(offset) }
                            if self.wantsPlayback { self.play() }
                            self.updateNowPlaying()
                        }
                    }
                }
            }
        }
        player.replaceCurrentItem(with: item)
        updateNowPlaying()
    }

    func toggle() { if wantsPlayback { pause() } else { play() } }
    func play() {
        guard let entry = current else { return }
        message = nil
        if player.currentItem == nil || player.currentItem?.status == .failed {
            load(entry, autoplay: true, refresh: true); return
        }
        wantsPlayback = true
        guard !restoring else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            if duration > 0 && position >= duration - 0.2 { seek(0) }
            player.play()
        } catch { wantsPlayback = false; message = "error" }
    }
    func pause() { listeningDwell.setPlaying(false); wantsPlayback = false; pauseSleepCountdown(); player.pause(); savePosition(); updateNowPlaying() }
    func stop() {
        listeningDwell.reset()
        clearScrubReturn()
        cancelSleepTimer()
        savePosition(); loadTask?.cancel(); generation = UUID(); status = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        currentID = nil; position = 0; duration = 0; playing = false; loading = false; restoring = false; wantsPlayback = false
        pendingWidgetSkip = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        publishWidget()
    }
    func reset() {
        stop()
        source = nil; message = nil; interruptedPlayback = false
        store.select(nil)
    }
    func seek(_ seconds: Double, rememberPrevious: Bool = true) {
        guard !loading, duration > 0 else { return }
        let target = max(0, min(duration, seconds)); let token = generation
        let request = UUID(); seekGeneration = request
        listeningDwell.setPlaying(false)
        if let id = currentID {
            if rememberPrevious && listeningDwell.eligible && abs(target - position) >= 1 { rememberScrub(position) }
            // Persist the intended destination before an asynchronous seek can be interrupted.
            store.setPosition(target, for: id)
        }
        listeningDwell.reset()
        restoring = true; position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.seekGeneration == request else { return }
                self.restoring = false
                self.listeningDwell.setPlaying(self.player.timeControlStatus == .playing && self.wantsPlayback)
                self.savePosition(); self.updateNowPlaying()
            }
        }
    }
    func returnToSavedPosition(_ position: Double? = nil) {
        guard !loading, duration > 0, let saved = position ?? visibleScrubReturnPosition else { return }
        seek(saved, rememberPrevious: false)
        scrubNotches.removeAll { abs($0.position - saved) < 1 }
        if let id = currentID { store.setScrubReturnPosition(scrubNotches.first?.position, for: id) }
    }
    func skip(_ seconds: Double) { seek(position + seconds, rememberPrevious: false) }
    func savePosition() {
        guard !restoring, let id = currentID, player.currentItem?.status == .readyToPlay else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite { store.setPosition(duration > 0 && seconds >= duration - 0.1 ? 0 : seconds, for: id); lastSaved = seconds }
    }
    private func tick() {
        if let deadline = sleepDeadline {
            sleepRemaining = max(0, deadline.timeIntervalSinceNow)
            if sleepRemaining <= 0 { expireSleepTimer() }
        }
        guard !restoring, currentID != nil else { return }
        let time = player.currentTime().seconds
        if time.isFinite { position = max(0, time) }
        if let d = player.currentItem?.duration.seconds, d.isFinite {
            duration = d
            if let id = currentID { store.setDuration(d, for: id) }
        }
        if abs(position - lastSaved) >= 5 { savePosition() }
        updateNowPlaying()
    }
    func handleWidgetAction(_ action: String) {
        switch action {
        case "toggle": restoreLast(); toggle()
        case "back", "forward":
            restoreLast()
            let offset: Double = action == "back" ? -15 : 15
            if loading { pendingWidgetSkip = offset }
            else { skip(offset) }
        case "sleep-options": widgetSleepChoosing.toggle(); publishWidget()
        case "sleep-5", "sleep-15", "sleep-30":
            widgetSleepChoosing = false
            let minutes = Double(action.replacingOccurrences(of: "sleep-", with: "")) ?? 5
            setSleepTimer(seconds: minutes * 60)
        case "sleep-cancel": widgetSleepChoosing = false; cancelSleepTimer()
        case "reset": reset()
        default: restoreLast()
        }
    }
    private var pendingWidgetSkip: Double?
    var widgetDecorations: (() -> WidgetDecorations)?
    func publishWidget() {
        WidgetBridge.publish(WidgetSnapshot(title: current?.title ?? "earmark", folder: current.map { $0.folder ?? "inbox" } ?? "",
            position: position, duration: duration > 0 ? duration : (current?.duration ?? 0), playing: playing, loaded: currentID != nil,
            dark: UserDefaults.standard.object(forKey: "darkMode") as? Bool ?? true, updated: Date(), sleepDeadline: sleepDeadline, sleepRemaining: sleepRemaining, sleepChoosing: widgetSleepChoosing, decorations: widgetDecorations?() ?? .empty))
    }
    func updateNowPlaying() {
        publishWidget()
        guard let entry = current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: entry.title,
                                  MPMediaItemPropertyArtist: entry.show,
                                  MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
                                  MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-15) }; return .success }
        commands.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(15) }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.seek(time) }; return .success
        }
    }
}
