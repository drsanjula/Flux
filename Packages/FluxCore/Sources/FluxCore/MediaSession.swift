import Foundation
import Observation
import MediaPlayer

// MARK: - MediaSession

/// Coordinates between MPVClient and the UI layer.
///
/// Owns an MPVClient, drives a PlaybackState, and manages system integration
/// (Now Playing info, Remote Command Center for Control Center / AirPods / lock screen).
///
/// Usage:
/// ```swift
/// @State var session = MediaSession()
/// // In your view:
/// VideoSurfaceView(client: session.client)
/// // Load a file:
/// await session.open(url: fileURL)
/// ```
@Observable
public final class MediaSession: @unchecked Sendable {

    // MARK: Public

    public let client: MPVClient
    public let state: PlaybackState
    public var savedPositions: [URL: Double] = [:]

    // MARK: Private

    private var eventTask: Task<Void, Never>?
    private var positionSaveTimer: Timer?

    // MARK: Init

    public init() throws {
        self.client = try MPVClient()
        self.state  = PlaybackState()
        setupRemoteCommandCenter()
        startEventLoop()
    }

    deinit {
        eventTask?.cancel()
        positionSaveTimer?.invalidate()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(nil)
    }

    // MARK: Playback Control

    public func open(url: URL, startTime: Double? = nil) {
        let resumeTime = startTime ?? savedPositions[url]
        state.currentURL = url
        state.status = .loading
        state.currentTitle = url.deletingPathExtension().lastPathComponent
        client.loadFile(url, startTime: resumeTime)
        startPositionSaveTimer()
    }

    public func play()  { client.play()  }
    public func pause() { client.pause() }

    public func togglePlayPause() {
        if state.isPlaying { client.pause() } else { client.play() }
    }

    public func seek(to time: Double) {
        client.seek(to: time)
    }

    public func seekRelative(_ delta: Double) {
        client.seekRelative(delta)
    }

    public func setVolume(_ volume: Double) {
        state.volume = volume
        client.setVolume(volume)
    }

    public func setMute(_ muted: Bool) {
        state.isMuted = muted
        client.setMute(muted)
    }

    public func selectAudioTrack(_ track: MediaTrack) {
        client.setAudioTrack(track.id)
    }

    public func selectSubtitleTrack(_ track: MediaTrack) {
        client.setSubtitleTrack(track.id)
    }

    public func disableSubtitles() {
        client.disableSubtitles()
    }

    public func loadExternalSubtitle(_ url: URL) {
        client.loadExternalSubtitle(url)
    }

    // MARK: Private — Event Loop

    private func startEventLoop() {
        eventTask = Task.detached(priority: .high) { [weak self] in
            guard let self else { return }
            for await event in self.client.events {
                if Task.isCancelled { break }
                await self.handle(event: event)
            }
        }
    }

    @MainActor
    private func handle(event: MPVEvent) {
        switch event {
        case .fileLoaded:
            state.status = .playing
            state.isPlaying = true
            updateNowPlaying()

        case .endFile(let reason):
            switch reason {
            case .eof:
                saveCurrentPosition(zeroed: true)
                state.status = .ended
                state.isPlaying = false
            case .error(let msg):
                state.status = .error(msg)
                state.isPlaying = false
            default:
                state.status = .idle
                state.isPlaying = false
            }

        case .propertyChanged(let change):
            applyPropertyChange(change)

        case .videoReconfig:
            break  // Could reload track list here

        case .audioReconfig:
            break

        case .seek:
            updateNowPlaying()

        case .playbackRestarted:
            state.status = state.isPlaying ? .playing : .paused

        case .idle:
            state.status = .idle

        case .shutdown:
            state.status = .idle
            state.isPlaying = false
        }
    }

    @MainActor
    private func applyPropertyChange(_ change: MPVPropertyChange) {
        switch change.name {
        case "time-pos":
            if case .double(let t) = change.value, t >= 0 {
                state.currentTime = t
                updateNowPlayingPosition()
            }
        case "duration":
            if case .double(let d) = change.value, d > 0 {
                state.duration = d
            }
        case "pause":
            if case .bool(let paused) = change.value {
                state.isPlaying = !paused
                state.status = paused ? .paused : .playing
                updateNowPlaying()
            }
        case "volume":
            if case .double(let v) = change.value { state.volume = v }
        case "mute":
            if case .bool(let m) = change.value { state.isMuted = m }
        case "chapter":
            if case .int64(let c) = change.value { state.currentChapter = Int(c) }
        case "hwdec-current":
            if case .string(let s) = change.value {
                state.videoInfo = VideoInfo(
                    codec: state.videoInfo?.codec,
                    hwDecoder: s.isEmpty || s == "no" ? nil : s,
                    isHDR: state.videoInfo?.isHDR ?? false,
                    isDolbyVision: state.videoInfo?.isDolbyVision ?? false,
                    dvProfile: state.videoInfo?.dvProfile
                )
            }
        case "video-codec":
            if case .string(let s) = change.value {
                state.videoInfo = VideoInfo(
                    codec: s,
                    hwDecoder: state.videoInfo?.hwDecoder,
                    isHDR: state.videoInfo?.isHDR ?? false,
                    isDolbyVision: state.videoInfo?.isDolbyVision ?? false,
                    dvProfile: state.videoInfo?.dvProfile
                )
            }
        case "track-list":
            // Re-query track list — mpv_node is complex to parse from Swift
            // In full implementation, parse the node or use a separate property query
            break
        case "chapter-list":
            break
        default:
            break
        }
    }

    // MARK: Private — Position Persistence

    private func startPositionSaveTimer() {
        positionSaveTimer?.invalidate()
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.saveCurrentPosition(zeroed: false)
        }
    }

    private func saveCurrentPosition(zeroed: Bool) {
        guard let url = state.currentURL else { return }
        let pos = zeroed ? 0.0 : state.currentTime
        // Only save if we've played > 30s and not within last 30s of end
        if !zeroed && pos > 30 && (state.duration <= 0 || pos < state.duration - 30) {
            savedPositions[url] = pos
        } else {
            savedPositions.removeValue(forKey: url)
        }
    }

    // MARK: Private — Now Playing / Remote Commands

    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            self?.client.play()
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.client.pause()
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        cc.skipForwardCommand.preferredIntervals = [30]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            self?.client.seekRelative(30)
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [10]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            self?.client.seekRelative(-10)
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.client.seek(to: e.positionTime)
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.currentTitle ?? "Flux",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
        ]
        if let title = state.currentTitle {
            info[MPMediaItemPropertyTitle] = title
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPosition() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = state.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = state.isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
