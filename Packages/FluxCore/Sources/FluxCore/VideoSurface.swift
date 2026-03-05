#if canImport(AppKit)
import AppKit
import Metal
import QuartzCore
import SwiftUI

// MARK: - VideoSurface (macOS)

/// NSView backed by CAMetalLayer. Hosts the mpv render context.
/// Bridge to SwiftUI via NSViewRepresentable.
///
/// This is the only non-SwiftUI view in Flux.
public final class VideoSurface: NSView {

    // MARK: Properties

    public var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }
    private var renderContext: MPVRenderContext?
    private(set) var client: MPVClient?

    // MARK: Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: Setup

    private func setup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // Create Metal layer
        let metalLayer = CAMetalLayer()
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor.black
        metalLayer.displaySyncEnabled = true  // sync to display refresh rate

        layer = metalLayer
    }

    public override func makeBackingLayer() -> CALayer {
        let ml = CAMetalLayer()
        ml.device = MTLCreateSystemDefaultDevice()
        ml.pixelFormat = .bgra8Unorm
        ml.isOpaque = true
        ml.backgroundColor = CGColor.black
        return ml
    }

    // MARK: MPV Attachment

    public func attach(client: MPVClient) {
        self.client = client
        guard let metalLayer else { return }
        renderContext = MPVRenderContext(client: client, layer: metalLayer)
        renderContext?.start()
    }

    public func detach() {
        renderContext?.stop()
        renderContext = nil
        client = nil
    }

    // MARK: Layout

    public override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer?.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }

    // MARK: View Properties

    public override var isOpaque: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - SwiftUI Bridge

/// SwiftUI view wrapping VideoSurface for macOS.
public struct VideoSurfaceView: NSViewRepresentable {
    public let client: MPVClient

    public init(client: MPVClient) {
        self.client = client
    }

    public func makeNSView(context: Context) -> VideoSurface {
        let surface = VideoSurface()
        surface.attach(client: client)
        return surface
    }

    public func updateNSView(_ nsView: VideoSurface, context: Context) {
        // Client doesn't change after creation
    }

    public static func dismantleNSView(_ nsView: VideoSurface, coordinator: ()) {
        nsView.detach()
    }
}

#elseif canImport(UIKit)
import UIKit
import Metal
import QuartzCore
import SwiftUI

// MARK: - VideoSurface (iOS/tvOS)

public final class VideoSurface: UIView {

    public var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }
    private var renderContext: MPVRenderContext?

    public override class var layerClass: AnyClass { CAMetalLayer.self }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor.black
    }

    public func attach(client: MPVClient) {
        guard let metalLayer else { return }
        renderContext = MPVRenderContext(client: client, layer: metalLayer)
        renderContext?.start()
    }

    public func detach() {
        renderContext?.stop()
        renderContext = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer?.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }
}

public struct VideoSurfaceView: UIViewRepresentable {
    public let client: MPVClient

    public init(client: MPVClient) {
        self.client = client
    }

    public func makeUIView(context: Context) -> VideoSurface {
        let surface = VideoSurface()
        surface.attach(client: client)
        return surface
    }

    public func updateUIView(_ uiView: VideoSurface, context: Context) {}

    public static func dismantleUIView(_ uiView: VideoSurface, coordinator: ()) {
        uiView.detach()
    }
}

#endif
