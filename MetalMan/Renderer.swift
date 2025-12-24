import Metal
import MetalKit
import simd

final class Renderer: NSObject, MTKViewDelegate {
    // Simple vertex for wireframe (stick figure)
    struct Vertex {
        var position: simd_float3
        var color: simd_float4
    }
    
    // Textured vertex for solid geometry with lighting
    struct TexturedVertex {
        var position: simd_float3
        var normal: simd_float3
        var texCoord: simd_float2
        var materialIndex: UInt32  // 0=ground, 1=tree trunk, 2=foliage, 3=rock, 4=pole
        var padding: UInt32 = 0
    }
    
    // Uniforms for lit rendering
    struct LitUniforms {
        var modelMatrix: simd_float4x4
        var viewProjectionMatrix: simd_float4x4
        var lightViewProjectionMatrix: simd_float4x4
        var lightDirection: simd_float3
        var cameraPosition: simd_float3
        var ambientIntensity: Float
        var diffuseIntensity: Float
    }
    
    // Collision circle for simple 2D collision detection (on XZ plane)
    struct Collider {
        var position: simd_float2  // X, Z position
        var radius: Float
    }
    
    // MARK: - Properties
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // Pipeline states
    let wireframePipelineState: MTLRenderPipelineState
    let litPipelineState: MTLRenderPipelineState
    let shadowPipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let depthStencilStateNoWrite: MTLDepthStencilState
    let shadowDepthStencilState: MTLDepthStencilState
    var library: MTLLibrary
    
    // Textures
    var groundTexture: MTLTexture!
    var trunkTexture: MTLTexture!
    var foliageTexture: MTLTexture!
    var rockTexture: MTLTexture!
    var poleTexture: MTLTexture!
    var characterTexture: MTLTexture!  // Skin/clothes texture for 3D character
    var shadowMap: MTLTexture!
    let shadowMapSize: Int = 2048
    let textureSampler: MTLSamplerState
    let shadowSampler: MTLSamplerState
    
    // Input from keyboard/touch
    var movementVector: simd_float2 = .zero
    var lookDelta: simd_float2 = .zero
    
    // Character state
    private var characterPosition: simd_float3 = .zero
    private var characterVelocity: simd_float3 = .zero
    private var characterYaw: Float = 0
    private var targetYaw: Float = 0
    
    // Walking animation state
    private var walkPhase: Float = 0
    private var walkSpeed: Float = 12.0
    private var isMoving: Bool = false
    
    // Movement configuration
    private let characterSpeed: Float = 6.0
    private let acceleration: Float = 40.0
    private let deceleration: Float = 25.0
    private let turnSpeed: Float = 15.0
    
    // Camera configuration
    private var cameraPosition: simd_float3 = simd_float3(0, 8, 10)
    private let cameraHeight: Float = 8.0
    private let cameraDistance: Float = 10.0
    
    // Lighting
    private let lightDirection = simd_normalize(simd_float3(-0.5, -0.8, -0.3))
    private let ambientIntensity: Float = 0.35
    private let diffuseIntensity: Float = 0.65
    
    private var viewportSize: CGSize = .zero
    
    // Matrices
    private var projectionMatrix = matrix_identity_float4x4
    private var viewMatrix = matrix_identity_float4x4
    private var lightViewProjectionMatrix = matrix_identity_float4x4
    
    // Wireframe buffers (grid overlay only now)
    private var gridLineBuffer: MTLBuffer
    private var gridLineCount: Int = 0
    
    // 3D Character mesh (animated humanoid)
    private var characterVertexBuffer: MTLBuffer
    private var characterVertexCount: Int = 0
    private let characterMaxVertices = 2000  // Enough for animated humanoid
    
    // Solid geometry buffers
    private var groundVertexBuffer: MTLBuffer
    private var groundVertexCount: Int = 0
    private var treeVertexBuffer: MTLBuffer
    private var treeVertexCount: Int = 0
    private var rockVertexBuffer: MTLBuffer
    private var rockVertexCount: Int = 0
    private var poleVertexBuffer: MTLBuffer
    private var poleVertexCount: Int = 0
    
    // Uniform buffers
    private var uniformBuffer: MTLBuffer
    private var litUniformBuffer: MTLBuffer          // For landscape (identity model matrix)
    private var characterUniformBuffer: MTLBuffer   // For character (with model transform)
    
    // Collision detection
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
        
        // Shader source with lighting, textures, and shadows
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        // Simple wireframe vertex
        struct VertexIn {
            float3 position [[attribute(0)]];
            float4 color [[attribute(1)]];
        };
        
        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };
        
        struct Uniforms {
            float4x4 mvpMatrix;
        };
        
        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
            out.color = in.color;
            return out;
        }
        
        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return in.color;
        }
        
        // Textured lit vertex
        struct TexturedVertexIn {
            float3 position [[attribute(0)]];
            float3 normal [[attribute(1)]];
            float2 texCoord [[attribute(2)]];
            uint materialIndex [[attribute(3)]];
        };
        
        struct LitVertexOut {
            float4 position [[position]];
            float3 worldPosition;
            float3 normal;
            float2 texCoord;
            float4 lightSpacePosition;
            uint materialIndex;
        };
        
        struct LitUniforms {
            float4x4 modelMatrix;
            float4x4 viewProjectionMatrix;
            float4x4 lightViewProjectionMatrix;
            float3 lightDirection;
            float3 cameraPosition;
            float ambientIntensity;
            float diffuseIntensity;
        };
        
        vertex LitVertexOut vertex_lit(TexturedVertexIn in [[stage_in]],
                                       constant LitUniforms &uniforms [[buffer(1)]]) {
            LitVertexOut out;
            float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
            out.worldPosition = worldPos.xyz;
            out.position = uniforms.viewProjectionMatrix * worldPos;
            out.normal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
            out.texCoord = in.texCoord;
            out.lightSpacePosition = uniforms.lightViewProjectionMatrix * worldPos;
            out.materialIndex = in.materialIndex;
            return out;
        }
        
        float calculateShadow(float4 lightSpacePos, depth2d<float> shadowMap, sampler shadowSampler) {
            float3 projCoords = lightSpacePos.xyz / lightSpacePos.w;
            projCoords.xy = projCoords.xy * 0.5 + 0.5;
            projCoords.y = 1.0 - projCoords.y;
            
            if (projCoords.x < 0 || projCoords.x > 1 || projCoords.y < 0 || projCoords.y > 1 || projCoords.z > 1) {
                return 1.0;
            }
            
            float currentDepth = projCoords.z;
            float bias = 0.005;
            
            // PCF soft shadows
            float shadow = 0.0;
            float2 texelSize = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
            for (int x = -1; x <= 1; x++) {
                for (int y = -1; y <= 1; y++) {
                    float pcfDepth = shadowMap.sample(shadowSampler, projCoords.xy + float2(x, y) * texelSize);
                    shadow += currentDepth - bias > pcfDepth ? 0.4 : 1.0;
                }
            }
            return shadow / 9.0;
        }
        
        fragment float4 fragment_lit(LitVertexOut in [[stage_in]],
                                     texture2d<float> groundTex [[texture(0)]],
                                     texture2d<float> trunkTex [[texture(1)]],
                                     texture2d<float> foliageTex [[texture(2)]],
                                     texture2d<float> rockTex [[texture(3)]],
                                     texture2d<float> poleTex [[texture(4)]],
                                     depth2d<float> shadowMap [[texture(5)]],
                                     texture2d<float> characterTex [[texture(6)]],
                                     sampler texSampler [[sampler(0)]],
                                     sampler shadowSampler [[sampler(1)]],
                                     constant LitUniforms &uniforms [[buffer(1)]]) {
            // Sample texture based on material
            float4 texColor;
            switch (in.materialIndex) {
                case 0: texColor = groundTex.sample(texSampler, in.texCoord); break;
                case 1: texColor = trunkTex.sample(texSampler, in.texCoord); break;
                case 2: texColor = foliageTex.sample(texSampler, in.texCoord); break;
                case 3: texColor = rockTex.sample(texSampler, in.texCoord); break;
                case 4: texColor = poleTex.sample(texSampler, in.texCoord); break;
                case 5: texColor = characterTex.sample(texSampler, in.texCoord); break;
                default: texColor = float4(1, 0, 1, 1); break;
            }
            
            // Lighting
            float3 normal = normalize(in.normal);
            float3 lightDir = normalize(-uniforms.lightDirection);
            float NdotL = max(dot(normal, lightDir), 0.0);
            
            // Shadow
            float shadow = calculateShadow(in.lightSpacePosition, shadowMap, shadowSampler);
            
            // Final color
            float lighting = uniforms.ambientIntensity + uniforms.diffuseIntensity * NdotL * shadow;
            float3 finalColor = texColor.rgb * lighting;
            
            return float4(finalColor, texColor.a);
        }
        
        // Shadow pass vertex shader
        vertex float4 vertex_shadow(TexturedVertexIn in [[stage_in]],
                                    constant LitUniforms &uniforms [[buffer(1)]]) {
            float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
            return uniforms.lightViewProjectionMatrix * worldPos;
        }
        
        fragment void fragment_shadow() {
            // Depth-only pass, no color output
        }
        """
        
        do {
            self.library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            fatalError("Failed to create library: \(error)")
        }
        
        // Wireframe pipeline
        let wireframePipelineDesc = MTLRenderPipelineDescriptor()
        wireframePipelineDesc.vertexFunction = library.makeFunction(name: "vertex_main")
        wireframePipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_main")
        wireframePipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        wireframePipelineDesc.depthAttachmentPixelFormat = .depth32Float
        
        let wireframeVertexDesc = MTLVertexDescriptor()
        wireframeVertexDesc.attributes[0].format = .float3
        wireframeVertexDesc.attributes[0].offset = 0
        wireframeVertexDesc.attributes[0].bufferIndex = 0
        wireframeVertexDesc.attributes[1].format = .float4
        wireframeVertexDesc.attributes[1].offset = 12
        wireframeVertexDesc.attributes[1].bufferIndex = 0
        wireframeVertexDesc.layouts[0].stride = MemoryLayout<Vertex>.stride
        wireframePipelineDesc.vertexDescriptor = wireframeVertexDesc
        
        do {
            wireframePipelineState = try device.makeRenderPipelineState(descriptor: wireframePipelineDesc)
        } catch {
            fatalError("Failed to create wireframe pipeline: \(error)")
        }
        
        // Lit textured pipeline
        let litPipelineDesc = MTLRenderPipelineDescriptor()
        litPipelineDesc.vertexFunction = library.makeFunction(name: "vertex_lit")
        litPipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_lit")
        litPipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        litPipelineDesc.depthAttachmentPixelFormat = .depth32Float
        
        let litVertexDesc = MTLVertexDescriptor()
        litVertexDesc.attributes[0].format = .float3  // position
        litVertexDesc.attributes[0].offset = 0
        litVertexDesc.attributes[0].bufferIndex = 0
        litVertexDesc.attributes[1].format = .float3  // normal
        litVertexDesc.attributes[1].offset = 12
        litVertexDesc.attributes[1].bufferIndex = 0
        litVertexDesc.attributes[2].format = .float2  // texCoord
        litVertexDesc.attributes[2].offset = 24
        litVertexDesc.attributes[2].bufferIndex = 0
        litVertexDesc.attributes[3].format = .uint    // materialIndex
        litVertexDesc.attributes[3].offset = 32
        litVertexDesc.attributes[3].bufferIndex = 0
        litVertexDesc.layouts[0].stride = MemoryLayout<TexturedVertex>.stride
        litPipelineDesc.vertexDescriptor = litVertexDesc
        
        do {
            litPipelineState = try device.makeRenderPipelineState(descriptor: litPipelineDesc)
        } catch {
            fatalError("Failed to create lit pipeline: \(error)")
        }
        
        // Shadow pipeline (depth only)
        let shadowPipelineDesc = MTLRenderPipelineDescriptor()
        shadowPipelineDesc.vertexFunction = library.makeFunction(name: "vertex_shadow")
        shadowPipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_shadow")
        shadowPipelineDesc.colorAttachments[0].pixelFormat = .invalid
        shadowPipelineDesc.depthAttachmentPixelFormat = .depth32Float
        shadowPipelineDesc.vertexDescriptor = litVertexDesc
        
        do {
            shadowPipelineState = try device.makeRenderPipelineState(descriptor: shadowPipelineDesc)
        } catch {
            fatalError("Failed to create shadow pipeline: \(error)")
        }
        
        // Depth stencil states
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)!
        
        let depthDescNoWrite = MTLDepthStencilDescriptor()
        depthDescNoWrite.depthCompareFunction = .less
        depthDescNoWrite.isDepthWriteEnabled = false
        depthStencilStateNoWrite = device.makeDepthStencilState(descriptor: depthDescNoWrite)!
        
        let shadowDepthDesc = MTLDepthStencilDescriptor()
        shadowDepthDesc.depthCompareFunction = .less
        shadowDepthDesc.isDepthWriteEnabled = true
        shadowDepthStencilState = device.makeDepthStencilState(descriptor: shadowDepthDesc)!
        
        // Create texture sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        textureSampler = device.makeSamplerState(descriptor: samplerDesc)!
        
        let shadowSamplerDesc = MTLSamplerDescriptor()
        shadowSamplerDesc.minFilter = .linear
        shadowSamplerDesc.magFilter = .linear
        shadowSamplerDesc.compareFunction = .less
        shadowSampler = device.makeSamplerState(descriptor: shadowSamplerDesc)!
        
        // Create buffers and collect colliders
        var allColliders: [Collider] = []
        
        // Create character vertex buffer (large enough for animated humanoid mesh)
        characterVertexBuffer = device.makeBuffer(
            length: MemoryLayout<TexturedVertex>.stride * characterMaxVertices,
            options: .storageModeShared
        )!
        
        (gridLineBuffer, gridLineCount) = Renderer.makeGridLines(device: device)
        (groundVertexBuffer, groundVertexCount) = Renderer.makeGroundMesh(device: device)
        
        let treeResult = Renderer.makeTreeMeshes(device: device)
        treeVertexBuffer = treeResult.0
        treeVertexCount = treeResult.1
        allColliders.append(contentsOf: treeResult.2)
        
        let rockResult = Renderer.makeRockMeshes(device: device)
        rockVertexBuffer = rockResult.0
        rockVertexCount = rockResult.1
        allColliders.append(contentsOf: rockResult.2)
        
        let poleResult = Renderer.makePoleMeshes(device: device)
        poleVertexBuffer = poleResult.0
        poleVertexCount = poleResult.1
        allColliders.append(contentsOf: poleResult.2)
        
        self.colliders = allColliders
        
        uniformBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride * 3, options: [])!
        litUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: [])!
        characterUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: [])!
        
        super.init()
        
        // Create textures
        groundTexture = createGroundTexture()
        trunkTexture = createTrunkTexture()
        foliageTexture = createFoliageTexture()
        rockTexture = createRockTexture()
        poleTexture = createPoleTexture()
        characterTexture = createCharacterTexture()
        shadowMap = createShadowMap()
        
        // Initialize character mesh
        updateCharacterMesh()
        
        // Setup view
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1.0)  // Sky blue
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        
        viewportSize = view.drawableSize
        if viewportSize.width == 0 || viewportSize.height == 0 {
            viewportSize = CGSize(width: 1024, height: 768)
        }
        
        updateProjection(size: viewportSize)
        updateLightMatrix()
    }
    
    // MARK: - Texture Creation
    
    private func createGroundTexture() -> MTLTexture {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                // Grass texture with variation
                let noise = Float(((x * 13 + y * 7) % 23)) / 23.0
                let grass = 0.35 + noise * 0.15
                let variation = Float(((x * 31 + y * 17) % 37)) / 37.0 * 0.1
                
                pixels[i] = UInt8(min(255, (0.2 + variation) * 255))      // R
                pixels[i + 1] = UInt8(min(255, (grass + variation) * 255)) // G
                pixels[i + 2] = UInt8(min(255, (0.15 + variation * 0.5) * 255)) // B
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    private func createTrunkTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                // Bark texture
                let stripe = abs(sin(Float(y) * 0.5 + Float(x) * 0.1)) * 0.15
                let noise = Float((x * 7 + y * 13) % 11) / 11.0 * 0.1
                
                pixels[i] = UInt8((0.35 + stripe + noise) * 255)     // R
                pixels[i + 1] = UInt8((0.22 + stripe * 0.5 + noise) * 255) // G
                pixels[i + 2] = UInt8((0.12 + noise) * 255)          // B
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    private func createFoliageTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                // Leafy texture with clusters
                let cluster = sin(Float(x) * 0.4) * sin(Float(y) * 0.4) * 0.15
                let noise = Float((x * 17 + y * 23) % 19) / 19.0 * 0.15
                
                pixels[i] = UInt8((0.15 + noise) * 255)               // R
                pixels[i + 1] = UInt8((0.45 + cluster + noise) * 255) // G
                pixels[i + 2] = UInt8((0.18 + noise * 0.5) * 255)     // B
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    private func createRockTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                // Rocky texture with speckles
                let base: Float = 0.45
                let noise1 = Float((x * 11 + y * 7) % 13) / 13.0 * 0.15
                let noise2 = Float((x * 23 + y * 31) % 17) / 17.0 * 0.1
                let gray = base + noise1 - noise2
                
                pixels[i] = UInt8(min(255, gray * 255))
                pixels[i + 1] = UInt8(min(255, (gray - 0.02) * 255))
                pixels[i + 2] = UInt8(min(255, (gray + 0.02) * 255))
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    private func createPoleTexture() -> MTLTexture {
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                // Wooden pole with grain
                let grain = abs(sin(Float(y) * 0.8)) * 0.1
                let base: Float = 0.5
                
                pixels[i] = UInt8((base + grain + 0.1) * 255)     // R
                pixels[i + 1] = UInt8((base * 0.6 + grain) * 255) // G
                pixels[i + 2] = UInt8((base * 0.3) * 255)         // B
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    private func createCharacterTexture() -> MTLTexture {
        // Create a texture atlas for the character with different body parts
        // Layout: Top half = skin tones, Bottom half = clothes
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // UV regions:
                // y < 16: Head/face skin (warm peach)
                // y < 32: Arm skin
                // y < 48: Shirt (blue)
                // y >= 48: Pants (dark blue/denim)
                
                let noise = Float((x * 7 + y * 13) % 11) / 11.0 * 0.05
                
                if y < 16 {
                    // Face/head - warm skin tone with subtle features
                    let faceShadow = Float(x) / Float(size) * 0.1
                    pixels[i] = UInt8(min(255, (0.95 - faceShadow + noise) * 255))      // R
                    pixels[i + 1] = UInt8(min(255, (0.75 - faceShadow + noise) * 255))  // G
                    pixels[i + 2] = UInt8(min(255, (0.6 - faceShadow * 0.5) * 255))     // B
                    pixels[i + 3] = 255
                } else if y < 32 {
                    // Arms - skin tone
                    pixels[i] = UInt8(min(255, (0.9 + noise) * 255))
                    pixels[i + 1] = UInt8(min(255, (0.72 + noise) * 255))
                    pixels[i + 2] = UInt8(min(255, (0.58 + noise * 0.5) * 255))
                    pixels[i + 3] = 255
                } else if y < 48 {
                    // Shirt - nice blue with fabric texture
                    let fabric = sin(Float(x) * 0.8) * sin(Float(y) * 0.8) * 0.05
                    pixels[i] = UInt8(min(255, (0.2 + fabric + noise) * 255))
                    pixels[i + 1] = UInt8(min(255, (0.45 + fabric + noise) * 255))
                    pixels[i + 2] = UInt8(min(255, (0.75 + fabric) * 255))
                    pixels[i + 3] = 255
                } else {
                    // Pants - dark denim blue
                    let denim = abs(sin(Float(y) * 0.5 + Float(x) * 0.2)) * 0.08
                    pixels[i] = UInt8(min(255, (0.15 + denim + noise) * 255))
                    pixels[i + 1] = UInt8(min(255, (0.2 + denim + noise) * 255))
                    pixels[i + 2] = UInt8(min(255, (0.35 + denim) * 255))
                    pixels[i + 3] = 255
                }
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    private func createTexture(from pixels: [UInt8], size: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size * 4
        )
        
        // Generate mipmaps
        if let commandBuffer = commandQueue.makeCommandBuffer(),
           let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.generateMipmaps(for: texture)
            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        return texture
    }
    
    private func createShadowMap() -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: shadowMapSize,
            height: shadowMapSize,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }
    
    private func updateLightMatrix() {
        // Orthographic projection for directional light shadow map
        let lightPos = -lightDirection * 80  // Position light far from scene
        let lightTarget = simd_float3(0, 0, 0)
        let lightUp = simd_float3(0, 1, 0)
        
        let lightView = lookAt(eye: lightPos, center: lightTarget, up: lightUp)
        let lightProj = orthographicRH(left: -120, right: 120, bottom: -120, top: 120, near: 1, far: 200)
        
        lightViewProjectionMatrix = lightProj * lightView
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
        
        updateCharacter(deltaTime: dt)
        updateCamera(deltaTime: dt)
        viewMatrix = buildViewMatrix()
        
        let vp = projectionMatrix * viewMatrix
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // === SHADOW PASS ===
        let shadowPassDesc = MTLRenderPassDescriptor()
        shadowPassDesc.depthAttachment.texture = shadowMap
        shadowPassDesc.depthAttachment.loadAction = .clear
        shadowPassDesc.depthAttachment.storeAction = .store
        shadowPassDesc.depthAttachment.clearDepth = 1.0
        
        if let shadowEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPassDesc) {
            shadowEncoder.setRenderPipelineState(shadowPipelineState)
            shadowEncoder.setDepthStencilState(shadowDepthStencilState)
            shadowEncoder.setCullMode(.front)  // Reduce shadow acne
            
            // Render all solid geometry to shadow map
            var shadowUniforms = LitUniforms(
                modelMatrix: matrix_identity_float4x4,
                viewProjectionMatrix: vp,
                lightViewProjectionMatrix: lightViewProjectionMatrix,
                lightDirection: lightDirection,
                cameraPosition: cameraPosition,
                ambientIntensity: ambientIntensity,
                diffuseIntensity: diffuseIntensity
            )
            memcpy(litUniformBuffer.contents(), &shadowUniforms, MemoryLayout<LitUniforms>.stride)
            shadowEncoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
            
            // Ground
            shadowEncoder.setVertexBuffer(groundVertexBuffer, offset: 0, index: 0)
            shadowEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: groundVertexCount)
            
            // Trees
            shadowEncoder.setVertexBuffer(treeVertexBuffer, offset: 0, index: 0)
            shadowEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: treeVertexCount)
            
            // Rocks
            shadowEncoder.setVertexBuffer(rockVertexBuffer, offset: 0, index: 0)
            shadowEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: rockVertexCount)
            
            // Poles
            shadowEncoder.setVertexBuffer(poleVertexBuffer, offset: 0, index: 0)
            shadowEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: poleVertexCount)
            
            // Character (with model matrix for position/rotation)
            updateCharacterMesh()
            let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
            var charShadowUniforms = LitUniforms(
                modelMatrix: charModelMatrix,
                viewProjectionMatrix: vp,
                lightViewProjectionMatrix: lightViewProjectionMatrix,
                lightDirection: lightDirection,
                cameraPosition: cameraPosition,
                ambientIntensity: ambientIntensity,
                diffuseIntensity: diffuseIntensity
            )
            memcpy(characterUniformBuffer.contents(), &charShadowUniforms, MemoryLayout<LitUniforms>.stride)
            shadowEncoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
            shadowEncoder.setVertexBuffer(characterVertexBuffer, offset: 0, index: 0)
            shadowEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: characterVertexCount)
            
            shadowEncoder.endEncoding()
        }
        
        // === MAIN PASS ===
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: mainDescriptor) {
            encoder.setCullMode(.back)
            
            // Draw solid lit geometry
            encoder.setRenderPipelineState(litPipelineState)
            encoder.setDepthStencilState(depthStencilState)
            
            var litUniforms = LitUniforms(
                modelMatrix: matrix_identity_float4x4,
                viewProjectionMatrix: vp,
                lightViewProjectionMatrix: lightViewProjectionMatrix,
                lightDirection: lightDirection,
                cameraPosition: cameraPosition,
                ambientIntensity: ambientIntensity,
                diffuseIntensity: diffuseIntensity
            )
            memcpy(litUniformBuffer.contents(), &litUniforms, MemoryLayout<LitUniforms>.stride)
            encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
            
            // Bind textures
            encoder.setFragmentTexture(groundTexture, index: 0)
            encoder.setFragmentTexture(trunkTexture, index: 1)
            encoder.setFragmentTexture(foliageTexture, index: 2)
            encoder.setFragmentTexture(rockTexture, index: 3)
            encoder.setFragmentTexture(poleTexture, index: 4)
            encoder.setFragmentTexture(shadowMap, index: 5)
            encoder.setFragmentTexture(characterTexture, index: 6)
            encoder.setFragmentSamplerState(textureSampler, index: 0)
            encoder.setFragmentSamplerState(shadowSampler, index: 1)
            
            // Draw ground
            encoder.setVertexBuffer(groundVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: groundVertexCount)
            
            // Draw trees
            encoder.setVertexBuffer(treeVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: treeVertexCount)
            
            // Draw rocks
            encoder.setVertexBuffer(rockVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: rockVertexCount)
            
            // Draw poles
            encoder.setVertexBuffer(poleVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: poleVertexCount)
            
            // Draw 3D character with model transform (use separate buffer to avoid overwriting landscape uniforms)
            let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
            var charUniforms = LitUniforms(
                modelMatrix: charModelMatrix,
                viewProjectionMatrix: vp,
                lightViewProjectionMatrix: lightViewProjectionMatrix,
                lightDirection: lightDirection,
                cameraPosition: cameraPosition,
                ambientIntensity: ambientIntensity,
                diffuseIntensity: diffuseIntensity
            )
            memcpy(characterUniformBuffer.contents(), &charUniforms, MemoryLayout<LitUniforms>.stride)
            encoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(characterUniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(characterVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: characterVertexCount)
            
            // Draw grid lines on top (semi-transparent overlay)
            encoder.setRenderPipelineState(wireframePipelineState)
            encoder.setDepthStencilState(depthStencilStateNoWrite)
            
            var gridMVP = vp
            let matrixStride = MemoryLayout<simd_float4x4>.stride
            memcpy(uniformBuffer.contents(), &gridMVP, matrixStride)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(gridLineBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridLineCount)
            
            encoder.endEncoding()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        lastFrameTime = now
    }
    
    // MARK: - Character & Camera
    
    private func updateCharacter(deltaTime dt: Float) {
        // Target velocity based on input
        let targetVelocity = simd_float3(
            movementVector.x * characterSpeed,
            0,
            -movementVector.y * characterSpeed
        )
        
        let targetSpeed = simd_length(targetVelocity)
        isMoving = targetSpeed > 0.1
        
        // Smooth acceleration/deceleration
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
            
            // Update facing direction
            targetYaw = atan2(targetVelocity.x, targetVelocity.z)
        } else {
            // Decelerate to stop
            let currentSpeed = simd_length(characterVelocity)
            if currentSpeed > 0.01 {
                let newSpeed = max(currentSpeed - deceleration * dt, 0)
                characterVelocity = simd_normalize(characterVelocity) * newSpeed
            } else {
                characterVelocity = .zero
            }
        }
        
        // Update position
        let newPosition = characterPosition + characterVelocity * dt
        
        // Collision detection - check against all colliders
        var finalPosition = newPosition
        var collisionOccurred = false
        
        // Multiple collision resolution passes for stability
        for _ in 0..<3 {
            let charPos2D = simd_float2(finalPosition.x, finalPosition.z)
            
            for collider in colliders {
                let toChar = charPos2D - collider.position
                let distance = simd_length(toChar)
                let minDist = collider.radius + characterRadius
                
                if distance < minDist && distance > 0.001 {
                    // Push character out of collision
                    let pushDirection = simd_normalize(toChar)
                    let pushAmount = minDist - distance + 0.01  // Small buffer
                    finalPosition.x += pushDirection.x * pushAmount
                    finalPosition.z += pushDirection.y * pushAmount
                    collisionOccurred = true
                }
            }
        }
        
        // If collision occurred, reduce velocity to prevent tunneling
        if collisionOccurred {
            characterVelocity *= 0.5
        }
        
        characterPosition = finalPosition
        
        // World bounds
        characterPosition.x = max(-95, min(95, characterPosition.x))
        characterPosition.z = max(-95, min(95, characterPosition.z))
        
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
        if isMoving {
            walkPhase += simd_length(characterVelocity) * dt * walkSpeed
            while walkPhase > 2 * .pi { walkPhase -= 2 * .pi }
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
    
    // MARK: - 3D Character Mesh Animation
    
    /// Updates the 3D character mesh with walking animation
    /// Creates a humanoid figure with head, torso, arms, and legs as solid geometry
    private func updateCharacterMesh() {
        var vertices: [TexturedVertex] = []
        
        // Animation parameters
        let legSwingAmount: Float = 0.5
        let armSwingAmount: Float = 0.35
        
        let leftLegSwing = sin(walkPhase) * legSwingAmount
        let rightLegSwing = -sin(walkPhase) * legSwingAmount
        let leftArmSwing = -sin(walkPhase) * armSwingAmount
        let rightArmSwing = sin(walkPhase) * armSwingAmount
        let bodyBob = abs(sin(walkPhase * 2)) * 0.03
        
        // Material indices for different body parts (map to texture UV regions)
        // We'll use materialIndex 5 for character, but vary UV to get different textures
        let matHead: UInt32 = 5
        let matArm: UInt32 = 5
        let matTorso: UInt32 = 5
        let matLeg: UInt32 = 5
        
        // Helper to add a cylinder segment between two points
        func addLimb(from start: simd_float3, to end: simd_float3, radius: Float, segments: Int, uvYStart: Float, uvYEnd: Float, material: UInt32) {
            let direction = end - start
            let length = simd_length(direction)
            guard length > 0.001 else { return }
            
            let forward = simd_normalize(direction)
            
            // Create a perpendicular vector for the cylinder orientation
            var up = simd_float3(0, 1, 0)
            if abs(simd_dot(forward, up)) > 0.99 {
                up = simd_float3(1, 0, 0)
            }
            let right = simd_normalize(simd_cross(forward, up))
            let actualUp = simd_normalize(simd_cross(right, forward))
            
            for i in 0..<segments {
                let angle1 = Float(i) / Float(segments) * 2 * .pi
                let angle2 = Float((i + 1) % segments) / Float(segments) * 2 * .pi
                
                let offset1 = (cos(angle1) * right + sin(angle1) * actualUp) * radius
                let offset2 = (cos(angle2) * right + sin(angle2) * actualUp) * radius
                
                let n1 = simd_normalize(cos(angle1) * right + sin(angle1) * actualUp)
                let n2 = simd_normalize(cos(angle2) * right + sin(angle2) * actualUp)
                
                let bl = start + offset1
                let br = start + offset2
                let tl = end + offset1
                let tr = end + offset2
                
                let u1 = Float(i) / Float(segments)
                let u2 = Float(i + 1) / Float(segments)
                
                // First triangle
                vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, uvYEnd), materialIndex: material))
                vertices.append(TexturedVertex(position: br, normal: n2, texCoord: simd_float2(u2, uvYEnd), materialIndex: material))
                vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, uvYStart), materialIndex: material))
                
                // Second triangle
                vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, uvYEnd), materialIndex: material))
                vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, uvYStart), materialIndex: material))
                vertices.append(TexturedVertex(position: tl, normal: n1, texCoord: simd_float2(u1, uvYStart), materialIndex: material))
            }
        }
        
        // Helper to add a sphere (for head and joints)
        func addSphere(center: simd_float3, radius: Float, latSegments: Int, lonSegments: Int, uvYStart: Float, uvYEnd: Float, material: UInt32) {
            for lat in 0..<latSegments {
                let theta1 = Float(lat) / Float(latSegments) * .pi
                let theta2 = Float(lat + 1) / Float(latSegments) * .pi
                
                for lon in 0..<lonSegments {
                    let phi1 = Float(lon) / Float(lonSegments) * 2 * .pi
                    let phi2 = Float(lon + 1) / Float(lonSegments) * 2 * .pi
                    
                    let p1 = center + radius * simd_float3(
                        sin(theta1) * cos(phi1),
                        cos(theta1),
                        sin(theta1) * sin(phi1)
                    )
                    let p2 = center + radius * simd_float3(
                        sin(theta1) * cos(phi2),
                        cos(theta1),
                        sin(theta1) * sin(phi2)
                    )
                    let p3 = center + radius * simd_float3(
                        sin(theta2) * cos(phi2),
                        cos(theta2),
                        sin(theta2) * sin(phi2)
                    )
                    let p4 = center + radius * simd_float3(
                        sin(theta2) * cos(phi1),
                        cos(theta2),
                        sin(theta2) * sin(phi1)
                    )
                    
                    let n1 = simd_normalize(p1 - center)
                    let n2 = simd_normalize(p2 - center)
                    let n3 = simd_normalize(p3 - center)
                    let n4 = simd_normalize(p4 - center)
                    
                    let u1 = Float(lon) / Float(lonSegments)
                    let u2 = Float(lon + 1) / Float(lonSegments)
                    let v1 = uvYStart + (uvYEnd - uvYStart) * Float(lat) / Float(latSegments)
                    let v2 = uvYStart + (uvYEnd - uvYStart) * Float(lat + 1) / Float(latSegments)
                    
                    // Two triangles per quad
                    vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: material))
                    vertices.append(TexturedVertex(position: p2, normal: n2, texCoord: simd_float2(u2, v1), materialIndex: material))
                    vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: material))
                    
                    vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: material))
                    vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: material))
                    vertices.append(TexturedVertex(position: p4, normal: n4, texCoord: simd_float2(u1, v2), materialIndex: material))
                }
            }
        }
        
        // Helper to add a box (for torso)
        func addBox(center: simd_float3, size: simd_float3, uvYStart: Float, uvYEnd: Float, material: UInt32) {
            let hw = size.x / 2
            let hh = size.y / 2
            let hd = size.z / 2
            
            // Front face
            let frontNormal = simd_float3(0, 0, 1)
            let frontBL = center + simd_float3(-hw, -hh, hd)
            let frontBR = center + simd_float3(hw, -hh, hd)
            let frontTL = center + simd_float3(-hw, hh, hd)
            let frontTR = center + simd_float3(hw, hh, hd)
            vertices.append(TexturedVertex(position: frontBL, normal: frontNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: frontBR, normal: frontNormal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: frontTR, normal: frontNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: frontBL, normal: frontNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: frontTR, normal: frontNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: frontTL, normal: frontNormal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
            
            // Back face
            let backNormal = simd_float3(0, 0, -1)
            let backBL = center + simd_float3(hw, -hh, -hd)
            let backBR = center + simd_float3(-hw, -hh, -hd)
            let backTL = center + simd_float3(hw, hh, -hd)
            let backTR = center + simd_float3(-hw, hh, -hd)
            vertices.append(TexturedVertex(position: backBL, normal: backNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: backBR, normal: backNormal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: backTR, normal: backNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: backBL, normal: backNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: backTR, normal: backNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: backTL, normal: backNormal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
            
            // Left face
            let leftNormal = simd_float3(-1, 0, 0)
            let leftBL = center + simd_float3(-hw, -hh, -hd)
            let leftBR = center + simd_float3(-hw, -hh, hd)
            let leftTL = center + simd_float3(-hw, hh, -hd)
            let leftTR = center + simd_float3(-hw, hh, hd)
            vertices.append(TexturedVertex(position: leftBL, normal: leftNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: leftBR, normal: leftNormal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: leftTR, normal: leftNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: leftBL, normal: leftNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: leftTR, normal: leftNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: leftTL, normal: leftNormal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
            
            // Right face
            let rightNormal = simd_float3(1, 0, 0)
            let rightBL = center + simd_float3(hw, -hh, hd)
            let rightBR = center + simd_float3(hw, -hh, -hd)
            let rightTL = center + simd_float3(hw, hh, hd)
            let rightTR = center + simd_float3(hw, hh, -hd)
            vertices.append(TexturedVertex(position: rightBL, normal: rightNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: rightBR, normal: rightNormal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: rightTR, normal: rightNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: rightBL, normal: rightNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: rightTR, normal: rightNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: rightTL, normal: rightNormal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
            
            // Top face
            let topNormal = simd_float3(0, 1, 0)
            let topBL = center + simd_float3(-hw, hh, hd)
            let topBR = center + simd_float3(hw, hh, hd)
            let topTL = center + simd_float3(-hw, hh, -hd)
            let topTR = center + simd_float3(hw, hh, -hd)
            vertices.append(TexturedVertex(position: topBL, normal: topNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: topBR, normal: topNormal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: topTR, normal: topNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: topBL, normal: topNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: topTR, normal: topNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: topTL, normal: topNormal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
            
            // Bottom face
            let bottomNormal = simd_float3(0, -1, 0)
            let bottomBL = center + simd_float3(-hw, -hh, -hd)
            let bottomBR = center + simd_float3(hw, -hh, -hd)
            let bottomTL = center + simd_float3(-hw, -hh, hd)
            let bottomTR = center + simd_float3(hw, -hh, hd)
            vertices.append(TexturedVertex(position: bottomBL, normal: bottomNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: bottomBR, normal: bottomNormal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: bottomTR, normal: bottomNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: bottomBL, normal: bottomNormal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: bottomTR, normal: bottomNormal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: bottomTL, normal: bottomNormal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
        }
        
        // Character dimensions
        let hipY: Float = 0.85 + bodyBob
        let shoulderY: Float = 1.45 + bodyBob
        let neckY: Float = 1.55 + bodyBob
        let headY: Float = 1.75 + bodyBob
        
        // HEAD (sphere) - UV 0.0-0.25
        addSphere(center: simd_float3(0, headY, 0), radius: 0.22, latSegments: 8, lonSegments: 12, uvYStart: 0.0, uvYEnd: 0.25, material: matHead)
        
        // NECK (small cylinder)
        addLimb(from: simd_float3(0, shoulderY, 0), to: simd_float3(0, neckY, 0), radius: 0.08, segments: 6, uvYStart: 0.0, uvYEnd: 0.25, material: matHead)
        
        // TORSO (box) - UV 0.5-0.75 for shirt
        addBox(center: simd_float3(0, (hipY + shoulderY) / 2, 0), size: simd_float3(0.4, shoulderY - hipY, 0.22), uvYStart: 0.5, uvYEnd: 0.75, material: matTorso)
        
        // ARMS with animation
        let shoulderWidth: Float = 0.25
        
        // Left arm
        let leftShoulderPos = simd_float3(-shoulderWidth, shoulderY - 0.05, 0)
        let leftElbowPos = simd_float3(-shoulderWidth - 0.08, shoulderY - 0.35, leftArmSwing * 0.3)
        let leftHandPos = simd_float3(-shoulderWidth - 0.05, shoulderY - 0.65, leftArmSwing * 0.5)
        
        addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6, uvYStart: 0.25, uvYEnd: 0.5, material: matArm)
        addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6, uvYStart: 0.25, uvYEnd: 0.5, material: matArm)
        addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6, uvYStart: 0.25, uvYEnd: 0.5, material: matArm)
        
        // Right arm
        let rightShoulderPos = simd_float3(shoulderWidth, shoulderY - 0.05, 0)
        let rightElbowPos = simd_float3(shoulderWidth + 0.08, shoulderY - 0.35, rightArmSwing * 0.3)
        let rightHandPos = simd_float3(shoulderWidth + 0.05, shoulderY - 0.65, rightArmSwing * 0.5)
        
        addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6, uvYStart: 0.25, uvYEnd: 0.5, material: matArm)
        addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6, uvYStart: 0.25, uvYEnd: 0.5, material: matArm)
        addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6, uvYStart: 0.25, uvYEnd: 0.5, material: matArm)
        
        // LEGS with walking animation - UV 0.75-1.0 for pants
        let legSeparation: Float = 0.12
        
        // Left leg
        let leftHipPos = simd_float3(-legSeparation, hipY, 0)
        let leftKneeHeight = 0.45 + max(0, sin(walkPhase)) * 0.08
        let leftKneePos = simd_float3(-legSeparation, leftKneeHeight, leftLegSwing * 0.4)
        let leftFootHeight: Float = 0.08 + max(0, sin(walkPhase)) * 0.12
        let leftFootPos = simd_float3(-legSeparation, leftFootHeight, leftLegSwing * 0.6)
        
        addLimb(from: leftHipPos, to: leftKneePos, radius: 0.09, segments: 6, uvYStart: 0.75, uvYEnd: 1.0, material: matLeg)
        addLimb(from: leftKneePos, to: leftFootPos, radius: 0.07, segments: 6, uvYStart: 0.75, uvYEnd: 1.0, material: matLeg)
        // Foot (small box)
        addBox(center: leftFootPos + simd_float3(0, -0.03, 0.05), size: simd_float3(0.1, 0.06, 0.18), uvYStart: 0.75, uvYEnd: 1.0, material: matLeg)
        
        // Right leg
        let rightHipPos = simd_float3(legSeparation, hipY, 0)
        let rightKneeHeight = 0.45 + max(0, -sin(walkPhase)) * 0.08
        let rightKneePos = simd_float3(legSeparation, rightKneeHeight, rightLegSwing * 0.4)
        let rightFootHeight: Float = 0.08 + max(0, -sin(walkPhase)) * 0.12
        let rightFootPos = simd_float3(legSeparation, rightFootHeight, rightLegSwing * 0.6)
        
        addLimb(from: rightHipPos, to: rightKneePos, radius: 0.09, segments: 6, uvYStart: 0.75, uvYEnd: 1.0, material: matLeg)
        addLimb(from: rightKneePos, to: rightFootPos, radius: 0.07, segments: 6, uvYStart: 0.75, uvYEnd: 1.0, material: matLeg)
        // Foot
        addBox(center: rightFootPos + simd_float3(0, -0.03, 0.05), size: simd_float3(0.1, 0.06, 0.18), uvYStart: 0.75, uvYEnd: 1.0, material: matLeg)
        
        // Update buffer
        characterVertexCount = vertices.count
        vertices.withUnsafeBytes { ptr in
            memcpy(characterVertexBuffer.contents(), ptr.baseAddress!, ptr.count)
        }
    }
    
    // MARK: - Geometry Generation
    
    private static func makeGridLines(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [Vertex] = []
        let gridMin: Float = -100
        let gridMax: Float = 100
        let majorColor = simd_float4(0.3, 0.35, 0.25, 0.6)
        let minorColor = simd_float4(0.25, 0.3, 0.2, 0.4)
        
        var i: Float = gridMin
        while i <= gridMax {
            let isMajor = Int(i) % 10 == 0
            let color = isMajor ? majorColor : minorColor
            let y: Float = 0.01  // Slightly above ground
            
            vertices.append(Vertex(position: simd_float3(gridMin, y, i), color: color))
            vertices.append(Vertex(position: simd_float3(gridMax, y, i), color: color))
            vertices.append(Vertex(position: simd_float3(i, y, gridMin), color: color))
            vertices.append(Vertex(position: simd_float3(i, y, gridMax), color: color))
            i += 5
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count)
    }
    
    private static func makeGroundMesh(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [TexturedVertex] = []
        let size: Float = 100
        let normal = simd_float3(0, 1, 0)
        let texScale: Float = 20  // Repeat texture
        
        // Two triangles for ground quad
        let corners = [
            (simd_float3(-size, 0, -size), simd_float2(0, 0)),
            (simd_float3( size, 0, -size), simd_float2(texScale, 0)),
            (simd_float3( size, 0,  size), simd_float2(texScale, texScale)),
            (simd_float3(-size, 0,  size), simd_float2(0, texScale))
        ]
        
        // Triangle 1
        vertices.append(TexturedVertex(position: corners[0].0, normal: normal, texCoord: corners[0].1, materialIndex: 0))
        vertices.append(TexturedVertex(position: corners[1].0, normal: normal, texCoord: corners[1].1, materialIndex: 0))
        vertices.append(TexturedVertex(position: corners[2].0, normal: normal, texCoord: corners[2].1, materialIndex: 0))
        // Triangle 2
        vertices.append(TexturedVertex(position: corners[0].0, normal: normal, texCoord: corners[0].1, materialIndex: 0))
        vertices.append(TexturedVertex(position: corners[2].0, normal: normal, texCoord: corners[2].1, materialIndex: 0))
        vertices.append(TexturedVertex(position: corners[3].0, normal: normal, texCoord: corners[3].1, materialIndex: 0))
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count)
    }
    
    private static func makeTreeMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        func seededRandom(_ seed: Int) -> Float {
            let x = sin(Float(seed) * 12.9898 + Float(seed) * 78.233) * 43758.5453
            return x - floor(x)
        }
        
        func addCylinder(at pos: simd_float3, radius: Float, height: Float, segments: Int, material: UInt32) {
            for i in 0..<segments {
                let angle1 = Float(i) / Float(segments) * 2 * .pi
                let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
                
                let x1 = cos(angle1) * radius
                let z1 = sin(angle1) * radius
                let x2 = cos(angle2) * radius
                let z2 = sin(angle2) * radius
                
                let n1 = simd_normalize(simd_float3(cos(angle1), 0, sin(angle1)))
                let n2 = simd_normalize(simd_float3(cos(angle2), 0, sin(angle2)))
                
                let u1 = Float(i) / Float(segments)
                let u2 = Float(i + 1) / Float(segments)
                
                let bl = pos + simd_float3(x1, 0, z1)
                let br = pos + simd_float3(x2, 0, z2)
                let tl = pos + simd_float3(x1, height, z1)
                let tr = pos + simd_float3(x2, height, z2)
                
                vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, 1), materialIndex: material))
                vertices.append(TexturedVertex(position: br, normal: n2, texCoord: simd_float2(u2, 1), materialIndex: material))
                vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, 0), materialIndex: material))
                
                vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, 1), materialIndex: material))
                vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, 0), materialIndex: material))
                vertices.append(TexturedVertex(position: tl, normal: n1, texCoord: simd_float2(u1, 0), materialIndex: material))
            }
        }
        
        func addCone(at pos: simd_float3, radius: Float, height: Float, segments: Int, material: UInt32) {
            let apex = pos + simd_float3(0, height, 0)
            
            for i in 0..<segments {
                let angle1 = Float(i) / Float(segments) * 2 * .pi
                let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
                
                let x1 = cos(angle1) * radius
                let z1 = sin(angle1) * radius
                let x2 = cos(angle2) * radius
                let z2 = sin(angle2) * radius
                
                let p1 = pos + simd_float3(x1, 0, z1)
                let p2 = pos + simd_float3(x2, 0, z2)
                
                // Calculate face normal
                let edge1 = p2 - p1
                let edge2 = apex - p1
                let normal = simd_normalize(simd_cross(edge1, edge2))
                
                let u1 = Float(i) / Float(segments)
                let u2 = Float(i + 1) / Float(segments)
                
                vertices.append(TexturedVertex(position: p1, normal: normal, texCoord: simd_float2(u1, 1), materialIndex: material))
                vertices.append(TexturedVertex(position: p2, normal: normal, texCoord: simd_float2(u2, 1), materialIndex: material))
                vertices.append(TexturedVertex(position: apex, normal: normal, texCoord: simd_float2((u1 + u2) / 2, 0), materialIndex: material))
            }
        }
        
        func addTree(at pos: simd_float3, height: Float, radius: Float) {
            let trunkHeight = height * 0.35
            let trunkRadius = radius * 0.12
            
            addCylinder(at: pos, radius: trunkRadius, height: trunkHeight, segments: 8, material: 1)
            
            // Three cone layers for foliage
            let layerHeights: [Float] = [trunkHeight * 0.8, trunkHeight + height * 0.2, trunkHeight + height * 0.4]
            let layerRadii: [Float] = [radius, radius * 0.7, radius * 0.4]
            let coneHeights: [Float] = [height * 0.35, height * 0.3, height * 0.3]
            
            for i in 0..<3 {
                addCone(at: pos + simd_float3(0, layerHeights[i], 0), radius: layerRadii[i], height: coneHeights[i], segments: 8, material: 2)
            }
            
            // Add collision for tree trunk (use trunk radius + small buffer)
            colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: trunkRadius + 0.2))
        }
        
        var seed = 1
        for gridX in stride(from: -90, through: 90, by: 12) {
            for gridZ in stride(from: -90, through: 90, by: 12) {
                if abs(gridX) < 8 && abs(gridZ) < 8 { seed += 5; continue }
                
                let offsetX = (seededRandom(seed) - 0.5) * 10
                let offsetZ = (seededRandom(seed + 1) - 0.5) * 10
                let height = 3.5 + seededRandom(seed + 2) * 3.0
                let radius = 1.0 + seededRandom(seed + 3) * 1.0
                
                if seededRandom(seed + 4) < 0.7 {
                    addTree(at: simd_float3(Float(gridX) + offsetX, 0, Float(gridZ) + offsetZ), height: height, radius: radius)
                }
                seed += 5
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func makeRockMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        func seededRandom(_ seed: Int) -> Float {
            let x = sin(Float(seed) * 12.9898 + Float(seed) * 78.233) * 43758.5453
            return x - floor(x)
        }
        
        func addRock(at pos: simd_float3, size: Float) {
            let s = size
            let h = size * 1.2
            
            // Irregular rock vertices
            let corners: [simd_float3] = [
                pos + simd_float3(-s * 0.9, 0, -s * 0.8),
                pos + simd_float3(s * 0.85, 0, -s * 0.95),
                pos + simd_float3(s * 0.9, 0, s * 0.75),
                pos + simd_float3(-s * 0.75, 0, s * 0.9),
                pos + simd_float3(-s * 0.5, h * 0.9, -s * 0.4),
                pos + simd_float3(s * 0.45, h, -s * 0.5),
                pos + simd_float3(s * 0.5, h * 0.85, s * 0.35),
                pos + simd_float3(-s * 0.4, h * 0.8, s * 0.45)
            ]
            
            // Define faces (as triangles)
            let faces: [(Int, Int, Int)] = [
                // Bottom
                (0, 2, 1), (0, 3, 2),
                // Top
                (4, 5, 6), (4, 6, 7),
                // Sides
                (0, 1, 5), (0, 5, 4),
                (1, 2, 6), (1, 6, 5),
                (2, 3, 7), (2, 7, 6),
                (3, 0, 4), (3, 4, 7)
            ]
            
            for (a, b, c) in faces {
                let edge1 = corners[b] - corners[a]
                let edge2 = corners[c] - corners[a]
                let normal = simd_normalize(simd_cross(edge1, edge2))
                
                vertices.append(TexturedVertex(position: corners[a], normal: normal, texCoord: simd_float2(0, 0), materialIndex: 3))
                vertices.append(TexturedVertex(position: corners[b], normal: normal, texCoord: simd_float2(1, 0), materialIndex: 3))
                vertices.append(TexturedVertex(position: corners[c], normal: normal, texCoord: simd_float2(0.5, 1), materialIndex: 3))
            }
            
            // Add collision for rock (use size as radius)
            colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: s))
        }
        
        var seed = 1000
        for gridX in stride(from: -85, through: 85, by: 18) {
            for gridZ in stride(from: -85, through: 85, by: 18) {
                if abs(gridX) < 10 && abs(gridZ) < 10 { seed += 4; continue }
                
                let offsetX = (seededRandom(seed) - 0.5) * 12
                let offsetZ = (seededRandom(seed + 1) - 0.5) * 12
                let size = 0.6 + seededRandom(seed + 2) * 0.8
                
                let chance = seededRandom(seed + 3)
                if chance < 0.5 {
                    addRock(at: simd_float3(Float(gridX) + offsetX, 0, Float(gridZ) + offsetZ), size: size)
                    // Add cluster
                    if chance < 0.25 {
                        addRock(at: simd_float3(Float(gridX) + offsetX + size * 1.2, 0, Float(gridZ) + offsetZ + size * 0.3), size: size * 0.7)
                        addRock(at: simd_float3(Float(gridX) + offsetX - size * 0.4, 0, Float(gridZ) + offsetZ + size * 1.0), size: size * 0.5)
                    }
                }
                seed += 4
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func makePoleMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        func addPole(at pos: simd_float3, height: Float, radius: Float = 0.15) {
            let segments = 6
            for i in 0..<segments {
                let angle1 = Float(i) / Float(segments) * 2 * .pi
                let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
                
                let x1 = cos(angle1) * radius
                let z1 = sin(angle1) * radius
                let x2 = cos(angle2) * radius
                let z2 = sin(angle2) * radius
                
                let n1 = simd_normalize(simd_float3(cos(angle1), 0, sin(angle1)))
                let n2 = simd_normalize(simd_float3(cos(angle2), 0, sin(angle2)))
                
                let bl = pos + simd_float3(x1, 0, z1)
                let br = pos + simd_float3(x2, 0, z2)
                let tl = pos + simd_float3(x1, height, z1)
                let tr = pos + simd_float3(x2, height, z2)
                
                vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(0, 1), materialIndex: 4))
                vertices.append(TexturedVertex(position: br, normal: n2, texCoord: simd_float2(1, 1), materialIndex: 4))
                vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(1, 0), materialIndex: 4))
                
                vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(0, 1), materialIndex: 4))
                vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(1, 0), materialIndex: 4))
                vertices.append(TexturedVertex(position: tl, normal: n1, texCoord: simd_float2(0, 0), materialIndex: 4))
            }
            
            // Top cap
            let topCenter = pos + simd_float3(0, height, 0)
            let topNormal = simd_float3(0, 1, 0)
            for i in 0..<segments {
                let angle1 = Float(i) / Float(segments) * 2 * .pi
                let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
                
                let p1 = pos + simd_float3(cos(angle1) * radius, height, sin(angle1) * radius)
                let p2 = pos + simd_float3(cos(angle2) * radius, height, sin(angle2) * radius)
                
                vertices.append(TexturedVertex(position: topCenter, normal: topNormal, texCoord: simd_float2(0.5, 0.5), materialIndex: 4))
                vertices.append(TexturedVertex(position: p1, normal: topNormal, texCoord: simd_float2(0, 0), materialIndex: 4))
                vertices.append(TexturedVertex(position: p2, normal: topNormal, texCoord: simd_float2(1, 0), materialIndex: 4))
            }
            
            // Add collision for pole
            colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: radius + 0.1))
        }
        
        // Corner posts
        addPole(at: simd_float3(0, 0, 0), height: 5.0, radius: 0.2)
        addPole(at: simd_float3(-95, 0, -95), height: 4.0)
        addPole(at: simd_float3(95, 0, -95), height: 4.0)
        addPole(at: simd_float3(-95, 0, 95), height: 4.0)
        addPole(at: simd_float3(95, 0, 95), height: 4.0)
        
        // Edge posts
        for i in stride(from: -50, through: 50, by: 50) {
            if i != 0 {
                addPole(at: simd_float3(Float(i), 0, -95), height: 3.0)
                addPole(at: simd_float3(Float(i), 0, 95), height: 3.0)
                addPole(at: simd_float3(-95, 0, Float(i)), height: 3.0)
                addPole(at: simd_float3(95, 0, Float(i)), height: 3.0)
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
}

// MARK: - Math Helpers

func perspectiveFovRH(fovYRadians fovY: Float, aspectRatio aspect: Float, nearZ near: Float, farZ far: Float) -> simd_float4x4 {
    let yScale = 1 / tan(fovY * 0.5)
    let xScale = yScale / aspect
    let zRange = far - near
    let zScale = -(far + near) / zRange
    let wzScale = -2 * far * near / zRange
    
    return simd_float4x4(
        simd_float4(xScale, 0, 0, 0),
        simd_float4(0, yScale, 0, 0),
        simd_float4(0, 0, zScale, -1),
        simd_float4(0, 0, wzScale, 0)
    )
}

func lookAt(eye: simd_float3, center: simd_float3, up: simd_float3) -> simd_float4x4 {
    let z = simd_normalize(eye - center)
    let x = simd_normalize(simd_cross(up, z))
    let y = simd_cross(z, x)
    
    return simd_float4x4(columns: (
        simd_float4(x.x, y.x, z.x, 0),
        simd_float4(x.y, y.y, z.y, 0),
        simd_float4(x.z, y.z, z.z, 0),
        simd_float4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
    ))
}

func rotationY(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4(c, 0, s, 0),
        simd_float4(0, 1, 0, 0),
        simd_float4(-s, 0, c, 0),
        simd_float4(0, 0, 0, 1)
    )
}

func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        simd_float4(1, 0, 0, 0),
        simd_float4(0, 1, 0, 0),
        simd_float4(0, 0, 1, 0),
        simd_float4(x, y, z, 1)
    )
}

func orthographicRH(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
    let rml = right - left
    let tmb = top - bottom
    let fmn = far - near
    return simd_float4x4(
        simd_float4(2.0 / rml, 0, 0, 0),
        simd_float4(0, 2.0 / tmb, 0, 0),
        simd_float4(0, 0, -1.0 / fmn, 0),
        simd_float4(-(right + left) / rml, -(top + bottom) / tmb, -near / fmn, 1)
    )
}
