//
//  DicomMetalView.swift
//  DcmSwift
//
//  GPU-first DICOM pixel rendering without CPU round-trip
//

#if canImport(UIKit) && canImport(MetalKit)
import UIKit
import MetalKit
import Metal
import os.signpost
import Foundation

/// GPU-first DICOM pixel view using Metal for direct rendering
/// Eliminates the GPU⇄CPU round-trip by keeping pixels on GPU and applying WL in shader
@MainActor
public final class DicomMetalView: MTKView {
    
    // MARK: - Metal Resources
    
    private var _device: MTLDevice?
    override public var device: MTLDevice? {
        get { return _device }
        set { _device = newValue }
    }
    private var commandQueue: MTLCommandQueue
    private var renderPipelineState: MTLRenderPipelineState?
    private var computePipelineState: MTLComputePipelineState?
    
    // Texture resources
    private var sourceTexture: MTLTexture?
    private var textureHeap: MTLHeap?
    
    // Buffer resources
    private var wlParamsBuffer: MTLBuffer?
    private var vertexBuffer: MTLBuffer?
    
    // MARK: - Rendering State
    
    private var imageWidth: Int = 0
    private var imageHeight: Int = 0
    private var samplesPerPixel: Int = 1
    
    // Window/Level parameters
    private var windowCenter: Float = 0
    private var windowWidth: Float = 0
    private var rescaleSlope: Float = 1.0
    private var rescaleIntercept: Float = 0.0
    private var inverted: Bool = false
    
    // Performance monitoring
    private var enablePerfMetrics: Bool {
        UserDefaults.standard.bool(forKey: "settings.perfMetricsEnabled")
    }
    
    // MARK: - Initialization
    
    public init(device: MTLDevice? = nil) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        self._device = metalDevice
        guard let queue = metalDevice?.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue
        
        super.init(frame: .zero, device: metalDevice)
        
        setupMetalView()
        setupRenderPipeline()
        setupComputePipeline()
        setupBuffers()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupMetalView() {
        // Configure MTKView for optimal performance
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .invalid
        preferredFramesPerSecond = 60
        isPaused = false
        enableSetNeedsDisplay = false
        
        // Enable automatic drawing
        delegate = self
    }
    
    private func setupRenderPipeline() {
        guard let device = device, let library = device.makeDefaultLibrary() else {
            print("❌ Failed to create Metal library")
            return
        }
        
        // Create render pipeline for fragment shader WL
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_wl")
        
        guard let vertexFunc = vertexFunction, let fragmentFunc = fragmentFunction else {
            print("❌ Failed to find shader functions")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Failed to create render pipeline state: \(error)")
        }
    }
    
    private func setupComputePipeline() {
        // Use existing compute pipeline for WL operations
        let accelerator = MetalAccelerator.shared
        if accelerator.isAvailable {
            computePipelineState = accelerator.windowLevelPipelineState
        }
    }
    
    private func setupBuffers() {
        guard let device = device else { return }
        
        // Create WL parameters buffer
        wlParamsBuffer = device.makeBuffer(length: MemoryLayout<WLParams>.stride, options: .storageModeShared)
        
        // Create vertex buffer for full-screen quad
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,  // bottom-left
             1.0, -1.0, 1.0, 1.0,  // bottom-right
            -1.0,  1.0, 0.0, 0.0,  // top-left
             1.0,  1.0, 1.0, 0.0   // top-right
        ]
        
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared)
        
        // Create texture heap for efficient memory management
        if #available(iOS 13.0, macOS 10.15, *) {
            let heapDescriptor = MTLHeapDescriptor()
            heapDescriptor.size = 64 * 1024 * 1024 // 64MB heap
            heapDescriptor.storageMode = .private
            textureHeap = device.makeHeap(descriptor: heapDescriptor)
        }
    }
    
    // MARK: - Public Interface
    
    /// Upload 16-bit grayscale pixels to GPU texture
    public func upload16(_ pixels: UnsafeRawPointer, width: Int, height: Int, pixelFormat: MTLPixelFormat = .r16Uint) {
        guard let device = device else { return }
        
        // Performance monitoring disabled for now
        // let token = performanceMonitor.startGPUOperation(GPUOperation.textureUpload)
        // defer { performanceMonitor.endGPUOperation(token) }
        
        imageWidth = width
        imageHeight = height
        samplesPerPixel = 1
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .private
        
        // Try to allocate from heap first, fallback to direct allocation
        if let heap = textureHeap {
            sourceTexture = heap.makeTexture(descriptor: textureDescriptor)
        } else {
            sourceTexture = device.makeTexture(descriptor: textureDescriptor)
        }
        
        guard let texture = sourceTexture else {
            print("❌ Failed to create source texture")
            return
        }
        
        // Upload pixel data
        let bytesPerRow = width * MemoryLayout<UInt16>.stride
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                              size: MTLSize(width: width, height: height, depth: 1))
        
        texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        
        // Trigger redraw
        setNeedsDisplay()
    }
    
    /// Upload 8-bit RGB pixels to GPU texture
    public func upload8x3(_ pixels: UnsafeRawPointer, width: Int, height: Int, bgr: Bool = false) {
        guard let device = device else { return }
        
        // Performance monitoring disabled for now
        // let token = performanceMonitor.startGPUOperation(GPUOperation.textureUpload)
        // defer { performanceMonitor.endGPUOperation(token) }
        
        imageWidth = width
        imageHeight = height
        samplesPerPixel = 3
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        textureDescriptor.storageMode = .private
        
        if let heap = textureHeap {
            sourceTexture = heap.makeTexture(descriptor: textureDescriptor)
        } else {
            sourceTexture = device.makeTexture(descriptor: textureDescriptor)
        }
        
        guard let texture = sourceTexture else {
            print("❌ Failed to create RGB texture")
            return
        }
        
        let bytesPerRow = width * 3 * MemoryLayout<UInt8>.stride
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                              size: MTLSize(width: width, height: height, depth: 1))
        
        texture.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        
        setNeedsDisplay()
    }
    
    /// Set window/level parameters for shader
    public func setWL(center: Float, width: Float, slope: Float = 1.0, intercept: Float = 0.0, invert: Bool = false) {
        windowCenter = center
        windowWidth = max(1.0, width)
        rescaleSlope = slope
        rescaleIntercept = intercept
        inverted = invert
        
        updateWLParams()
        setNeedsDisplay()
    }
    
    // MARK: - Private Methods
    
    private func updateWLParams() {
        guard let buffer = wlParamsBuffer else { return }
        
        let params = WLParams(
            windowCenter: windowCenter,
            windowWidth: windowWidth,
            rescaleSlope: rescaleSlope,
            rescaleIntercept: rescaleIntercept,
            inverted: inverted,
            imageWidth: Float(imageWidth),
            imageHeight: Float(imageHeight)
        )
        
        var paramsCopy = params
        memcpy(buffer.contents(), &paramsCopy, MemoryLayout<WLParams>.stride)
    }
    
    private func renderFrame() {
        guard let renderPassDescriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let pipelineState = renderPipelineState,
              let sourceTexture = sourceTexture,
              let vertexBuffer = vertexBuffer,
              let wlParamsBuffer = wlParamsBuffer else {
            return
        }
        
        // Performance monitoring disabled for now
        // let token = performanceMonitor.startGPUOperation(GPUOperation.renderPass)
        // defer { performanceMonitor.endGPUOperation(token) }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        renderEncoder.setFragmentBuffer(wlParamsBuffer, offset: 0, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - MTKViewDelegate

extension DicomMetalView: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }
    
    public func draw(in view: MTKView) {
        renderFrame()
    }
}

// MARK: - Supporting Types

struct WLParams {
    var windowCenter: Float
    var windowWidth: Float
    var rescaleSlope: Float
    var rescaleIntercept: Float
    var inverted: Bool
    var imageWidth: Float
    var imageHeight: Float
}

// MARK: - Metal Shaders

// Add these shaders to Shaders.metal:

/*
// Vertex shader for full-screen quad
vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                            constant float4* vertices [[buffer(0)]]) {
    VertexOut out;
    out.position = vertices[vertexID];
    out.texCoord = vertices[vertexID].xy * 0.5 + 0.5; // Convert to 0-1 range
    return out;
}

// Fragment shader for window/level with 16-bit input
fragment float4 fragment_wl(VertexOut in [[stage_in]],
                           texture2d<ushort> sourceTexture [[texture(0)]],
                           constant WLParams& params [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 texCoord = in.texCoord;
    ushort rawValue = sourceTexture.sample(textureSampler, texCoord).r;
    
    // Apply rescale: HU = raw * slope + intercept
    float hu = float(rawValue) * params.rescaleSlope + params.rescaleIntercept;
    
    // Apply window/level: normalize to 0-1 range
    float normalized = (hu - params.windowCenter + params.windowWidth * 0.5) / max(1.0, params.windowWidth);
    normalized = clamp(normalized, 0.0, 1.0);
    
    if (params.inverted) {
        normalized = 1.0 - normalized;
    }
    
    return float4(normalized, normalized, normalized, 1.0);
}

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};
*/

#endif
