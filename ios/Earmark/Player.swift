import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentID: UUID?
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var message: String?
    private let store: LibraryStore
    private let player = AVPlayer()
    private var status: NSKeyValueObservation?
    private var playbackStatus: NSKeyValueObservation?
    private var clock: Any?
    private var notifications: [NSObjectProtocol] = []
    private var loadTask: Task<Void, Never>?
    private var generation = UUID()
    private var restoring = false
    private var wantsPlayback = false
    private var interruptedPlayback = false
    private var lastSaved: Double = -1
    private var source: URL?
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var sleepRemaining: Double = 0
    @Published private(set) var scrubReturnDeadline: Date?
    private var scrubReturnTask: Task<Void, Never>?
    var visibleScrubReturnPosition: Double? {
        guard let deadline = scrubReturnDeadline, deadline > Date() else { return nil }
        return current?.scrubReturnPosition
    }
    func expireScrubReturnIfNeeded(now: Date = Date()) {
        guard let deadline = scrubReturnDeadline, now >= deadline else { return }
        clearScrubReturn()
    }
    private func clearScrubReturn() {
        if let id = currentID { store.setScrubReturnPosition(nil, for: id) }
        scrubReturnDeadline = nil; scrubReturnTask?.cancel(); scrubReturnTask = nil
    }
    private var sleepTask: Task<Void, Never>?

    func setSleepTimer(seconds: Double) {
        cancelSleepTimer()
        guard seconds.isFinite, seconds > 0, seconds <= 86_400 else { return }
        sleepDeadline = Date().addingTimeInterval(seconds)
        sleepRemaining = seconds
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let deadline = self?.sleepDeadline else { return }
                let remaining = max(0, deadline.timeIntervalSinceNow)
                self?.sleepRemaining = remaining
                if remaining <= 0 { self?.expireSleepTimer(); return }
                do { try await Task.sleep(for: .seconds(min(1, remaining))) }
                catch { return }
            }
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel(); sleepTask = nil
        sleepDeadline = nil; sleepRemaining = 0
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
                self.playing = isPlaying
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
                self.wantsPlayback = false; self.playing = false
                if let id = self.currentID { self.store.setPosition(0, for: id) }
                self.updateNowPlaying()
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
        clearScrubReturn()
        savePosition(); player.pause(); loadTask?.cancel()
        status = nil; player.replaceCurrentItem(with: nil)
        generation = UUID(); let token = generation
        currentID = entry.id; store.select(entry.id)
        source = nil; position = entry.position; duration = 0
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
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : 0
                    let target = self.duration > 0 ? min(resume, max(0, self.duration - 0.1)) : resume
                    self.player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == token else { return }
                            self.restoring = false; self.loading = false
                            if completed { self.position = target }
                            else { self.message = "error" }
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
    func pause() { wantsPlayback = false; player.pause(); savePosition(); updateNowPlaying() }
    func stop() {
        clearScrubReturn()
        cancelSleepTimer()
        savePosition(); loadTask?.cancel(); generation = UUID(); status = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        currentID = nil; position = 0; duration = 0; playing = false; loading = false; restoring = false; wantsPlayback = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    func reset() {
        stop()
        source = nil; message = nil; interruptedPlayback = false
        store.select(nil)
    }
    func seek(_ seconds: Double, rememberPrevious: Bool = true) {
        guard !restoring, duration > 0 else { return }
        let target = max(0, min(duration, seconds)); let token = generation
        if let id = currentID {
            expireScrubReturnIfNeeded()
            if rememberPrevious && visibleScrubReturnPosition == nil && abs(target - position) >= 60 {
                store.setScrubReturnPosition(position, for: id)
                scrubReturnDeadline = Date().addingTimeInterval(30)
                scrubReturnTask?.cancel()
                scrubReturnTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.expireScrubReturnIfNeeded()
                }
            }
            // Persist the intended destination before an asynchronous seek can be interrupted.
            store.setPosition(target, for: id)
        }
        restoring = true; position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.restoring = false; self.savePosition(); self.updateNowPlaying()
            }
        }
    }
    func returnToSavedPosition() {
        guard !restoring, duration > 0, let entry = current, let saved = visibleScrubReturnPosition else { return }
        seek(saved, rememberPrevious: false)
        store.setScrubReturnPosition(nil, for: entry.id)
        scrubReturnDeadline = nil; scrubReturnTask?.cancel(); scrubReturnTask = nil
    }
    func skip(_ seconds: Double) { seek(position + seconds) }
    func savePosition() {
        guard !restoring, let id = currentID, player.currentItem?.status == .readyToPlay else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite { store.setPosition(duration > 0 && seconds >= duration - 0.1 ? 0 : seconds, for: id); lastSaved = seconds }
    }
    private func tick() {
        expireScrubReturnIfNeeded()
        if let deadline = sleepDeadline {
            sleepRemaining = max(0, deadline.timeIntervalSinceNow)
            if sleepRemaining <= 0 { expireSleepTimer() }
        }
        guard !restoring, currentID != nil else { return }
        let time = player.currentTime().seconds
        if time.isFinite { position = max(0, time) }
        if let d = player.currentItem?.duration.seconds, d.isFinite { duration = d }
        if abs(position - lastSaved) >= 5 { savePosition() }
        updateNowPlaying()
    }
    func updateNowPlaying() {
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
