import Foundation
import CLibMPV

// MARK: - Event Types

public enum MPVEvent: Sendable {
    case fileLoaded
    case endFile(reason: EndFileReason)
    case propertyChanged(MPVPropertyChange)
    case videoReconfig
    case audioReconfig
    case seek
    case playbackRestarted
    case idle
    case shutdown
}

public enum EndFileReason: Sendable {
    case eof
    case stop
    case quit
    case error(String)
    case redirect
}

public struct MPVPropertyChange: Sendable {
    public let name: String
    public let value: MPVPropertyValue
}

public enum MPVPropertyValue: Sendable {
    case bool(Bool)
    case double(Double)
    case int64(Int64)
    case string(String)
    case node // complex node — parse as needed
    case none
}

// MARK: - Errors

public enum MPVClientError: Error, Sendable {
    case initializationFailed
    case commandFailed(String)
    case propertyReadFailed(String)
    case propertyWriteFailed(String)
    case fileNotFound(URL)
}

// MARK: - MPVClient

/// Thread-safe client wrapping a single `mpv_handle`.
///
/// All mpv API calls (commands, property reads/writes) are serialized on
/// an internal dispatch queue. Events from mpv are delivered via `events`
/// AsyncStream, which can be consumed from any Swift concurrency context.
///
/// Usage:
/// ```swift
/// let client = try MPVClient()
/// for await event in client.events {
///     switch event {
///     case .fileLoaded: ...
///     }
/// }
/// await client.loadFile(url)
/// ```
public final class MPVClient: @unchecked Sendable {

    // MARK: Internals

    /// Internal state that must be accessed on `queue`
    private final class State: @unchecked Sendable {
        var handle: OpaquePointer?
        var continuation: AsyncStream<MPVEvent>.Continuation?

        init() {}
    }

    private let queue = DispatchQueue(
        label: "dev.flux.mpvclient",
        qos: .userInteractive
    )
    private let state = State()

    public let events: AsyncStream<MPVEvent>

    // MARK: Init

    public init() throws {
        var cont: AsyncStream<MPVEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(128)) { cont = $0 }

        try queue.sync {
            guard let handle = mpv_create() else {
                throw MPVClientError.initializationFailed
            }

            self.state.handle = handle
            self.state.continuation = cont

            // Configure options before mpv_initialize
            mpv_set_option_string(handle, "vo", "libmpv")
            mpv_set_option_string(handle, "hwdec", "auto")
            mpv_set_option_string(handle, "gpu-api", "opengl")
            mpv_set_option_string(handle, "sub-auto", "fuzzy")
            mpv_set_option_string(handle, "alang", "und,en,eng")
            mpv_set_option_string(handle, "slang", "und,en,eng")
            mpv_set_option_string(handle, "keep-open", "yes")
            mpv_set_option_string(handle, "idle", "yes")
            mpv_set_option_string(handle, "input-default-bindings", "no")
            mpv_set_option_string(handle, "input-vo-keyboard", "no")
            mpv_set_option_string(handle, "osc", "no")

            guard mpv_initialize(handle) == MPV_ERROR_SUCCESS else {
                mpv_destroy(handle)
                self.state.handle = nil
                throw MPVClientError.initializationFailed
            }

            // Observe properties for UI state binding
            mpv_observe_property(handle, 1, "time-pos", MPV_FORMAT_DOUBLE)
            mpv_observe_property(handle, 2, "duration", MPV_FORMAT_DOUBLE)
            mpv_observe_property(handle, 3, "pause", MPV_FORMAT_FLAG)
            mpv_observe_property(handle, 4, "volume", MPV_FORMAT_DOUBLE)
            mpv_observe_property(handle, 5, "mute", MPV_FORMAT_FLAG)
            mpv_observe_property(handle, 6, "track-list", MPV_FORMAT_NODE)
            mpv_observe_property(handle, 7, "chapter-list", MPV_FORMAT_NODE)
            mpv_observe_property(handle, 8, "chapter", MPV_FORMAT_INT64)
            mpv_observe_property(handle, 9, "hwdec-current", MPV_FORMAT_STRING)
            mpv_observe_property(handle, 10, "video-format", MPV_FORMAT_STRING)
            mpv_observe_property(handle, 11, "video-codec", MPV_FORMAT_STRING)
            mpv_observe_property(handle, 12, "audio-codec-name", MPV_FORMAT_STRING)
            mpv_observe_property(handle, 13, "current-tracks/video/image", MPV_FORMAT_FLAG)

            // Wakeup callback: called from any thread when events are ready.
            // We process events on our queue to avoid blocking mpv's internals.
            let rawSelf = Unmanaged.passUnretained(self).toOpaque()
            mpv_set_wakeup_callback(handle, { rawPtr in
                guard let ptr = rawPtr else { return }
                let client = Unmanaged<MPVClient>.fromOpaque(ptr).takeUnretainedValue()
                client.drainEvents()
            }, rawSelf)
        }
    }

    deinit {
        queue.sync {
            state.continuation?.finish()
            if let handle = state.handle {
                mpv_terminate_destroy(handle)
                state.handle = nil
            }
        }
    }

    // MARK: Playback Commands

    public func loadFile(_ url: URL, startTime: Double? = nil) {
        var args = [url.isFileURL ? url.path : url.absoluteString]
        if let t = startTime {
            args.append("replace")
            args.append("start=\(t)")
        }
        command("loadfile", args: args)
    }

    public func play() {
        setProperty("pause", value: false)
    }

    public func pause() {
        setProperty("pause", value: true)
    }

    public func togglePlayPause() {
        command("cycle", args: ["pause"])
    }

    public func seek(to time: Double, precise: Bool = true) {
        let mode = precise ? "absolute+exact" : "absolute"
        command("seek", args: [String(time), mode])
    }

    public func seekRelative(_ delta: Double) {
        command("seek", args: [String(delta), "relative"])
    }

    public func stop() {
        command("stop")
    }

    public func nextChapter() {
        command("add", args: ["chapter", "1"])
    }

    public func previousChapter() {
        command("add", args: ["chapter", "-1"])
    }

    // MARK: Audio / Subtitle Tracks

    public func setAudioTrack(_ id: Int) {
        setProperty("aid", intValue: id)
    }

    public func setSubtitleTrack(_ id: Int) {
        setProperty("sid", intValue: id)
    }

    public func disableSubtitles() {
        setProperty("sid", value: "no")
    }

    public func setSubtitleDelay(_ delay: Double) {
        setProperty("sub-delay", doubleValue: delay)
    }

    public func setVolume(_ volume: Double) {
        setProperty("volume", doubleValue: max(0, min(200, volume)))
    }

    public func setMute(_ muted: Bool) {
        setProperty("mute", value: muted)
    }

    public func loadExternalSubtitle(_ url: URL) {
        command("sub-add", args: [url.path, "select"])
    }

    // MARK: Property Access (sync, called on queue)

    public func getDouble(_ property: String) -> Double? {
        queue.sync {
            guard let handle = state.handle else { return nil }
            var value = 0.0
            guard mpv_get_property(handle, property, MPV_FORMAT_DOUBLE, &value) == MPV_ERROR_SUCCESS else {
                return nil
            }
            return value
        }
    }

    public func getString(_ property: String) -> String? {
        queue.sync {
            guard let handle = state.handle else { return nil }
            guard let cstr = mpv_get_property_string(handle, property) else { return nil }
            defer { mpv_free(cstr) }
            return String(cString: cstr)
        }
    }

    // MARK: Render Context

    /// Creates and returns an mpv render context for Metal rendering.
    /// Must be called after `mpv_initialize`.
    public func createRenderContext(
        updateCallback: @escaping @Sendable () -> Void
    ) -> OpaquePointer? {
        queue.sync {
            guard let handle = state.handle else { return nil }

            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: MPV_RENDER_API_TYPE_SW)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]

            var ctx: OpaquePointer?
            let result = mpv_render_context_create(&ctx, handle, &params)
            guard result == MPV_ERROR_SUCCESS, let ctx else { return nil }

            let block = updateCallback as AnyObject
            let rawBlock = Unmanaged.passRetained(block).toOpaque()

            mpv_render_context_set_update_callback(ctx, { rawPtr in
                guard let ptr = rawPtr else { return }
                let block = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
                if let callback = block as? (() -> Void) {
                    callback()
                }
            }, rawBlock)

            return ctx
        }
    }

    // MARK: Private Helpers

    private func command(_ name: String, args: [String] = []) {
        queue.async { [weak self] in
            guard let self, let handle = self.state.handle else { return }
            var cArgs: [UnsafePointer<CChar>?] = [name].map { $0.withCString { strdup($0) } }
            args.forEach { cArgs.append($0.withCString { strdup($0) }) }
            cArgs.append(nil)
            mpv_command(handle, &cArgs)
            cArgs.forEach { if let p = $0 { free(UnsafeMutableRawPointer(mutating: p)) } }
        }
    }

    private func setProperty(_ name: String, value: Bool) {
        queue.async { [weak self] in
            guard let handle = self?.state.handle else { return }
            var v: Int32 = value ? 1 : 0
            mpv_set_property(handle, name, MPV_FORMAT_FLAG, &v)
        }
    }

    private func setProperty(_ name: String, value: String) {
        queue.async { [weak self] in
            guard let handle = self?.state.handle else { return }
            var v = value
            v.withUTF8 { ptr in
                _ = ptr.baseAddress.map {
                    mpv_set_property_string(handle, name, UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
                }
            }
        }
    }

    private func setProperty(_ name: String, doubleValue: Double) {
        queue.async { [weak self] in
            guard let handle = self?.state.handle else { return }
            var v = doubleValue
            mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &v)
        }
    }

    private func setProperty(_ name: String, intValue: Int) {
        queue.async { [weak self] in
            guard let handle = self?.state.handle else { return }
            var v = Int64(intValue)
            mpv_set_property(handle, name, MPV_FORMAT_INT64, &v)
        }
    }

    private func drainEvents() {
        queue.async { [weak self] in
            guard let self, let handle = self.state.handle else { return }
            while true {
                let event = mpv_wait_event(handle, 0)
                guard let event else { break }
                if event.pointee.event_id == MPV_EVENT_NONE { break }
                self.processEvent(event.pointee)
            }
        }
    }

    private func processEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            state.continuation?.yield(.fileLoaded)

        case MPV_EVENT_END_FILE:
            if let data = event.data?.bindMemory(to: mpv_event_end_file.self, capacity: 1) {
                let reason = endFileReason(from: data.pointee)
                state.continuation?.yield(.endFile(reason: reason))
            }

        case MPV_EVENT_PROPERTY_CHANGE:
            if let data = event.data?.bindMemory(to: mpv_event_property.self, capacity: 1) {
                let change = propertyChange(from: data.pointee)
                state.continuation?.yield(.propertyChanged(change))
            }

        case MPV_EVENT_VIDEO_RECONFIG:
            state.continuation?.yield(.videoReconfig)

        case MPV_EVENT_AUDIO_RECONFIG:
            state.continuation?.yield(.audioReconfig)

        case MPV_EVENT_SEEK:
            state.continuation?.yield(.seek)

        case MPV_EVENT_PLAYBACK_RESTART:
            state.continuation?.yield(.playbackRestarted)

        case MPV_EVENT_IDLE:
            state.continuation?.yield(.idle)

        case MPV_EVENT_SHUTDOWN:
            state.continuation?.yield(.shutdown)
            state.continuation?.finish()

        default:
            break
        }
    }

    private func endFileReason(from data: mpv_event_end_file) -> EndFileReason {
        switch data.reason {
        case MPV_END_FILE_REASON_EOF:    return .eof
        case MPV_END_FILE_REASON_STOP:   return .stop
        case MPV_END_FILE_REASON_QUIT:   return .quit
        case MPV_END_FILE_REASON_REDIRECT: return .redirect
        case MPV_END_FILE_REASON_ERROR:
            let msg = data.error == MPV_ERROR_SUCCESS ? "unknown" : String(cString: mpv_error_string(data.error))
            return .error(msg)
        default:
            return .stop
        }
    }

    private func propertyChange(from prop: mpv_event_property) -> MPVPropertyChange {
        let name = String(cString: prop.name)
        let value: MPVPropertyValue

        switch prop.format {
        case MPV_FORMAT_DOUBLE:
            if let ptr = prop.data?.bindMemory(to: Double.self, capacity: 1) {
                value = .double(ptr.pointee)
            } else {
                value = .none
            }
        case MPV_FORMAT_FLAG:
            if let ptr = prop.data?.bindMemory(to: Int32.self, capacity: 1) {
                value = .bool(ptr.pointee != 0)
            } else {
                value = .none
            }
        case MPV_FORMAT_INT64:
            if let ptr = prop.data?.bindMemory(to: Int64.self, capacity: 1) {
                value = .int64(ptr.pointee)
            } else {
                value = .none
            }
        case MPV_FORMAT_STRING:
            if let ptr = prop.data?.bindMemory(to: UnsafePointer<CChar>.self, capacity: 1),
               let cstr = ptr.pointee {
                value = .string(String(cString: cstr))
            } else {
                value = .none
            }
        case MPV_FORMAT_NODE:
            value = .node
        default:
            value = .none
        }

        return MPVPropertyChange(name: name, value: value)
    }
}
