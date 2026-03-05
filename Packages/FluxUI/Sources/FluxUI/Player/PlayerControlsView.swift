import SwiftUI
import FluxCore

// MARK: - PlayerControlsView

/// Full playback controls overlay.
/// Shows on hover (macOS) or tap (iOS). Auto-hides after 3 seconds of inactivity.
public struct PlayerControlsView: View {

    // MARK: Properties

    @ObservedObject var session: MediaSession
    @Binding var isVisible: Bool
    var onClose: (() -> Void)?

    @Environment(\.fluxTheme) private var theme
    @State private var isDraggingScrubber = false
    @State private var scrubberValue: Double = 0
    @State private var hideTimer: Timer?

    private var state: PlaybackState { session.state }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            controlsBackground
        }
        .opacity(isVisible ? 1 : 0)
        .animation(theme.animations.standard, value: isVisible)
        .onAppear { resetHideTimer() }
        .onChange(of: isVisible) { _, visible in
            if visible { resetHideTimer() }
        }
    }

    // MARK: Controls Background

    @ViewBuilder
    private var controlsBackground: some View {
        VStack(spacing: 0) {
            // Gradient fade behind controls
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)

            // Controls bar
            VStack(spacing: theme.spacing.md) {
                scrubberRow
                buttonRow
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, theme.spacing.lg)
            .padding(.top, theme.spacing.sm)
            .background(.black.opacity(0.85))
        }
        .onHover { _ in resetHideTimer() }
    }

    // MARK: Scrubber Row

    @ViewBuilder
    private var scrubberRow: some View {
        VStack(spacing: 4) {
            // Chapter-aware scrubber
            ChapterScrubber(
                value: isDraggingScrubber ? scrubberValue : state.progress,
                chapters: state.chapters,
                onEditingChanged: { editing in
                    isDraggingScrubber = editing
                    if !editing {
                        session.seek(to: scrubberValue * state.duration)
                    }
                    resetHideTimer()
                },
                onValueChanged: { scrubberValue = $0 }
            )
            .frame(height: 20)

            HStack {
                Text(formatTime(state.currentTime))
                    .font(theme.typography.playerTime)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer()
                Text("-" + formatTime(state.remainingTime))
                    .font(theme.typography.playerTime)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    // MARK: Button Row

    @ViewBuilder
    private var buttonRow: some View {
        HStack(spacing: 0) {
            // Left: skip back
            ControlButton(systemName: "gobackward.10") {
                session.seekRelative(-10)
                resetHideTimer()
            }

            Spacer()

            // Center: play/pause
            ControlButton(
                systemName: state.isPlaying ? "pause.fill" : "play.fill",
                fontSize: 28
            ) {
                session.togglePlayPause()
                resetHideTimer()
            }

            Spacer()

            // Right: skip forward
            ControlButton(systemName: "goforward.30") {
                session.seekRelative(30)
                resetHideTimer()
            }

            Spacer().frame(width: 24)

            // Volume
            VolumeControl(volume: state.volume, isMuted: state.isMuted) { vol in
                session.setVolume(vol)
                resetHideTimer()
            } onMuteToggle: {
                session.setMute(!state.isMuted)
                resetHideTimer()
            }

            Spacer().frame(width: 24)

            // Audio track picker
            if state.audioTracks.count > 1 {
                TrackPickerButton(
                    systemName: "speaker.wave.2",
                    tracks: state.audioTracks.map { TrackItem(id: $0.id, label: $0.title ?? $0.language ?? "Audio \($0.id)") },
                    selectedID: state.selectedAudioTrack.map { String($0.id) }
                ) { id in
                    if let track = state.audioTracks.first(where: { String($0.id) == id }) {
                        session.selectAudioTrack(track)
                    }
                    resetHideTimer()
                }
            }

            // Subtitle track picker
            TrackPickerButton(
                systemName: "captions.bubble",
                tracks: [TrackItem(id: "off", label: "Off")] + state.subtitleTracks.map {
                    TrackItem(id: String($0.id), label: $0.title ?? $0.language ?? "Sub \($0.id)")
                },
                selectedID: state.selectedSubtitleTrack.map { String($0.id) } ?? "off"
            ) { id in
                if id == "off" {
                    session.disableSubtitles()
                } else if let track = state.subtitleTracks.first(where: { String($0.id) == id }) {
                    session.selectSubtitleTrack(track)
                }
                resetHideTimer()
            }

            Spacer().frame(width: 24)

            // Close / fullscreen
            if let onClose {
                ControlButton(systemName: "xmark") {
                    onClose()
                }
            }
        }
    }

    // MARK: Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(theme.animations.standard) {
                isVisible = false
            }
        }
    }
}

// MARK: - ChapterScrubber

struct ChapterScrubber: View {
    let value: Double
    let chapters: [MediaChapter]
    let onEditingChanged: (Bool) -> Void
    let onValueChanged: (Double) -> Void

    @Environment(\.fluxTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(theme.colors.scrubberTrack)
                    .frame(height: 4)

                // Fill
                Capsule()
                    .fill(theme.colors.scrubberFill)
                    .frame(width: geo.size.width * max(0, min(1, value)), height: 4)

                // Chapter markers
                ForEach(chapters) { chapter in
                    let x = geo.size.width * CGFloat(chapter.time / max(1, value == 0 ? 1 : value))
                    Capsule()
                        .fill(theme.colors.scrubberChapter)
                        .frame(width: 2, height: 8)
                        .offset(x: x - 1)
                }

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(radius: 2)
                    .offset(x: geo.size.width * max(0, min(1, value)) - 7)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let v = max(0, min(1, drag.location.x / geo.size.width))
                        onValueChanged(v)
                        onEditingChanged(true)
                    }
                    .onEnded { _ in
                        onEditingChanged(false)
                    }
            )
        }
    }
}

// MARK: - Supporting Types

struct TrackItem: Identifiable {
    let id: String
    let label: String
}

// MARK: - Control Button

struct ControlButton: View {
    let systemName: String
    var fontSize: CGFloat = 20
    let action: () -> Void

    @Environment(\.fluxTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(isHovered ? theme.colors.accentHover : .white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Volume Control

struct VolumeControl: View {
    let volume: Double
    let isMuted: Bool
    let onVolumeChange: (Double) -> Void
    let onMuteToggle: () -> Void

    @Environment(\.fluxTheme) private var theme
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onMuteToggle) {
                Image(systemName: isMuted || volume == 0 ? "speaker.slash.fill" : volumeIcon)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Slider(value: Binding(
                    get: { volume },
                    set: { onVolumeChange($0) }
                ), in: 0...100)
                .frame(width: 80)
                .tint(theme.colors.accent)
            }
        }
        .onHover { isExpanded = $0 }
    }

    private var volumeIcon: String {
        if volume > 66 { return "speaker.wave.3.fill" }
        if volume > 33 { return "speaker.wave.2.fill" }
        return "speaker.wave.1.fill"
    }
}

// MARK: - Track Picker Button

struct TrackPickerButton: View {
    let systemName: String
    let tracks: [TrackItem]
    let selectedID: String?
    let onSelect: (String) -> Void

    @Environment(\.fluxTheme) private var theme

    var body: some View {
        Menu {
            ForEach(tracks) { track in
                Button(action: { onSelect(track.id) }) {
                    HStack {
                        Text(track.label)
                        if track.id == selectedID {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
    }
}
