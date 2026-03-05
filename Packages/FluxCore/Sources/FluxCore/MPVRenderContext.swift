import Foundation
import Metal
import QuartzCore
import CLibMPV

// MARK: - MPVRenderContext

/// Manages the libmpv render context for Metal-based rendering.
///
/// mpv renders frames into an IOSurface which is then displayed via a CAMetalLayer.
/// Frame updates are driven by CADisplayLink for correct frame pacing.
///
/// Usage:
/// ```swift
/// let renderCtx = MPVRenderContext(client: mpvClient, layer: metalLayer)
/// renderCtx.start()
/// ```
public final class MPVRenderContext: @unchecked Sendable {

    // MARK: Properties

    private let client: MPVClient
    private weak var layer: CAMetalLayer?
    private var renderContext: OpaquePointer?
    private var displayLink: CADisplayLink?

    private let renderQueue = DispatchQueue(
        label: "dev.flux.render",
        qos: .userInteractive
    )

    private var needsRender = false
    private let lock = NSLock()

    // MARK: Init

    public init(client: MPVClient, layer: CAMetalLayer) {
        self.client = client
        self.layer = layer
        setupRenderContext()
    }

    deinit {
        stop()
        if let ctx = renderContext {
            mpv_render_context_free(ctx)
        }
    }

    // MARK: Lifecycle

    public func start() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: Private

    private func setupRenderContext() {
        guard let layer else { return }

        // Use software render API as the base — Metal surface provided via IOSurface
        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                             data: UnsafeMutableRawPointer(mutating: MPV_RENDER_API_TYPE_SW)),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]

        var ctx: OpaquePointer?
        // Note: For full Metal render, use MPV_RENDER_API_TYPE_OPENGL with a Metal-backed
        // context. The SW path is used here for simplicity in the initial implementation.
        // See mpv's render_gl.h for the OpenGL + Metal interop path.
        guard mpv_render_context_create(&ctx, nil, &params) == MPV_ERROR_SUCCESS,
              let ctx else {
            return
        }
        self.renderContext = ctx

        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(ctx, { rawPtr in
            guard let ptr = rawPtr else { return }
            let renderCtx = Unmanaged<MPVRenderContext>.fromOpaque(ptr).takeUnretainedValue()
            renderCtx.flagNeedsRender()
        }, rawSelf)

        _ = layer // suppress unused warning — layer is used in render
    }

    private func flagNeedsRender() {
        lock.lock()
        needsRender = true
        lock.unlock()
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        lock.lock()
        let should = needsRender
        needsRender = false
        lock.unlock()

        guard should, let ctx = renderContext, let layer else { return }

        renderQueue.async {
            self.renderFrame(ctx: ctx, layer: layer)
        }
    }

    private func renderFrame(ctx: OpaquePointer, layer: CAMetalLayer) {
        let size = layer.drawableSize
        let width  = Int32(size.width)
        let height = Int32(size.height)

        // Allocate a pixel buffer for SW render
        let bytesPerRow = width * 4
        let bufferSize  = Int(bytesPerRow * height)
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        buffer.withUnsafeMutableBytes { rawPtr in
            var stride = Int32(bytesPerRow)
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE,    data: &stride),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT,  data: UnsafeMutableRawPointer(mutating: "rgb0" as NSString as AnyObject as! UnsafeMutableRawPointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE,  data: &stride),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: rawPtr.baseAddress!),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID,    data: nil),
            ]
            mpv_render_context_render(ctx, &params)
        }

        // Present via Metal drawable
        guard let drawable = layer.nextDrawable(),
              let device = layer.device else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(width),
            height: Int(height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]

        guard let texture = device.makeTexture(descriptor: descriptor) else { return }

        let region = MTLRegionMake2D(0, 0, Int(width), Int(height))
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: Int(bytesPerRow)
        )

        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitEncoder.copy(
            from: texture,
            sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOriginMake(0, 0, 0),
            sourceSize: MTLSizeMake(Int(width), Int(height), 1),
            to: drawable.texture,
            destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOriginMake(0, 0, 0)
        )
        blitEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        mpv_render_context_report_swap(ctx)
    }
}
