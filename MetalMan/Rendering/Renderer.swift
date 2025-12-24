import Metal
import MetalKit
import simd

final class Renderer: NSObject, MTKViewDelegate {
    
    // MARK: - Core Metal Objects
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // Pipeline states
    private let wireframePipelineState: MTLRenderPipelineState
    private let litPipelineState: MTLRenderPipelineState
    private let shadowPipelineState: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private let depthStencilStateNoWrite: MTLDepthStencilState
    private let depthStencilStateSkybox: MTLDepthStencilState
    private let shadowDepthStencilState: MTLDepthStencilState
    
    // Samplers
    private let textureSampler: MTLSamplerState
    private let shadowSampler: MTLSamplerState
    
    // MARK: - Textures (Diffuse)
    
    private var groundTexture: MTLTexture!
    private var trunkTexture: MTLTexture!
    private var foliageTexture: MTLTexture!
    private var rockTexture: MTLTexture!
    private var poleTexture: MTLTexture!
    private var characterTexture: MTLTexture!
    private var pathTexture: MTLTexture!
    private var stoneWallTexture: MTLTexture!
    private var roofTexture: MTLTexture!
    private var woodPlankTexture: MTLTexture!
    private var skyTexture: MTLTexture!
    private var shadowMap: MTLTexture!
    private let shadowMapSize: Int = 2048
    
    // MARK: - Textures (Normal Maps)
    
    private var groundNormalMap: MTLTexture!
    private var trunkNormalMap: MTLTexture!
    private var rockNormalMap: MTLTexture!
    private var pathNormalMap: MTLTexture!
    
    // MARK: - Input
    
    var movementVector: simd_float2 = .zero
    var lookDelta: simd_float2 = .zero
    var jumpPressed: Bool = false
    
    // MARK: - Character State
    
    private var characterPosition: simd_float3 = .zero
    private var characterVelocity: simd_float3 = .zero
    private var characterYaw: Float = 0
    private var targetYaw: Float = 0
    private var walkPhase: Float = 0
    private var isMoving: Bool = false
    
    // ============================================
    // WALK ANIMATION CONFIGURATION
    private let stepsPerUnitDistance: Float = 0.5
    // ============================================
    
    // Jump state
    private var isJumping: Bool = false
    private var verticalVelocity: Float = 0
    private var jumpRequested: Bool = false
    
    private let jumpVelocity: Float = 8.0
    private let gravity: Float = 20.0
    
    // Movement config
    private let characterSpeed: Float = 6.0
    private let acceleration: Float = 40.0
    private let deceleration: Float = 25.0
    private let turnSpeed: Float = 15.0
    
    // MARK: - Camera & Lighting
    
    private var cameraPosition: simd_float3 = simd_float3(0, 8, 10)
    private let cameraHeight: Float = 8.0
    private let cameraDistance: Float = 10.0
    
    // MARK: - Day/Night Cycle
    
    /// Time of day in hours (0-24), cycles continuously
    private var timeOfDay: Float = 10.0  // Start at 10 AM
    
    /// Speed of day/night cycle (1.0 = 24 minutes per full day, higher = faster)
    private let dayNightSpeed: Float = 0.5
    
    /// Computed sun direction based on time of day
    private var sunDirection: simd_float3 {
        // Sun rises at 6:00 (east), peaks at 12:00 (overhead), sets at 18:00 (west)
        let sunAngle = (timeOfDay - 6.0) / 12.0 * .pi  // 0 at sunrise, pi at sunset
        
        // Sun path: rises in east (+X), travels overhead, sets in west (-X)
        let x = -cos(sunAngle)  // East to west
        let y = -abs(sin(sunAngle))  // Always pointing down from above
        let z: Float = -0.3  // Slight offset for interesting shadows
        
        return simd_normalize(simd_float3(x, y, z))
    }
    
    /// Is it currently daytime?
    private var isDaytime: Bool {
        return timeOfDay >= 6.0 && timeOfDay < 18.0
    }
    
    /// Sun intensity based on time (0 at night, 1 at noon)
    private var sunIntensity: Float {
        if timeOfDay < 5.0 || timeOfDay > 19.0 {
            return 0.0  // Full night
        } else if timeOfDay < 6.0 {
            return (timeOfDay - 5.0)  // Dawn
        } else if timeOfDay > 18.0 {
            return 1.0 - (timeOfDay - 18.0)  // Dusk
        } else {
            // Day - peak at noon
            let noonDistance = abs(timeOfDay - 12.0) / 6.0
            return 1.0 - noonDistance * 0.3
        }
    }
    
    /// Ambient intensity based on time of day
    private var ambientIntensity: Float {
        let baseAmbient: Float = 0.15
        let dayAmbient: Float = 0.35
        return baseAmbient + (dayAmbient - baseAmbient) * sunIntensity
    }
    
    /// Diffuse (sun) intensity based on time of day
    private var diffuseIntensity: Float {
        return 0.65 * sunIntensity
    }
    
    /// Sky color parameters for current time
    private var skyColors: (top: simd_float3, horizon: simd_float3, sun: simd_float3) {
        if timeOfDay < 5.0 || timeOfDay >= 20.0 {
            // Night
            return (
                top: simd_float3(0.02, 0.02, 0.08),      // Deep blue-black
                horizon: simd_float3(0.05, 0.05, 0.12),  // Slightly lighter
                sun: simd_float3(0.8, 0.85, 1.0)         // Moonlight color
            )
        } else if timeOfDay < 6.0 {
            // Dawn (5-6)
            let t = timeOfDay - 5.0
            return (
                top: simd_mix(simd_float3(0.02, 0.02, 0.08), simd_float3(0.2, 0.3, 0.5), simd_float3(repeating: t)),
                horizon: simd_mix(simd_float3(0.05, 0.05, 0.12), simd_float3(0.9, 0.5, 0.3), simd_float3(repeating: t)),
                sun: simd_float3(1.0, 0.6, 0.3)  // Orange sunrise
            )
        } else if timeOfDay < 8.0 {
            // Early morning (6-8)
            let t = (timeOfDay - 6.0) / 2.0
            return (
                top: simd_mix(simd_float3(0.2, 0.3, 0.5), simd_float3(0.3, 0.5, 0.9), simd_float3(repeating: t)),
                horizon: simd_mix(simd_float3(0.9, 0.5, 0.3), simd_float3(0.6, 0.7, 0.9), simd_float3(repeating: t)),
                sun: simd_mix(simd_float3(1.0, 0.6, 0.3), simd_float3(1.0, 0.95, 0.8), simd_float3(repeating: t))
            )
        } else if timeOfDay < 17.0 {
            // Day (8-17)
            return (
                top: simd_float3(0.3, 0.5, 0.9),         // Blue sky
                horizon: simd_float3(0.6, 0.7, 0.9),     // Pale blue
                sun: simd_float3(1.0, 0.95, 0.85)        // Warm white sunlight
            )
        } else if timeOfDay < 18.0 {
            // Late afternoon (17-18)
            let t = timeOfDay - 17.0
            return (
                top: simd_mix(simd_float3(0.3, 0.5, 0.9), simd_float3(0.4, 0.3, 0.5), simd_float3(repeating: t)),
                horizon: simd_mix(simd_float3(0.6, 0.7, 0.9), simd_float3(0.95, 0.6, 0.4), simd_float3(repeating: t)),
                sun: simd_float3(1.0, 0.5, 0.2)  // Orange sunset
            )
        } else if timeOfDay < 19.0 {
            // Dusk (18-19)
            let t = timeOfDay - 18.0
            return (
                top: simd_mix(simd_float3(0.4, 0.3, 0.5), simd_float3(0.1, 0.08, 0.2), simd_float3(repeating: t)),
                horizon: simd_mix(simd_float3(0.95, 0.6, 0.4), simd_float3(0.3, 0.15, 0.2), simd_float3(repeating: t)),
                sun: simd_float3(0.9, 0.3, 0.2)  // Deep red sunset
            )
        } else {
            // Twilight (19-20)
            let t = timeOfDay - 19.0
            return (
                top: simd_mix(simd_float3(0.1, 0.08, 0.2), simd_float3(0.02, 0.02, 0.08), simd_float3(repeating: t)),
                horizon: simd_mix(simd_float3(0.3, 0.15, 0.2), simd_float3(0.05, 0.05, 0.12), simd_float3(repeating: t)),
                sun: simd_float3(0.8, 0.85, 1.0)  // Moonlight
            )
        }
    }
    
    // MARK: - Matrices & Viewport
    
    private var viewportSize: CGSize = .zero
    private var projectionMatrix = matrix_identity_float4x4
    private var viewMatrix = matrix_identity_float4x4
    private var lightViewProjectionMatrix = matrix_identity_float4x4
    
    // MARK: - Geometry Buffers
    
    private var gridLineBuffer: MTLBuffer
    private var gridLineCount: Int = 0
    
    private var groundVertexBuffer: MTLBuffer
    private var groundVertexCount: Int = 0
    private var treeVertexBuffer: MTLBuffer
    private var treeVertexCount: Int = 0
    private var rockVertexBuffer: MTLBuffer
    private var rockVertexCount: Int = 0
    private var poleVertexBuffer: MTLBuffer
    private var poleVertexCount: Int = 0
    private var structureVertexBuffer: MTLBuffer
    private var structureVertexCount: Int = 0
    private var skyboxVertexBuffer: MTLBuffer
    private var skyboxVertexCount: Int = 0
    
    // Character mesh (animated each frame)
    private let characterMesh: CharacterMesh
    
    // Uniform buffers
    private var uniformBuffer: MTLBuffer
    private var litUniformBuffer: MTLBuffer
    private var characterUniformBuffer: MTLBuffer
    private var skyboxUniformBuffer: MTLBuffer
    
    // Collision
    private var colliders: [Collider] = []
    private let characterRadius: Float = 0.3
    
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    
    // MARK: - Init
    
    init(device: MTLDevice, view: MTKView) {
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = commandQueue
        
        // Create shader library
        do {
            self.library = try device.makeLibrary(source: metalShaderSource, options: nil)
        } catch {
            fatalError("Failed to create shader library: \(error)")
        }
        
        // Create pipeline states
        self.wireframePipelineState = Renderer.createWireframePipeline(device: device, library: library, view: view)
        self.litPipelineState = Renderer.createLitPipeline(device: device, library: library, view: view)
        self.shadowPipelineState = Renderer.createShadowPipeline(device: device, library: library)
        
        // Create depth stencil states
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)!
        
        let depthDescNoWrite = MTLDepthStencilDescriptor()
        depthDescNoWrite.depthCompareFunction = .less
        depthDescNoWrite.isDepthWriteEnabled = false
        self.depthStencilStateNoWrite = device.makeDepthStencilState(descriptor: depthDescNoWrite)!
        
        // Skybox: always pass depth test (draw at infinity)
        let skyboxDepthDesc = MTLDepthStencilDescriptor()
        skyboxDepthDesc.depthCompareFunction = .lessEqual
        skyboxDepthDesc.isDepthWriteEnabled = false
        self.depthStencilStateSkybox = device.makeDepthStencilState(descriptor: skyboxDepthDesc)!
        
        let shadowDepthDesc = MTLDepthStencilDescriptor()
        shadowDepthDesc.depthCompareFunction = .less
        shadowDepthDesc.isDepthWriteEnabled = true
        self.shadowDepthStencilState = device.makeDepthStencilState(descriptor: shadowDepthDesc)!
        
        // Create samplers
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        self.textureSampler = device.makeSamplerState(descriptor: samplerDesc)!
        
        let shadowSamplerDesc = MTLSamplerDescriptor()
        shadowSamplerDesc.minFilter = .linear
        shadowSamplerDesc.magFilter = .linear
        shadowSamplerDesc.compareFunction = .less
        self.shadowSampler = device.makeSamplerState(descriptor: shadowSamplerDesc)!
        
        // Create geometry
        var allColliders: [Collider] = []
        
        // Clear any previous placement tracking
        GeometryGenerator.clearOccupiedAreas()
        
        (gridLineBuffer, gridLineCount) = GeometryGenerator.makeGridLines(device: device)
        (groundVertexBuffer, groundVertexCount) = GeometryGenerator.makeGroundMesh(device: device)
        (skyboxVertexBuffer, skyboxVertexCount) = GeometryGenerator.makeSkybox(device: device)
        
        // Generate objects in order of priority (largest first to ensure they get placed)
        // 1. Structures first (houses, ruins, towers)
        let structureResult = GeometryGenerator.makeStructureMeshes(device: device)
        structureVertexBuffer = structureResult.0
        structureVertexCount = structureResult.1
        allColliders.append(contentsOf: structureResult.2)
        
        // 2. Trees second (medium-large objects)
        let treeResult = GeometryGenerator.makeTreeMeshes(device: device)
        treeVertexBuffer = treeResult.0
        treeVertexCount = treeResult.1
        allColliders.append(contentsOf: treeResult.2)
        
        // 3. Rocks third (medium objects)
        let rockResult = GeometryGenerator.makeRockMeshes(device: device)
        rockVertexBuffer = rockResult.0
        rockVertexCount = rockResult.1
        allColliders.append(contentsOf: rockResult.2)
        
        // 4. Poles last (smallest objects)
        let poleResult = GeometryGenerator.makePoleMeshes(device: device)
        poleVertexBuffer = poleResult.0
        poleVertexCount = poleResult.1
        allColliders.append(contentsOf: poleResult.2)
        
        self.colliders = allColliders
        
        // Create character mesh
        self.characterMesh = CharacterMesh(device: device)
        
        // Create uniform buffers
        uniformBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride * 3, options: [])!
        litUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: [])!
        characterUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: [])!
        skyboxUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: [])!
        
        super.init()
        
        // Create textures
        let textureGen = TextureGenerator(device: device, commandQueue: commandQueue)
        // Diffuse textures
        groundTexture = textureGen.createGroundTexture()
        trunkTexture = textureGen.createTrunkTexture()
        foliageTexture = textureGen.createFoliageTexture()
        rockTexture = textureGen.createRockTexture()
        poleTexture = textureGen.createPoleTexture()
        characterTexture = textureGen.createCharacterTexture()
        pathTexture = textureGen.createPathTexture()
        stoneWallTexture = textureGen.createStoneWallTexture()
        roofTexture = textureGen.createRoofTexture()
        woodPlankTexture = textureGen.createWoodPlankTexture()
        skyTexture = textureGen.createSkyTexture()
        shadowMap = textureGen.createShadowMap(size: shadowMapSize)
        
        // Normal maps
        groundNormalMap = textureGen.createGroundNormalMap()
        trunkNormalMap = textureGen.createTrunkNormalMap()
        rockNormalMap = textureGen.createRockNormalMap()
        pathNormalMap = textureGen.createPathNormalMap()
        
        // Initialize character mesh
        characterMesh.update(walkPhase: walkPhase, isJumping: isJumping)
        
        // Setup view
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1.0)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        
        viewportSize = view.drawableSize
        if viewportSize.width == 0 || viewportSize.height == 0 {
            viewportSize = CGSize(width: 1024, height: 768)
        }
        
        updateProjection(size: viewportSize)
        updateLightMatrix()
    }
    
    // MARK: - Pipeline Creation
    
    private static func createWireframePipeline(device: MTLDevice, library: MTLLibrary, view: MTKView) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertex_main")
        desc.fragmentFunction = library.makeFunction(name: "fragment_main")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.depthAttachmentPixelFormat = .depth32Float
        
        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float3
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.attributes[1].format = .float4
        vertexDesc.attributes[1].offset = 12
        vertexDesc.attributes[1].bufferIndex = 0
        vertexDesc.layouts[0].stride = MemoryLayout<Vertex>.stride
        desc.vertexDescriptor = vertexDesc
        
        return try! device.makeRenderPipelineState(descriptor: desc)
    }
    
    private static func createLitPipeline(device: MTLDevice, library: MTLLibrary, view: MTKView) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertex_lit")
        desc.fragmentFunction = library.makeFunction(name: "fragment_lit")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.vertexDescriptor = Renderer.texturedVertexDescriptor()
        
        return try! device.makeRenderPipelineState(descriptor: desc)
    }
    
    private static func createShadowPipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertex_shadow")
        desc.fragmentFunction = library.makeFunction(name: "fragment_shadow")
        desc.colorAttachments[0].pixelFormat = .invalid
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.vertexDescriptor = Renderer.texturedVertexDescriptor()
        
        return try! device.makeRenderPipelineState(descriptor: desc)
    }
    
    private static func texturedVertexDescriptor() -> MTLVertexDescriptor {
        let desc = MTLVertexDescriptor()
        
        // Use actual offsets from Swift struct layout
        let positionOffset = MemoryLayout<TexturedVertex>.offset(of: \TexturedVertex.position)!
        let normalOffset = MemoryLayout<TexturedVertex>.offset(of: \TexturedVertex.normal)!
        let tangentOffset = MemoryLayout<TexturedVertex>.offset(of: \TexturedVertex.tangent)!
        let texCoordOffset = MemoryLayout<TexturedVertex>.offset(of: \TexturedVertex.texCoord)!
        let materialIndexOffset = MemoryLayout<TexturedVertex>.offset(of: \TexturedVertex.materialIndex)!
        
        desc.attributes[0].format = .float3  // position
        desc.attributes[0].offset = positionOffset
        desc.attributes[0].bufferIndex = 0
        desc.attributes[1].format = .float3  // normal
        desc.attributes[1].offset = normalOffset
        desc.attributes[1].bufferIndex = 0
        desc.attributes[2].format = .float3  // tangent
        desc.attributes[2].offset = tangentOffset
        desc.attributes[2].bufferIndex = 0
        desc.attributes[3].format = .float2  // texCoord
        desc.attributes[3].offset = texCoordOffset
        desc.attributes[3].bufferIndex = 0
        desc.attributes[4].format = .uint    // materialIndex
        desc.attributes[4].offset = materialIndexOffset
        desc.attributes[4].bufferIndex = 0
        desc.layouts[0].stride = MemoryLayout<TexturedVertex>.stride
        return desc
    }
    
    private func updateLightMatrix() {
        // Use sun direction for daytime, fixed moon direction for nighttime
        let lightDir = isDaytime ? sunDirection : simd_normalize(simd_float3(0.3, -0.8, 0.2))
        let lightPos = -lightDir * 80
        let lightTarget = simd_float3(0, 0, 0)
        let lightUp = simd_float3(0, 1, 0)
        
        let lightView = lookAt(eye: lightPos, center: lightTarget, up: lightUp)
        let lightProj = orthographicRH(left: -120, right: 120, bottom: -120, top: 120, near: 1, far: 200)
        
        lightViewProjectionMatrix = lightProj * lightView
    }
    
    private func updateTimeOfDay(deltaTime: Float) {
        // Advance time (dayNightSpeed controls how fast the cycle is)
        // At speed 1.0, full day takes 24 minutes real time
        timeOfDay += deltaTime * dayNightSpeed / 60.0
        
        // Wrap around at 24 hours
        if timeOfDay >= 24.0 {
            timeOfDay -= 24.0
        }
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        updateProjection(size: size)
    }
    
    func draw(in view: MTKView) {
        let currentSize = view.drawableSize
        if currentSize.width > 0 && currentSize.height > 0 &&
           (viewportSize.width != currentSize.width || viewportSize.height != currentSize.height) {
            viewportSize = currentSize
            updateProjection(size: currentSize)
        }
        
        guard let drawable = view.currentDrawable,
              let mainDescriptor = view.currentRenderPassDescriptor else { return }
        
        let now = CACurrentMediaTime()
        if viewportSize.width == 0 || viewportSize.height == 0 {
            lastFrameTime = now
            return
        }
        
        var dt = Float(now - lastFrameTime)
        dt = min(max(dt, 0.0), 0.1)
        
        // Update day/night cycle
        updateTimeOfDay(deltaTime: dt)
        
        updateCharacter(deltaTime: dt)
        updateCamera(deltaTime: dt)
        viewMatrix = buildViewMatrix()
        updateLightMatrix()  // Update shadows for current sun position
        
        let vp = projectionMatrix * viewMatrix
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Update character mesh animation
        characterMesh.update(walkPhase: walkPhase, isJumping: isJumping)
        
        // Shadow pass
        renderShadowPass(commandBuffer: commandBuffer, viewProjection: vp)
        
        // Main pass
        renderMainPass(commandBuffer: commandBuffer, descriptor: mainDescriptor, viewProjection: vp)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        lastFrameTime = now
    }
    
    // MARK: - Render Passes
    
    private func renderShadowPass(commandBuffer: MTLCommandBuffer, viewProjection vp: simd_float4x4) {
        let shadowPassDesc = MTLRenderPassDescriptor()
        shadowPassDesc.depthAttachment.texture = shadowMap
        shadowPassDesc.depthAttachment.loadAction = .clear
        shadowPassDesc.depthAttachment.storeAction = .store
        shadowPassDesc.depthAttachment.clearDepth = 1.0
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPassDesc) else { return }
        
        encoder.setRenderPipelineState(shadowPipelineState)
        encoder.setDepthStencilState(shadowDepthStencilState)
        encoder.setCullMode(.front)
        
        // Landscape with identity matrix
        let currentLightDir = isDaytime ? sunDirection : simd_normalize(simd_float3(0.3, -0.8, 0.2))
        let currentSkyColors = skyColors
        var shadowUniforms = LitUniforms(
            modelMatrix: matrix_identity_float4x4,
            viewProjectionMatrix: vp,
            lightViewProjectionMatrix: lightViewProjectionMatrix,
            lightDirection: currentLightDir,
            cameraPosition: cameraPosition,
            ambientIntensity: ambientIntensity,
            diffuseIntensity: diffuseIntensity,
            skyColorTop: currentSkyColors.top,
            skyColorHorizon: currentSkyColors.horizon,
            sunColor: currentSkyColors.sun,
            timeOfDay: timeOfDay
        )
        memcpy(litUniformBuffer.contents(), &shadowUniforms, MemoryLayout<LitUniforms>.stride)
        encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
        
        drawLandscape(encoder: encoder)
        
        // Character with model matrix
        let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
        var charUniforms = shadowUniforms
        charUniforms.modelMatrix = charModelMatrix
        memcpy(characterUniformBuffer.contents(), &charUniforms, MemoryLayout<LitUniforms>.stride)
        encoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(characterMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: characterMesh.vertexCount)
        
        encoder.endEncoding()
    }
    
    private func renderMainPass(commandBuffer: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, viewProjection vp: simd_float4x4) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        
        // Bind all textures
        bindTextures(encoder: encoder)
        
        // Draw skybox first (no depth write, always behind everything)
        encoder.setCullMode(.front)  // Inside of cube
        encoder.setRenderPipelineState(litPipelineState)
        encoder.setDepthStencilState(depthStencilStateSkybox)
        
        // Skybox follows camera position
        let currentLightDir = isDaytime ? sunDirection : simd_normalize(simd_float3(0.3, -0.8, 0.2))
        let currentSkyColors = skyColors
        var skyboxUniforms = LitUniforms(
            modelMatrix: translation(cameraPosition.x, cameraPosition.y, cameraPosition.z),
            viewProjectionMatrix: vp,
            lightViewProjectionMatrix: lightViewProjectionMatrix,
            lightDirection: currentLightDir,
            cameraPosition: cameraPosition,
            ambientIntensity: 1.0,  // Full brightness for sky
            diffuseIntensity: 0.0,
            skyColorTop: currentSkyColors.top,
            skyColorHorizon: currentSkyColors.horizon,
            sunColor: currentSkyColors.sun,
            timeOfDay: timeOfDay
        )
        memcpy(skyboxUniformBuffer.contents(), &skyboxUniforms, MemoryLayout<LitUniforms>.stride)
        encoder.setVertexBuffer(skyboxUniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(skyboxUniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(skyboxVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: skyboxVertexCount)
        
        // Now draw the rest with normal settings
        encoder.setCullMode(.back)
        encoder.setDepthStencilState(depthStencilState)
        
        // Setup uniforms for landscape
        var litUniforms = LitUniforms(
            modelMatrix: matrix_identity_float4x4,
            viewProjectionMatrix: vp,
            lightViewProjectionMatrix: lightViewProjectionMatrix,
            lightDirection: currentLightDir,
            cameraPosition: cameraPosition,
            ambientIntensity: ambientIntensity,
            diffuseIntensity: diffuseIntensity,
            skyColorTop: currentSkyColors.top,
            skyColorHorizon: currentSkyColors.horizon,
            sunColor: currentSkyColors.sun,
            timeOfDay: timeOfDay
        )
        memcpy(litUniformBuffer.contents(), &litUniforms, MemoryLayout<LitUniforms>.stride)
        encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
        
        // Draw landscape
        drawLandscape(encoder: encoder)
        
        // Draw character
        let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
        var charUniforms = litUniforms
        charUniforms.modelMatrix = charModelMatrix
        memcpy(characterUniformBuffer.contents(), &charUniforms, MemoryLayout<LitUniforms>.stride)
        encoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(characterUniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(characterMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: characterMesh.vertexCount)
        
        // Draw grid lines overlay
        encoder.setRenderPipelineState(wireframePipelineState)
        encoder.setDepthStencilState(depthStencilStateNoWrite)
        
        var gridMVP = vp
        memcpy(uniformBuffer.contents(), &gridMVP, MemoryLayout<simd_float4x4>.stride)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(gridLineBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridLineCount)
        
        encoder.endEncoding()
    }
    
    private func bindTextures(encoder: MTLRenderCommandEncoder) {
        // Diffuse textures (indices 0-11)
        encoder.setFragmentTexture(groundTexture, index: 0)
        encoder.setFragmentTexture(trunkTexture, index: 1)
        encoder.setFragmentTexture(foliageTexture, index: 2)
        encoder.setFragmentTexture(rockTexture, index: 3)
        encoder.setFragmentTexture(poleTexture, index: 4)
        encoder.setFragmentTexture(shadowMap, index: 5)
        encoder.setFragmentTexture(characterTexture, index: 6)
        encoder.setFragmentTexture(pathTexture, index: 7)
        encoder.setFragmentTexture(stoneWallTexture, index: 8)
        encoder.setFragmentTexture(roofTexture, index: 9)
        encoder.setFragmentTexture(woodPlankTexture, index: 10)
        encoder.setFragmentTexture(skyTexture, index: 11)
        
        // Normal maps (indices 12-15)
        encoder.setFragmentTexture(groundNormalMap, index: 12)
        encoder.setFragmentTexture(trunkNormalMap, index: 13)
        encoder.setFragmentTexture(rockNormalMap, index: 14)
        encoder.setFragmentTexture(pathNormalMap, index: 15)
        
        encoder.setFragmentSamplerState(textureSampler, index: 0)
        encoder.setFragmentSamplerState(shadowSampler, index: 1)
    }
    
    private func drawLandscape(encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(groundVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: groundVertexCount)
        
        encoder.setVertexBuffer(treeVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: treeVertexCount)
        
        encoder.setVertexBuffer(rockVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: rockVertexCount)
        
        encoder.setVertexBuffer(poleVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: poleVertexCount)
        
        encoder.setVertexBuffer(structureVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: structureVertexCount)
    }
    
    // MARK: - Character & Camera Updates
    
    private func updateCharacter(deltaTime dt: Float) {
        let targetVelocity = simd_float3(
            movementVector.x * characterSpeed,
            0,
            -movementVector.y * characterSpeed
        )
        
        let targetSpeed = simd_length(targetVelocity)
        isMoving = targetSpeed > 0.1
        
        if isMoving {
            let currentSpeed = simd_length(characterVelocity)
            let speedDiff = targetSpeed - currentSpeed
            let accelThisFrame = acceleration * dt
            
            if speedDiff > 0 {
                let newSpeed = min(currentSpeed + accelThisFrame, targetSpeed)
                let direction = simd_normalize(targetVelocity)
                characterVelocity = direction * newSpeed
            } else {
                characterVelocity = targetVelocity
            }
            
            targetYaw = atan2(targetVelocity.x, -targetVelocity.z)
        } else {
            let currentSpeed = simd_length(characterVelocity)
            if currentSpeed > 0.01 {
                let newSpeed = max(currentSpeed - deceleration * dt, 0)
                characterVelocity = simd_normalize(characterVelocity) * newSpeed
            } else {
                characterVelocity = .zero
            }
        }
        
        // Update position with collision detection
        let newPosition = characterPosition + characterVelocity * dt
        var finalPosition = newPosition
        var collisionOccurred = false
        var standingSurfaceHeight: Float? = nil  // Height of surface character is standing on (if climbable)
        
        // Multiple iterations to resolve overlapping collisions
        for _ in 0..<3 {
            let charPos2D = simd_float2(finalPosition.x, finalPosition.z)
            let charFeetY = finalPosition.y  // Current character base Y position
            
            for collider in colliders {
                switch collider.type {
                case .circle:
                    // Simple circle collision
                    let toChar = charPos2D - collider.position
                    let distance = simd_length(toChar)
                    let minDist = collider.radius + characterRadius
                    
                    if distance < minDist && distance > 0.001 {
                        let pushDirection = simd_normalize(toChar)
                        let pushAmount = minDist - distance + 0.01
                        finalPosition.x += pushDirection.x * pushAmount
                        finalPosition.z += pushDirection.y * pushAmount
                        collisionOccurred = true
                    }
                    
                case .box:
                    // Box collision (axis-aligned for now)
                    let localX = charPos2D.x - collider.position.x
                    let localZ = charPos2D.y - collider.position.y
                    
                    // Check if character is within box + character radius
                    let expandedHalfW = collider.halfExtents.x + characterRadius
                    let expandedHalfD = collider.halfExtents.y + characterRadius
                    
                    if abs(localX) < expandedHalfW && abs(localZ) < expandedHalfD {
                        // Inside the box - push out along shortest axis
                        let overlapX = expandedHalfW - abs(localX)
                        let overlapZ = expandedHalfD - abs(localZ)
                        
                        if overlapX < overlapZ {
                            // Push out along X
                            finalPosition.x += (localX > 0 ? 1 : -1) * (overlapX + 0.01)
                        } else {
                            // Push out along Z
                            finalPosition.z += (localZ > 0 ? 1 : -1) * (overlapZ + 0.01)
                        }
                        collisionOccurred = true
                    }
                    
                case .climbable:
                    // Climbable objects (like rocks) - can walk on top
                    let toChar = charPos2D - collider.position
                    let distance = simd_length(toChar)
                    let collisionRadius = collider.radius + characterRadius
                    
                    // Check horizontal proximity
                    if distance < collider.radius {
                        // Character is directly above/on the object
                        let surfaceY = collider.baseY + collider.height
                        
                        // If character's feet are at or above surface, they can stand on it
                        if charFeetY >= surfaceY - 0.5 {
                            // Standing on top - record this surface height
                            if standingSurfaceHeight == nil || surfaceY > standingSurfaceHeight! {
                                standingSurfaceHeight = surfaceY
                            }
                        } else {
                            // Below surface level - push out horizontally
                            if distance > 0.001 {
                                let pushDirection = simd_normalize(toChar)
                                let pushAmount = collider.radius - distance + characterRadius + 0.01
                                finalPosition.x += pushDirection.x * pushAmount
                                finalPosition.z += pushDirection.y * pushAmount
                                collisionOccurred = true
                            }
                        }
                    } else if distance < collisionRadius {
                        // Near the edge - check if we should collide or can climb
                        let surfaceY = collider.baseY + collider.height
                        let stepUpThreshold: Float = 0.5  // Can step up this high
                        
                        if charFeetY >= surfaceY - stepUpThreshold {
                            // Can step up onto the object
                            if standingSurfaceHeight == nil || surfaceY > standingSurfaceHeight! {
                                standingSurfaceHeight = surfaceY
                            }
                        } else {
                            // Too low - push out
                            let pushDirection = simd_normalize(toChar)
                            let pushAmount = collisionRadius - distance + 0.01
                            finalPosition.x += pushDirection.x * pushAmount
                            finalPosition.z += pushDirection.y * pushAmount
                            collisionOccurred = true
                        }
                    }
                }
            }
        }
        
        if collisionOccurred {
            characterVelocity *= 0.5
        }
        
        characterPosition.x = max(-95, min(95, finalPosition.x))
        characterPosition.z = max(-95, min(95, finalPosition.z))
        
        // Get terrain height at character position
        var terrainHeight = Terrain.heightAt(x: characterPosition.x, z: characterPosition.z)
        
        // If standing on a climbable surface, use that height instead
        if let surfaceHeight = standingSurfaceHeight, surfaceHeight > terrainHeight {
            terrainHeight = surfaceHeight
        }
        
        // Smooth turning
        var yawDiff = targetYaw - characterYaw
        while yawDiff > .pi { yawDiff -= 2 * .pi }
        while yawDiff < -.pi { yawDiff += 2 * .pi }
        
        let maxTurn = turnSpeed * dt
        if abs(yawDiff) < maxTurn {
            characterYaw = targetYaw
        } else {
            characterYaw += (yawDiff > 0 ? 1 : -1) * maxTurn
        }
        
        // Walk animation
        if isMoving && !isJumping {
            let distanceThisFrame = simd_length(characterVelocity) * dt
            let radiansPerStep: Float = 2 * .pi
            walkPhase += distanceThisFrame * stepsPerUnitDistance * radiansPerStep
            while walkPhase > 2 * .pi { walkPhase -= 2 * .pi }
        }
        
        // Jump physics
        if jumpPressed && !jumpRequested && !isJumping {
            isJumping = true
            verticalVelocity = jumpVelocity
            jumpRequested = true
        }
        
        if !jumpPressed {
            jumpRequested = false
        }
        
        if isJumping {
            verticalVelocity -= gravity * dt
            characterPosition.y += verticalVelocity * dt
            
            // Check if landed on terrain
            if characterPosition.y <= terrainHeight {
                characterPosition.y = terrainHeight
                isJumping = false
                verticalVelocity = 0
            }
        } else {
            // Follow terrain height when not jumping
            characterPosition.y = terrainHeight
        }
    }
    
    private func updateCamera(deltaTime dt: Float) {
        cameraPosition = simd_float3(
            characterPosition.x,
            characterPosition.y + cameraHeight,
            characterPosition.z + cameraDistance
        )
    }
    
    private func buildViewMatrix() -> simd_float4x4 {
        let lookTarget = characterPosition + simd_float3(0, 1.0, 0)
        return lookAt(eye: cameraPosition, center: lookTarget, up: simd_float3(0, 1, 0))
    }
    
    private func updateProjection(size: CGSize) {
        guard size.width > 0 && size.height > 0 else {
            projectionMatrix = perspectiveFovRH(fovYRadians: 45 * .pi / 180, aspectRatio: 16.0/9.0, nearZ: 0.1, farZ: 500)
            return
        }
        let aspect = Float(size.width / size.height)
        projectionMatrix = perspectiveFovRH(fovYRadians: 45 * .pi / 180, aspectRatio: aspect, nearZ: 0.1, farZ: 500)
    }
}
