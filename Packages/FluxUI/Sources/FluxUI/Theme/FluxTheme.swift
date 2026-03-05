import SwiftUI

// MARK: - FluxTheme

/// Design system for Flux. Dark-mode-first.
/// Inject via `.environment(\.fluxTheme, FluxTheme())`.
public struct FluxTheme: Sendable {

    // MARK: Colors

    public struct Colors: Sendable {
        // Backgrounds
        public let backgroundPrimary   = Color(white: 0.07)   // near-black app bg
        public let backgroundSecondary = Color(white: 0.11)   // sidebar, cards
        public let backgroundElevated  = Color(white: 0.15)   // modals, sheets
        public let backgroundHover     = Color(white: 0.18)

        // Surfaces
        public let surfaceCard         = Color(white: 0.13)
        public let surfaceCardHover    = Color(white: 0.19)

        // Text
        public let textPrimary         = Color.white
        public let textSecondary       = Color(white: 0.65)
        public let textTertiary        = Color(white: 0.45)
        public let textDisabled        = Color(white: 0.30)

        // Accent — Flux blue
        public let accent              = Color(red: 0.10, green: 0.52, blue: 1.00)
        public let accentHover         = Color(red: 0.25, green: 0.62, blue: 1.00)
        public let accentPressed       = Color(red: 0.05, green: 0.42, blue: 0.90)

        // Semantic
        public let success             = Color(red: 0.20, green: 0.78, blue: 0.35)
        public let warning             = Color(red: 1.00, green: 0.75, blue: 0.00)
        public let error               = Color(red: 1.00, green: 0.27, blue: 0.23)

        // Badges
        public let hdrBadge            = Color(red: 1.00, green: 0.72, blue: 0.00)  // gold
        public let dolbyVisionBadge    = Color(red: 0.40, green: 0.20, blue: 0.80)  // purple
        public let watchedOverlay      = Color.black.opacity(0.45)

        // Scrubber
        public let scrubberFill        = Color.white
        public let scrubberTrack       = Color(white: 0.30)
        public let scrubberChapter     = Color(white: 0.55)
    }

    // MARK: Typography

    public struct Typography: Sendable {
        // Library
        public let posterTitle    = Font.system(size: 13, weight: .medium)
        public let posterSubtitle = Font.system(size: 11, weight: .regular)
        public let posterBadge    = Font.system(size: 10, weight: .semibold)

        // Navigation
        public let sidebarItem    = Font.system(size: 13, weight: .regular)
        public let sidebarHeader  = Font.system(size: 11, weight: .semibold)

        // Detail view
        public let detailTitle    = Font.system(size: 24, weight: .bold)
        public let detailSubtitle = Font.system(size: 15, weight: .regular)
        public let detailBody     = Font.system(size: 14, weight: .regular)
        public let detailCaption  = Font.system(size: 12, weight: .regular)

        // Player
        public let playerTime     = Font.system(size: 13, weight: .medium).monospacedDigit()
        public let playerTitle    = Font.system(size: 14, weight: .semibold)
    }

    // MARK: Spacing

    public struct Spacing: Sendable {
        public let xs:  CGFloat = 4
        public let sm:  CGFloat = 8
        public let md:  CGFloat = 12
        public let lg:  CGFloat = 16
        public let xl:  CGFloat = 24
        public let xxl: CGFloat = 32

        // Grid
        public let posterSpacing: CGFloat = 12
        public let posterCornerRadius: CGFloat = 8
        public let cardCornerRadius: CGFloat = 10
    }

    // MARK: Sizing

    public struct Sizing: Sendable {
        public let posterMinWidth:  CGFloat = 140
        public let posterMaxWidth:  CGFloat = 220
        public let posterAspect:    CGFloat = 2.0 / 3.0   // 2:3 portrait

        public let backdropAspect:  CGFloat = 16.0 / 9.0

        public let sidebarWidth:    CGFloat = 200
        public let playerBarHeight: CGFloat = 72
        public let controlsHeight:  CGFloat = 56
    }

    // MARK: Animation

    public struct Animations: Sendable {
        public let standard   = Animation.easeInOut(duration: 0.2)
        public let slow       = Animation.easeInOut(duration: 0.35)
        public let spring     = Animation.spring(response: 0.3, dampingFraction: 0.75)
        public let hover      = Animation.easeInOut(duration: 0.12)
    }

    // MARK: Instances

    public let colors     = Colors()
    public let typography = Typography()
    public let spacing    = Spacing()
    public let sizing     = Sizing()
    public let animations = Animations()

    public init() {}
}

// MARK: - Environment Key

public struct FluxThemeKey: EnvironmentKey {
    public static let defaultValue = FluxTheme()
}

extension EnvironmentValues {
    public var fluxTheme: FluxTheme {
        get { self[FluxThemeKey.self] }
        set { self[FluxThemeKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies the Flux design system to a view tree.
    public func fluxStyle() -> some View {
        self
            .environment(\.fluxTheme, FluxTheme())
            .preferredColorScheme(.dark)
    }
}
