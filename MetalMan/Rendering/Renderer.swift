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
    private var treasureChestTexture: MTLTexture!
    private var shadowMap: MTLTexture!
    private let shadowMapSize: Int = 2048
    
    // MARK: - Interactables
    
    private var interactables: [Interactable] = []
    private var chestVertexBuffer: MTLBuffer!
    private var chestVertexCount: Int = 0
    private var chestsNeedRebuild: Bool = false
    
    // MARK: - Enemies
    
    private var enemyTexture: MTLTexture!
    private var enemyManager: EnemyManager!
    private var enemyMesh: EnemyMesh!
    
    // MARK: - Textures (Normal Maps)
    
    private var groundNormalMap: MTLTexture!
    private var trunkNormalMap: MTLTexture!
    private var rockNormalMap: MTLTexture!
    private var pathNormalMap: MTLTexture!
    
    // MARK: - Input
    
    var movementVector: simd_float2 = .zero
    var lookDelta: simd_float2 = .zero
    var jumpPressed: Bool = false
    var interactPressed: Bool = false
    var attackPressed: Bool = false
    
    // MARK: - Combat State
    
    private var isAttacking: Bool = false
    private var attackPhase: Float = 0        // 0 to 1, progress through swing
    private var attackCooldown: Float = 0     // Time until next attack allowed
    private let attackDuration: Float = 0.4   // How long the swing takes
    private let attackCooldownTime: Float = 0.3  // Time between attacks
    private var attackWasPressed: Bool = false
    private var currentSwingType: SwingType = .mittelhaw
    
    // MARK: - HUD Reference
    
    weak var hudViewModel: GameHUDViewModel?
    private var interactWasPressed: Bool = false
    
    // MARK: - RPG Player
    
    /// The player character with stats, inventory, and equipment
    let player: PlayerCharacter
    
    // MARK: - Character State
    
    private var characterPosition: simd_float3 = .zero
    private var characterVelocity: simd_float3 = .zero
    private var characterYaw: Float = 0  // Direction character is facing (controlled by left/right)
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
    
    // Movement config (base values, modified by player stats)
    private let baseCharacterSpeed: Float = 6.0
    private let acceleration: Float = 40.0
    private let deceleration: Float = 25.0
    private let turnSpeed: Float = 15.0
    
    /// Effective character speed modified by player dexterity
    private var characterSpeed: Float {
        baseCharacterSpeed * player.speedModifier
    }
    
    // MARK: - Camera & Lighting
    
    private var cameraPosition: simd_float3 = simd_float3(0, 8, 10)
    private let cameraHeight: Float = 4.0    // Height above character
    private let cameraDistance: Float = 8.0  // Distance behind character
    
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
    private var enemyUniformBuffer: MTLBuffer  // Large buffer for all enemies
    
    // Collision
    private var colliders: [Collider] = []
    private let characterRadius: Float = 0.3
    
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    
    // MARK: - Init
    
    init(device: MTLDevice, view: MTKView) {
        self.device = device
        
        // Initialize player character
        self.player = PlayerCharacter(
            name: "Hero",
            attributes: CharacterAttributes(strength: 10, dexterity: 12, intelligence: 8),
            maxHP: 100,
            inventoryCapacity: 20
        )
        
        // Give starter items
        player.inventory.addItem(ItemTemplates.healthPotion(size: .common), quantity: 3)
        player.inventory.addGold(50)
        
        // Equip starting sword
        player.equipment.equip(ItemTemplates.sword(rarity: .common))
        
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
        
        // 5. Create treasure chests
        self.interactables = Renderer.createTreasureChests()
        let chestResult = GeometryGenerator.makeTreasureChestMeshes(device: device, interactables: interactables)
        chestVertexBuffer = chestResult.0
        chestVertexCount = chestResult.1
        allColliders.append(contentsOf: chestResult.2)
        
        self.colliders = allColliders
        
        // Create character mesh
        self.characterMesh = CharacterMesh(device: device)
        
        // Create enemy mesh and manager
        self.enemyMesh = EnemyMesh(device: device)
        self.enemyManager = EnemyManager()
        
        // Create uniform buffers with shared storage mode for CPU/GPU access
        uniformBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride * 3, options: .storageModeShared)!
        litUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: .storageModeShared)!
        characterUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: .storageModeShared)!
        skyboxUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: .storageModeShared)!
        // Enemy uniform buffer - large enough for 100 enemies with proper alignment
        let uniformStride = (MemoryLayout<LitUniforms>.stride + 255) & ~255  // 256-byte aligned
        enemyUniformBuffer = device.makeBuffer(length: uniformStride * 100, options: .storageModeShared)!
        
        super.init()
        
        // Spawn enemies (higher chance near treasure chests)
        // Must be after super.init() to call instance method
        spawnEnemies(nearChests: self.interactables)
        
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
        treasureChestTexture = textureGen.createTreasureChestTexture()
        enemyTexture = textureGen.createEnemyTexture()
        shadowMap = textureGen.createShadowMap(size: shadowMapSize)
        
        // Normal maps
        groundNormalMap = textureGen.createGroundNormalMap()
        trunkNormalMap = textureGen.createTrunkNormalMap()
        rockNormalMap = textureGen.createRockNormalMap()
        pathNormalMap = textureGen.createPathNormalMap()
        
        // Initialize character mesh
        characterMesh.update(walkPhase: walkPhase, isJumping: isJumping, 
                            hasSwordEquipped: player.equipment.hasSwordEquipped,
                            isAttacking: isAttacking, attackPhase: attackPhase,
                            swingType: currentSwingType)
        
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
    
    // MARK: - Treasure Chests
    
    /// Create treasure chests at interesting locations
    private static func createTreasureChests() -> [Interactable] {
        var chests: [Interactable] = []
        
        // Predefined chest locations (avoiding spawn area and paths)
        let chestLocations: [(x: Float, z: Float)] = [
            (15, 20),    // Near first house
            (-25, 15),   // Near second house
            (35, -30),   // Near third house
            (-40, -35),  // In the ruins
            (50, 45),    // In the second ruins
            (-55, 55),   // Near the watchtower
            (70, 10),    // Far east
            (-70, -20),  // Far west
            (20, -60),   // South area
            (-30, 70),   // North area
        ]
        
        var seed = 42
        for (x, z) in chestLocations {
            let terrainY = Terrain.heightAt(x: x, z: z)
            var chest = Interactable(type: .treasureChest, position: simd_float3(x, terrainY, z))
            
            // Random loot
            let lootRoll = seededRandom(seed)
            seed += 1
            
            if lootRoll < 0.4 {
                // Gold only (40% chance)
                chest.goldAmount = 10 + Int(seededRandom(seed) * 40)
                seed += 1
            } else if lootRoll < 0.7 {
                // Gold + common item (30% chance)
                chest.goldAmount = 5 + Int(seededRandom(seed) * 20)
                seed += 1
                
                let itemRoll = seededRandom(seed)
                seed += 1
                if itemRoll < 0.5 {
                    chest.containedItem = ItemTemplates.healthPotion(size: .common)
                } else {
                    chest.containedItem = ItemTemplates.sword(rarity: .common)
                }
            } else if lootRoll < 0.9 {
                // Uncommon item (20% chance)
                chest.goldAmount = 15 + Int(seededRandom(seed) * 30)
                seed += 1
                
                let itemRoll = seededRandom(seed)
                seed += 1
                if itemRoll < 0.3 {
                    chest.containedItem = ItemTemplates.healthPotion(size: .uncommon)
                } else if itemRoll < 0.6 {
                    chest.containedItem = ItemTemplates.sword(rarity: .uncommon)
                } else {
                    chest.containedItem = ItemTemplates.chestplate(rarity: .common)
                }
            } else {
                // Rare item (10% chance)
                chest.goldAmount = 30 + Int(seededRandom(seed) * 50)
                seed += 1
                
                let itemRoll = seededRandom(seed)
                seed += 1
                if itemRoll < 0.4 {
                    chest.containedItem = ItemTemplates.sword(rarity: .rare)
                } else if itemRoll < 0.7 {
                    chest.containedItem = ItemTemplates.chestplate(rarity: .uncommon)
                } else {
                    chest.containedItem = ItemTemplates.boots(rarity: .rare)
                }
            }
            
            chests.append(chest)
        }
        
        return chests
    }
    
    /// Spawn enemies throughout the world, with higher density near treasure chests
    private func spawnEnemies(nearChests chests: [Interactable]) {
        var seed = 1337
        
        // 1. Spawn 1-2 bandits near each chest (70% chance per chest)
        for chest in chests {
            let chanceRoll = seededRandom(seed)
            seed += 1
            
            if chanceRoll < 0.7 {
                // Spawn 1-2 enemies near this chest
                let enemyCount = chanceRoll < 0.3 ? 2 : 1
                
                for _ in 0..<enemyCount {
                    // Random offset from chest (5-12 units away)
                    let angle = seededRandom(seed) * 2 * .pi
                    seed += 1
                    let distance: Float = 5.0 + seededRandom(seed) * 7.0
                    seed += 1
                    
                    let x = chest.position.x + cos(angle) * distance
                    let z = chest.position.z + sin(angle) * distance
                    let y = Terrain.heightAt(x: x, z: z)
                    
                    // Don't spawn too close to origin (player spawn)
                    let distFromOrigin = sqrtf(x * x + z * z)
                    if distFromOrigin > 15 {
                        enemyManager.spawnEnemy(type: .bandit, at: simd_float3(x, y, z))
                    }
                }
            }
        }
        
        // 2. Spawn additional random bandits throughout the world
        let randomEnemyCount = 15
        for _ in 0..<randomEnemyCount {
            let x: Float = (seededRandom(seed) - 0.5) * 160  // -80 to 80
            seed += 1
            let z: Float = (seededRandom(seed) - 0.5) * 160
            seed += 1
            
            // Skip if too close to origin
            let distFromOrigin = sqrtf(x * x + z * z)
            if distFromOrigin < 20 { continue }
            
            let y = Terrain.heightAt(x: x, z: z)
            enemyManager.spawnEnemy(type: .bandit, at: simd_float3(x, y, z))
        }
        
        print("[Enemies] Spawned \(enemyManager.count) bandits")
    }
    
    /// Try to interact with nearby chests or corpses
    func tryInteract() {
        // Check for treasure chests first
        for i in 0..<interactables.count {
            if interactables[i].canInteract(playerPosition: characterPosition) {
                openChest(at: i)
                return
            }
        }
        
        // Check for lootable corpses
        if let corpse = enemyManager.findLootableCorpse(near: characterPosition) {
            lootCorpse(corpse)
        }
    }
    
    /// Loot a dead enemy's corpse
    private func lootCorpse(_ enemy: Enemy) {
        guard !enemy.isLooted else { return }
        
        enemy.isLooted = true
        
        // Collect gold
        if enemy.lootGold > 0 {
            player.inventory.addGold(enemy.lootGold)
        }
        
        // Collect items
        var itemName: String? = nil
        var itemRarity: String? = nil
        
        for item in enemy.lootItems {
            player.inventory.addItem(item)
            itemName = item.name
            itemRarity = item.rarity.name
        }
        
        // Show loot notification
        if enemy.lootGold > 0 || !enemy.lootItems.isEmpty {
            hudViewModel?.showLoot(gold: enemy.lootGold, itemName: itemName, itemRarity: itemRarity, title: "💀 Looted \(enemy.type.rawValue)!")
        }
        
        // Give XP for kill
        player.gainXP(enemy.type.xpReward)
        
        hudViewModel?.update()
    }
    
    /// Open a chest and give loot to player
    private func openChest(at index: Int) {
        guard index >= 0 && index < interactables.count else { return }
        guard !interactables[index].isOpen else { return }
        
        interactables[index].isOpen = true
        chestsNeedRebuild = true
        
        let goldFound = interactables[index].goldAmount
        var itemName: String? = nil
        var itemRarity: String? = nil
        
        // Give loot to player
        if goldFound > 0 {
            player.inventory.addGold(goldFound)
            print("[Chest] Found \(goldFound) gold!")
        }
        
        if let item = interactables[index].containedItem {
            if player.inventory.addItem(item) {
                itemName = item.name
                itemRarity = item.rarity.name
                print("[Chest] Found \(item.rarity.name) \(item.name)!")
            } else {
                print("[Chest] Inventory full! Couldn't pick up \(item.name)")
            }
        }
        
        // Show loot notification on HUD
        Task { @MainActor in
            hudViewModel?.showLoot(gold: goldFound, itemName: itemName, itemRarity: itemRarity)
        }
    }
    
    /// Rebuild chest meshes if needed (after opening)
    private func rebuildChestsIfNeeded() {
        guard chestsNeedRebuild else { return }
        chestsNeedRebuild = false
        
        let chestResult = GeometryGenerator.makeTreasureChestMeshes(device: device, interactables: interactables)
        chestVertexBuffer = chestResult.0
        chestVertexCount = chestResult.1
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
        
        // Handle interaction input (E key)
        if interactPressed && !interactWasPressed {
            tryInteract()
        }
        interactWasPressed = interactPressed
        
        // Rebuild chest meshes if any were opened
        rebuildChestsIfNeeded()
        
        // Handle combat
        updateCombat(deltaTime: dt)
        
        updateCharacter(deltaTime: dt)
        updateCamera(deltaTime: dt)
        viewMatrix = buildViewMatrix()
        updateLightMatrix()  // Update shadows for current sun position
        
        let vp = projectionMatrix * viewMatrix
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Update character mesh animation
        let hasSword = player.equipment.hasSwordEquipped
        characterMesh.update(walkPhase: walkPhase, isJumping: isJumping, 
                            hasSwordEquipped: hasSword,
                            isAttacking: isAttacking, attackPhase: attackPhase,
                            swingType: currentSwingType)
        
        // Update enemies
        updateEnemies(deltaTime: dt)
        enemyMesh.update(enemies: enemyManager.enemies)
        
        // Update damage numbers on HUD
        updateDamageNumbersDisplay()
        
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
        
        // Character with model matrix - use characterUniformBuffer
        let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
        let charShadowPtr = characterUniformBuffer.contents().bindMemory(to: LitUniforms.self, capacity: 1)
        charShadowPtr.pointee = shadowUniforms
        charShadowPtr.pointee.modelMatrix = charModelMatrix
        
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
        
        // Draw character - use characterUniformBuffer with character's model matrix
        if characterMesh.vertexCount > 0 {
            let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
            
            // Write directly to characterUniformBuffer
            let charBufferPtr = characterUniformBuffer.contents().bindMemory(to: LitUniforms.self, capacity: 1)
            charBufferPtr.pointee = litUniforms
            charBufferPtr.pointee.modelMatrix = charModelMatrix
            
            // Bind character's uniform buffer
            encoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(characterUniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(characterMesh.vertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: characterMesh.vertexCount)
            
            // Restore landscape uniform buffer for subsequent draws
            encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
        }
        
        // Draw enemies
        drawEnemies(encoder: encoder, litUniforms: litUniforms)
        
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
        
        // Treasure chest texture (index 16)
        encoder.setFragmentTexture(treasureChestTexture, index: 16)
        
        // Enemy texture (index 17 - red shirt for bandits)
        encoder.setFragmentTexture(enemyTexture, index: 17)
        
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
        
        // Draw treasure chests
        if chestVertexCount > 0 {
            encoder.setVertexBuffer(chestVertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: chestVertexCount)
        }
    }
    
    /// Draw all enemies
    private func drawEnemies(encoder: MTLRenderCommandEncoder, litUniforms: LitUniforms) {
        guard enemyMesh.vertexCount > 0 else { return }
        
        // Draw each enemy with its own model matrix
        let enemies = enemyManager.enemies.filter { $0.isAlive || $0.stateTimer < 60.0 }
        
        encoder.setVertexBuffer(enemyMesh.vertexBuffer, offset: 0, index: 0)
        
        // 256-byte aligned stride for uniform buffer offsets
        let uniformStride = (MemoryLayout<LitUniforms>.stride + 255) & ~255
        
        // First pass: write all enemy uniforms to buffer
        let bufferBase = enemyUniformBuffer.contents()
        for (index, enemy) in enemies.enumerated() {
            guard index < 100 else { break }  // Max 100 enemies
            
            let enemyModelMatrix = translation(enemy.position.x, enemy.position.y, enemy.position.z) * rotationY(enemy.yaw)
            
            var enemyUniforms = litUniforms
            enemyUniforms.modelMatrix = enemyModelMatrix
            
            // Write to this enemy's slot in the buffer
            let offset = index * uniformStride
            let ptr = bufferBase.advanced(by: offset).bindMemory(to: LitUniforms.self, capacity: 1)
            ptr.pointee = enemyUniforms
        }
        
        // Second pass: draw each enemy using its uniform offset
        for (index, enemy) in enemies.enumerated() {
            guard index < enemyMesh.enemyVertexRanges.count else { break }
            guard index < 100 else { break }
            
            let range = enemyMesh.enemyVertexRanges[index]
            guard range.count > 0 else { continue }
            
            let offset = index * uniformStride
            encoder.setVertexBuffer(enemyUniformBuffer, offset: offset, index: 1)
            encoder.setFragmentBuffer(enemyUniformBuffer, offset: offset, index: 1)
            
            encoder.drawPrimitives(type: .triangle, vertexStart: range.start, vertexCount: range.count)
        }
        
        // Restore landscape uniform buffer
        encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
    }
    
    // MARK: - Character & Camera Updates
    
    private func updateCharacter(deltaTime dt: Float) {
        // Tank controls:
        // - Left/Right (movementVector.x) rotates the character
        // - Up/Down (movementVector.y) moves forward/backward
        
        // Rotation from left/right input
        let rotationSpeed: Float = 3.0  // Radians per second
        characterYaw += movementVector.x * rotationSpeed * dt
        
        // Normalize yaw
        while characterYaw > .pi { characterYaw -= 2 * .pi }
        while characterYaw < -.pi { characterYaw += 2 * .pi }
        
        // Forward/backward movement in the direction the character is facing
        let forwardInput = movementVector.y  // Positive = forward, negative = backward
        
        // Calculate forward direction based on character yaw
        let forwardX = sin(characterYaw)
        let forwardZ = -cos(characterYaw)
        
        let targetSpeed = abs(forwardInput) * characterSpeed
        isMoving = targetSpeed > 0.1
        
        if isMoving {
            // Target velocity in the direction character is facing
            let moveDirection = forwardInput > 0 ? 1.0 : -1.0
            let targetVelocity = simd_float3(
                Float(moveDirection) * forwardX * targetSpeed,
                0,
                Float(moveDirection) * forwardZ * targetSpeed
            )
            
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
        } else {
            // Decelerate when not moving
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
        
        // Walk animation (rotation is now handled in input section above)
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
    
    private func updateCombat(deltaTime dt: Float) {
        // Update cooldown
        if attackCooldown > 0 {
            attackCooldown -= dt
        }
        
        // Check for attack input (only if has sword equipped)
        if attackPressed && !attackWasPressed && !isAttacking && attackCooldown <= 0 {
            if player.equipment.hasSwordEquipped {
                startAttack()
            }
        }
        attackWasPressed = attackPressed
        
        // Update attack animation
        if isAttacking {
            attackPhase += dt / attackDuration
            
            if attackPhase >= 1.0 {
                // Attack finished
                isAttacking = false
                attackPhase = 0
                attackCooldown = attackCooldownTime
                
                // Check for hits (damage enemies in range)
                performAttackHitCheck()
            }
        }
    }
    
    private func startAttack() {
        isAttacking = true
        attackPhase = 0
        
        // Randomly select swing type
        let swingTypes = SwingType.allCases
        currentSwingType = swingTypes[Int.random(in: 0..<swingTypes.count)]
        
        print("[Combat] \(currentSwingType.name)!")
    }
    
    private func performAttackHitCheck() {
        // Calculate attack hitbox position (in front of character)
        let attackRange: Float = 2.0
        
        // Get enemies in range
        let enemiesInRange = enemyManager.enemiesInRange(of: characterPosition, range: attackRange)
        
        // Check each enemy in range for hit (must be in front arc)
        for enemy in enemiesInRange {
            let toEnemy = simd_float2(enemy.position.x, enemy.position.z) - simd_float2(characterPosition.x, characterPosition.z)
            let dirToEnemy = simd_normalize(toEnemy)
            
            // Character forward direction
            let charForward = simd_float2(sin(characterYaw), -cos(characterYaw))
            
            // Dot product gives us angle - within 90 degree frontal arc
            let dot = simd_dot(charForward, dirToEnemy)
            if dot > 0.3 {  // Roughly 70 degree arc
                // Hit! Calculate damage
                let baseDamage = player.effectiveDamage
                let isCritical = Float.random(in: 0...1) < 0.15  // 15% crit chance
                let damage = isCritical ? baseDamage * 2 : baseDamage
                
                let actualDamage = enemy.takeDamage(damage)
                
                // Show damage number
                enemyManager.addDamageNumber(actualDamage, at: enemy.position, isCritical: isCritical)
                
                print("[Combat] Hit \(enemy.type.rawValue) for \(actualDamage) damage\(isCritical ? " (CRITICAL!)" : "")")
                
                // Check if enemy died
                if !enemy.isAlive {
                    // Give XP and gold
                    player.gainXP(enemy.type.xpReward)
                    let goldDrop = Int.random(in: enemy.type.goldDrop)
                    player.inventory.addGold(goldDrop)
                    print("[Combat] \(enemy.type.rawValue) defeated! +\(enemy.type.xpReward) XP, +\(goldDrop) gold")
                    
                    // Update HUD
                    Task { @MainActor in
                        hudViewModel?.update()
                    }
                }
            }
        }
    }
    
    /// Update all enemies (AI, movement, attacks)
    private func updateEnemies(deltaTime dt: Float) {
        // Update enemy AI and animation
        enemyManager.update(deltaTime: dt, playerPosition: characterPosition, terrain: Terrain.shared)
        
        // Check if any enemy is attacking the player
        let enemyHits = enemyManager.checkEnemyAttacks(playerPosition: characterPosition)
        for (enemy, damage) in enemyHits {
            // Player takes damage
            player.takeDamage(damage)
            
            // Show damage number on player
            enemyManager.addDamageNumber(damage, at: characterPosition)
            
            print("[Combat] Player hit by \(enemy.type.rawValue) for \(damage) damage! HP: \(player.vitals.currentHP)/\(player.effectiveMaxHP)")
            
            // Update HUD
            Task { @MainActor in
                hudViewModel?.update()
            }
        }
        
        // Clean up dead enemies
        enemyManager.removeDeadEnemies()
    }
    
    /// Project world position to screen position
    private func worldToScreen(_ worldPos: simd_float3) -> CGPoint? {
        let vp = projectionMatrix * viewMatrix
        let clipPos = vp * simd_float4(worldPos.x, worldPos.y, worldPos.z, 1.0)
        
        // Behind camera check
        if clipPos.w <= 0 { return nil }
        
        // Normalized device coordinates
        let ndcX = clipPos.x / clipPos.w
        let ndcY = clipPos.y / clipPos.w
        
        // Screen coordinates (0,0 is top-left in SwiftUI)
        let screenX = (ndcX + 1) * 0.5 * Float(viewportSize.width)
        let screenY = (1 - ndcY) * 0.5 * Float(viewportSize.height)  // Flip Y
        
        return CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))
    }
    
    /// Update HUD with damage numbers from enemy manager
    private func updateDamageNumbersDisplay() {
        let damageNums = enemyManager.damageNumbers
        
        Task { @MainActor in
            for dmgNum in damageNums {
                if let screenPos = self.worldToScreen(dmgNum.worldPosition) {
                    hudViewModel?.addDamageNumber(
                        amount: dmgNum.amount,
                        screenPosition: screenPos,
                        isCritical: dmgNum.isCritical,
                        isHeal: dmgNum.isHeal
                    )
                }
            }
        }
        
        // Clear damage numbers from manager after sending to HUD
        // (they're now managed by the HUD)
        enemyManager.damageNumbers.removeAll()
    }
    
    private func updateCamera(deltaTime dt: Float) {
        // Camera stays directly behind the character (over-the-shoulder)
        // Character forward direction: (sin(yaw), 0, -cos(yaw))
        // Camera should be behind, so we negate the forward direction
        
        // Calculate camera position behind character
        // Behind = opposite of forward = (-sin(yaw), 0, cos(yaw))
        let offsetX = -sin(characterYaw) * cameraDistance
        let offsetZ = cos(characterYaw) * cameraDistance
        
        // Target camera position (behind and above the character)
        let targetCameraPos = simd_float3(
            characterPosition.x + offsetX,
            characterPosition.y + cameraHeight,
            characterPosition.z + offsetZ
        )
        
        // Smooth camera position follow
        let positionSmoothness: Float = 12.0
        cameraPosition = cameraPosition + (targetCameraPos - cameraPosition) * min(1.0, positionSmoothness * dt)
    }
    
    private func buildViewMatrix() -> simd_float4x4 {
        // Camera looks at the character (slightly above their feet)
        let lookTarget = characterPosition + simd_float3(0, 1.2, 0)
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
