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
    private var skinnedPipelineState: MTLRenderPipelineState?  // For skeletal animation
    private var skinnedShadowPipelineState: MTLRenderPipelineState?  // Shadow pass for skeletal
    private let depthStencilState: MTLDepthStencilState
    private let depthStencilStateNoWrite: MTLDepthStencilState
    private let depthStencilStateSkybox: MTLDepthStencilState
    private let shadowDepthStencilState: MTLDepthStencilState
    
    // Skeletal Animation
    private var animatedCharacter: AnimatedCharacter?
    private var useSkeletalAnimation: Bool = false  // Toggle between old/new character system
    
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
    private var targetEnemyCount: Int = 25
    private var respawnTimer: Float = 0
    private let respawnInterval: Float = 5.0  // Seconds between respawn checks
    private let minSpawnDistance: Float = 30.0  // Minimum distance from player to spawn
    
    // Skeletal enemy animation
    private var enemySkeletalMesh: SkeletalMesh?
    private var animatedEnemies: [UUID: AnimatedEnemy] = [:]  // Map enemy ID to animated instance
    private var useSkeletalEnemies: Bool = false
    private var enemyModelMatrix: simd_float4x4 = matrix_identity_float4x4
    private var enemyModelScale: Float = 1.0
    
    // MARK: - NPCs
    
    private var vendorTexture: MTLTexture!
    private var npcManager: NPCManager!
    private var npcMesh: NPCMesh!
    private var npcUniformBuffer: MTLBuffer!
    
    // MARK: - USD Models (Cabin)
    
    private var cabinTexture: MTLTexture!
    private var cabinVertexBuffer: MTLBuffer?
    private var cabinVertexCount: Int = 0
    private var cabinModelMatrix: simd_float4x4 = matrix_identity_float4x4
    
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
    var runPressed: Bool = false  // Hold to run
    var savePressed: Bool = false
    private var saveWasPressed: Bool = false
    
    // MARK: - Combat State
    
    private var isAttacking: Bool = false
    private var attackPhase: Float = 0        // 0 to 1, progress through swing
    private var attackCooldown: Float = 0     // Time until next attack allowed
    private let baseAttackDuration: Float = 0.4   // How long the swing takes (base)
    private let baseAttackCooldownTime: Float = 0.3  // Time between attacks (base)
    private var attackWasPressed: Bool = false
    private var currentSwingType: SwingType = .mittelhaw
    private var hasPerformedHitCheck: Bool = false  // Track if hit check done this attack
    
    /// Effective attack cooldown based on dexterity
    /// Higher dexterity = faster recovery = lower cooldown
    private var effectiveAttackCooldown: Float {
        let dex = Float(player.effectiveDexterity)
        // Base cooldown reduced by 3% per dexterity point above 10
        // At DEX 10: 100% cooldown, DEX 20: 70% cooldown, DEX 30: 40% cooldown
        let reduction = max(0.3, 1.0 - (dex - 10) * 0.03)
        return baseAttackCooldownTime * reduction
    }
    
    /// Effective attack duration based on dexterity
    private var effectiveAttackDuration: Float {
        let dex = Float(player.effectiveDexterity)
        // Slightly faster swings with higher dex
        let reduction = max(0.5, 1.0 - (dex - 10) * 0.02)
        return baseAttackDuration * reduction
    }
    
    /// Animation speed multiplier for attacks based on dexterity
    /// Higher dexterity = faster attack animation
    private var attackAnimationSpeed: Float {
        let dex = Float(player.effectiveDexterity)
        // Same formula as effectiveAttackDuration, but inverted
        // So animation plays faster to match the shorter attack duration
        let reduction = max(0.5, 1.0 - (dex - 10) * 0.02)
        return 1.0 / reduction  // Invert: 0.5 reduction = 2.0x speed
    }
    
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
    private let baseCharacterSpeed: Float = 3.5  // Reduced to match walking animation
    private let runSpeedMultiplier: Float = 2.0  // Running is 2x walking speed
    private let acceleration: Float = 40.0
    private let deceleration: Float = 25.0
    private let turnSpeed: Float = 15.0
    
    /// Whether the player is currently running
    private var isRunning: Bool = false
    
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
    private var lanternPositions: [simd_float3] = []
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
    private var cabinUniformBuffer: MTLBuffer
    private var enemyUniformBuffer: MTLBuffer  // Large buffer for all enemies
    
    // Collision
    private var colliders: [Collider] = []
    private let characterRadius: Float = 0.3
    
    // Camera obstruction data (trees, rocks with their visual radius)
    private var cameraBlockers: [(position: simd_float2, radius: Float, height: Float)] = []
    
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
        cameraBlockers.append(contentsOf: treeResult.3)
        
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
        lanternPositions = poleResult.3
        
        // 5. Create treasure chests
        self.interactables = Renderer.createTreasureChests()
        let chestResult = GeometryGenerator.makeTreasureChestMeshes(device: device, interactables: interactables)
        chestVertexBuffer = chestResult.0
        chestVertexCount = chestResult.1
        allColliders.append(contentsOf: chestResult.2)
        
        self.colliders = allColliders
        
        // Create character mesh (fallback)
        self.characterMesh = CharacterMesh(device: device)
        
        // Try to create skinned pipelines and load skeletal character
        self.skinnedPipelineState = Renderer.createSkinnedPipeline(device: device, library: library, view: view)
        self.skinnedShadowPipelineState = Renderer.createSkinnedShadowPipeline(device: device, library: library)
        
        // Create enemy mesh and manager
        self.enemyMesh = EnemyMesh(device: device)
        self.enemyManager = EnemyManager()
        
        // Create NPC mesh and manager
        self.npcMesh = NPCMesh(device: device)
        self.npcManager = NPCManager()
        
        // Create uniform buffers with shared storage mode for CPU/GPU access
        uniformBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride * 3, options: .storageModeShared)!
        litUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: .storageModeShared)!
        characterUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: .storageModeShared)!
        skyboxUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: .storageModeShared)!
        cabinUniformBuffer = device.makeBuffer(length: MemoryLayout<LitUniforms>.stride, options: .storageModeShared)!
        // Enemy uniform buffer - large enough for 100 enemies with proper alignment
        let uniformStride = (MemoryLayout<LitUniforms>.stride + 255) & ~255  // 256-byte aligned
        enemyUniformBuffer = device.makeBuffer(length: uniformStride * 100, options: .storageModeShared)!
        
        // NPC uniform buffer - for 10 NPCs
        npcUniformBuffer = device.makeBuffer(length: uniformStride * 10, options: .storageModeShared)!
        
        super.init()
        
        // Load cabin USD model (must be after super.init)
        loadCabinModel()
        
        // Load skeletal player model (must be after super.init)
        loadPlayerModel()
        
        // Load skeletal enemy model
        loadEnemyModel()
        
        // Spawn enemies (higher chance near treasure chests)
        // Must be after super.init() to call instance method
        spawnEnemies(nearChests: self.interactables)
        
        // Spawn NPCs (vendors)
        spawnNPCs()
        
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
        vendorTexture = textureGen.createVendorTexture()
        cabinTexture = textureGen.createCabinTexture()  // Fallback texture for cabin
        shadowMap = textureGen.createShadowMap(size: shadowMapSize)
        
        // Normal maps
        groundNormalMap = textureGen.createGroundNormalMap()
        trunkNormalMap = textureGen.createTrunkNormalMap()
        rockNormalMap = textureGen.createRockNormalMap()
        pathNormalMap = textureGen.createPathNormalMap()
        
        // Initialize character mesh
        characterMesh.update(walkPhase: walkPhase, isJumping: isJumping, 
                            hasSwordEquipped: player.equipment.hasSwordEquipped,
                            hasShieldEquipped: player.equipment.hasShieldEquipped,
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
    
    /// Create pipeline for skeletal animation (skinned mesh)
    private static func createSkinnedPipeline(device: MTLDevice, library: MTLLibrary, view: MTKView) -> MTLRenderPipelineState? {
        guard let vertexFunc = library.makeFunction(name: "vertex_skinned"),
              let fragmentFunc = library.makeFunction(name: "fragment_lit") else {
            print("[Renderer] Could not find skinned vertex shader function")
            return nil
        }
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.vertexDescriptor = Renderer.skinnedVertexDescriptor()
        
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[Renderer] Failed to create skinned pipeline: \(error)")
            return nil
        }
    }
    
    /// Create shadow pipeline for skeletal animation
    private static func createSkinnedShadowPipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState? {
        guard let vertexFunc = library.makeFunction(name: "vertex_skinned_shadow"),
              let fragmentFunc = library.makeFunction(name: "fragment_shadow") else {
            print("[Renderer] Could not find skinned shadow shader function")
            return nil
        }
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = .invalid
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.vertexDescriptor = Renderer.skinnedVertexDescriptor()
        
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[Renderer] Failed to create skinned shadow pipeline: \(error)")
            return nil
        }
    }
    
    /// Vertex descriptor for skinned vertices (packed layout - no SIMD padding)
    private static func skinnedVertexDescriptor() -> MTLVertexDescriptor {
        let desc = MTLVertexDescriptor()
        
        var offset = 0
        
        // Position (float3) - 12 bytes
        desc.attributes[0].format = .float3
        desc.attributes[0].offset = offset
        desc.attributes[0].bufferIndex = 0
        offset += 12
        
        // Normal (float3) - 12 bytes
        desc.attributes[1].format = .float3
        desc.attributes[1].offset = offset
        desc.attributes[1].bufferIndex = 0
        offset += 12
        
        // TexCoord (float2) - 8 bytes
        desc.attributes[2].format = .float2
        desc.attributes[2].offset = offset
        desc.attributes[2].bufferIndex = 0
        offset += 8
        
        // Bone indices (uint4) - 16 bytes
        desc.attributes[3].format = .uint4
        desc.attributes[3].offset = offset
        desc.attributes[3].bufferIndex = 0
        offset += 16
        
        // Bone weights (float4) - 16 bytes
        desc.attributes[4].format = .float4
        desc.attributes[4].offset = offset
        desc.attributes[4].bufferIndex = 0
        offset += 16
        
        // Material index (uint) - 4 bytes
        desc.attributes[5].format = .uint
        desc.attributes[5].offset = offset
        desc.attributes[5].bufferIndex = 0
        offset += 4
        
        // Padding - 4 bytes
        offset += 4
        
        // Total stride should be 72 bytes
        desc.layouts[0].stride = SkinnedVertex.stride
        desc.layouts[0].stepRate = 1
        desc.layouts[0].stepFunction = .perVertex
        
        return desc
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
            
            if lootRoll < 0.35 {
                // Gold only (35% chance)
                chest.goldAmount = 10 + Int(seededRandom(seed) * 40)
                seed += 1
            } else if lootRoll < 0.60 {
                // Gold + common item (25% chance)
                chest.goldAmount = 5 + Int(seededRandom(seed) * 20)
                seed += 1
                
                let itemRoll = seededRandom(seed)
                seed += 1
                if itemRoll < 0.25 {
                    chest.containedItem = ItemTemplates.healthPotion(size: .common)
                } else if itemRoll < 0.40 {
                    chest.containedItem = ItemTemplates.randomSword()
                } else if itemRoll < 0.55 {
                    chest.containedItem = ItemTemplates.randomShield()
                } else if itemRoll < 0.70 {
                    chest.containedItem = ItemTemplates.randomArmor()
                } else {
                    chest.containedItem = ItemTemplates.randomGem()
                }
            } else if lootRoll < 0.85 {
                // Better item (25% chance)
                chest.goldAmount = 15 + Int(seededRandom(seed) * 30)
                seed += 1
                
                let itemRoll = seededRandom(seed)
                seed += 1
                if itemRoll < 0.15 {
                    chest.containedItem = ItemTemplates.healthPotion(size: .uncommon)
                } else if itemRoll < 0.35 {
                    chest.containedItem = ItemTemplates.randomSword()
                } else if itemRoll < 0.50 {
                    chest.containedItem = ItemTemplates.randomShield()
                } else if itemRoll < 0.65 {
                    chest.containedItem = ItemTemplates.randomArmor()
                } else {
                    chest.containedItem = ItemTemplates.randomGem()
                }
            } else {
                // Rare item (15% chance)
                chest.goldAmount = 30 + Int(seededRandom(seed) * 50)
                seed += 1
                
                let itemRoll = seededRandom(seed)
                seed += 1
                if itemRoll < 0.25 {
                    chest.containedItem = ItemTemplates.randomSword()
                } else if itemRoll < 0.45 {
                    chest.containedItem = ItemTemplates.randomShield()
                } else if itemRoll < 0.60 {
                    chest.containedItem = ItemTemplates.randomArmor()
                } else if itemRoll < 0.75 {
                    chest.containedItem = ItemTemplates.healthPotion(size: .rare)
                } else {
                    chest.containedItem = ItemTemplates.randomGem()
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
                        // Initial enemies start at level 1
                        enemyManager.spawnEnemy(type: .bandit, at: simd_float3(x, y, z), playerLevel: 1)
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
            // Initial enemies start at level 1
            enemyManager.spawnEnemy(type: .bandit, at: simd_float3(x, y, z), playerLevel: 1)
        }
        
        print("[Enemies] Spawned \(enemyManager.count) bandits")
        targetEnemyCount = enemyManager.count  // Set target to initial spawn count
    }
    
    /// Spawn vendor NPCs at strategic locations
    private func spawnNPCs() {
        // Place a vendor near the cabin
        let vendorX: Float = 3.5
        let vendorZ: Float = 20.3
        let vendorY = Terrain.heightAt(x: vendorX, z: vendorZ)
        
        // Vendor faces toward spawn point
        let yaw = atan2(-vendorX, -vendorZ)
        
        npcManager.spawnNPC(type: .vendor, name: "Traveling Merchant", at: simd_float3(vendorX, vendorY, vendorZ), yaw: yaw)
        
        print("[NPCs] Spawned \(npcManager.count) NPCs")
    }
    
    /// Try to respawn enemies if below target count
    private func tryRespawnEnemies(deltaTime dt: Float) {
        respawnTimer += dt
        
        guard respawnTimer >= respawnInterval else { return }
        respawnTimer = 0
        
        // Check if we need more enemies
        let currentAlive = enemyManager.aliveCount
        guard currentAlive < targetEnemyCount else { return }
        
        // Spawn 1-2 enemies at a time
        let toSpawn = min(2, targetEnemyCount - currentAlive)
        
        for _ in 0..<toSpawn {
            // Try to find a valid spawn location
            for _ in 0..<10 {  // Max 10 attempts
                // Random location in the world
                let x = Float.random(in: -80...80)
                let z = Float.random(in: -80...80)
                
                // Check distance from player
                let distFromPlayer = simd_distance(
                    simd_float2(x, z),
                    simd_float2(characterPosition.x, characterPosition.z)
                )
                
                if distFromPlayer >= minSpawnDistance {
                    let y = Terrain.heightAt(x: x, z: z)
                    // Respawned enemies scale with player level
                    enemyManager.spawnEnemy(type: .bandit, at: simd_float3(x, y, z), playerLevel: player.vitals.level)
                    break
                }
            }
        }
    }
    
    /// Try to interact with nearby chests, corpses, or NPCs
    func tryInteract() {
        // Check for NPCs first (vendors, etc.)
        if let npc = npcManager.findInteractableNPC(near: characterPosition) {
            interactWithNPC(npc)
            return
        }
        
        // Check for treasure chests
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
    
    /// Interact with an NPC (open shop, dialogue, etc.)
    private func interactWithNPC(_ npc: NPC) {
        switch npc.type {
        case .vendor:
            // Open shop UI
            Task { @MainActor in
                hudViewModel?.openShop(for: npc)
            }
            print("[NPC] Opened shop for \(npc.name)")
        }
    }
    
    /// Open the loot panel for a dead enemy's corpse
    private func lootCorpse(_ enemy: Enemy) {
        guard !enemy.isLooted else { return }
        
        // Open the loot panel UI instead of auto-looting
        hudViewModel?.openLootPanel(for: enemy)
    }
    
    // MARK: - Save/Load System
    
    /// Quick save the current game state
    func quickSave() -> Bool {
        let success = SaveGameManager.shared.quickSave(
            player: player,
            position: characterPosition,
            yaw: characterYaw
        )
        
        if success {
            Task { @MainActor in
                hudViewModel?.showLoot(gold: 0, itemName: "Quick Saved!", itemRarity: nil, title: "💾 Saved", icon: "bolt.fill")
            }
        }
        return success
    }
    
    /// Save the current game state with a name
    func saveGame(name: String? = nil) -> Bool {
        let success = SaveGameManager.shared.saveGame(
            player: player,
            position: characterPosition,
            yaw: characterYaw,
            saveName: name
        )
        
        if success {
            Task { @MainActor in
                hudViewModel?.showLoot(gold: 0, itemName: "Game Saved!", itemRarity: nil, title: "💾 Saved", icon: "checkmark.circle.fill")
            }
        }
        return success
    }
    
    /// Load the most recent saved game
    func loadGame() {
        guard let saveData = SaveGameManager.shared.loadGame() else {
            print("[SaveGame] No save data found")
            return
        }
        loadGame(from: saveData)
    }
    
    /// Load a specific save game
    func loadGame(from saveData: SaveGameData) {
        // Restore player state
        player.attributes.strength = saveData.strength
        player.attributes.dexterity = saveData.dexterity
        player.attributes.intelligence = saveData.intelligence
        player.vitals.currentHP = saveData.currentHP
        player.vitals.maxHP = saveData.maxHP
        player.vitals.currentXP = saveData.currentXP
        player.vitals.xpToNextLevel = saveData.xpToNextLevel
        player.vitals.level = saveData.level
        player.unspentAttributePoints = saveData.unspentPoints
        
        // Clear and restore inventory
        player.inventory.clear()
        player.inventory.addGold(saveData.gold)
        
        for savedStack in saveData.inventoryItems {
            let item = SaveGameManager.shared.restoreItem(savedStack.item)
            player.inventory.addItem(item, quantity: savedStack.quantity)
        }
        
        // Clear and restore equipment
        for slot in EquipmentSlot.allCases {
            player.equipment.unequip(slot)
        }
        for (_, savedItem) in saveData.equippedItems {
            let item = SaveGameManager.shared.restoreItem(savedItem)
            player.equipment.equip(item)
        }
        
        // Restore position
        characterPosition = simd_float3(saveData.positionX, saveData.positionY, saveData.positionZ)
        characterYaw = saveData.yaw
        characterVelocity = .zero
        
        // Reset game state
        isAttacking = false
        attackPhase = 0
        isJumping = false
        
        // Update HUD
        Task { @MainActor in
            hudViewModel?.hideDeathScreen()
            hudViewModel?.update()
            hudViewModel?.updateInventorySlots()
            hudViewModel?.updateEquipmentDisplay()
        }
        
        print("[SaveGame] Game loaded - Position: \(characterPosition), HP: \(player.vitals.currentHP)")
    }
    
    /// Restart the game with a fresh character
    func restartGame() {
        // Reset player
        player.attributes = CharacterAttributes(strength: 10, dexterity: 12, intelligence: 8)
        player.vitals = CharacterVitals(maxHP: 100, level: 1)
        player.vitals.currentHP = player.effectiveMaxHP
        player.unspentAttributePoints = 0
        
        // Clear inventory and give starting gold
        player.inventory.clear()
        player.inventory.addGold(50)
        
        // Give starter items
        player.inventory.addItem(ItemTemplates.healthPotion(size: .common), quantity: 3)
        
        // Clear and reset equipment
        for slot in EquipmentSlot.allCases {
            player.equipment.unequip(slot)
        }
        player.equipment.equip(ItemTemplates.sword(rarity: .common))
        
        // Reset position to origin
        characterPosition = simd_float3(0, 0, 0)
        characterPosition.y = Terrain.shared.heightAt(x: 0, z: 0)
        characterYaw = 0
        characterVelocity = .zero
        
        // Reset game state
        isAttacking = false
        attackPhase = 0
        isJumping = false
        
        // Respawn enemies
        enemyManager.clearEnemies()
        spawnEnemies(nearChests: interactables)
        
        // Reset treasure chests
        for i in 0..<interactables.count {
            interactables[i].isOpen = false
        }
        chestsNeedRebuild = true
        
        // Update HUD
        Task { @MainActor in
            hudViewModel?.hideDeathScreen()
            hudViewModel?.bind(to: player)
        }
        
        print("[Game] Game restarted")
    }
    
    /// Open a chest and give loot to player
    private func openChest(at index: Int) {
        guard index >= 0 && index < interactables.count else { return }
        guard !interactables[index].isOpen else { return }
        
        // Play treasure chest open sound
        AudioManager.shared.playTreasureChestOpen()
        
        // Mark chest as open (visually) but don't give loot yet
        interactables[index].isOpen = true
        chestsNeedRebuild = true
        
        let goldAmount = interactables[index].goldAmount
        var items: [Item] = []
        if let item = interactables[index].containedItem {
            items.append(item)
        }
        
        // Open the loot panel for this chest
        Task { @MainActor in
            hudViewModel?.openLootPanelForChest(
                index: index,
                name: "Treasure Chest",
                gold: goldAmount,
                items: items
            )
        }
    }
    
    /// Called when player finishes looting a chest (from loot panel)
    func finalizeChestLoot(chestIndex: Int, goldTaken: Int, itemsTaken: [Item]) {
        guard chestIndex >= 0 && chestIndex < interactables.count else { return }
        
        // Give gold to player
        if goldTaken > 0 {
            player.inventory.addGold(goldTaken)
            print("[Chest] Took \(goldTaken) gold")
        }
        
        // Give items to player
        for item in itemsTaken {
            if player.inventory.addItem(item) {
                print("[Chest] Took \(item.name)")
            } else {
                print("[Chest] Inventory full! Couldn't take \(item.name)")
            }
        }
        
        // Update HUD
        Task { @MainActor in
            hudViewModel?.update()
            hudViewModel?.updateInventorySlots()
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
        
        // Handle save input (F5 key)
        if savePressed && !saveWasPressed {
            _ = saveGame()
        }
        saveWasPressed = savePressed
        
        // Rebuild chest meshes if any were opened
        rebuildChestsIfNeeded()
        
        // Check if game is paused (menus open)
        let isGamePaused = hudViewModel?.isGamePaused ?? false
        
        if !isGamePaused {
            // Handle combat (only when not paused)
            updateCombat(deltaTime: dt)
            
            // Update character movement (only when not paused)
        updateCharacter(deltaTime: dt)
        }
        
        updateCamera(deltaTime: dt)
        viewMatrix = buildViewMatrix()
        updateLightMatrix()  // Update shadows for current sun position
        
        let vp = projectionMatrix * viewMatrix
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Update character animation
        let hasSword = player.equipment.hasSwordEquipped
        let hasShield = player.equipment.hasShieldEquipped
        
        if useSkeletalAnimation, let animChar = animatedCharacter {
            // Update skeletal animation based on player state
            if isAttacking {
                animChar.setAnimationState(.attacking)
                // Speed up attack animation based on dexterity
                animChar.animationSpeed = attackAnimationSpeed
            } else if isJumping {
                animChar.setAnimationState(.jumping)
                animChar.animationSpeed = 1.0
            } else if isMoving {
                // Use running animation when holding run key
                animChar.setAnimationState(isRunning ? .running : .walking)
                animChar.animationSpeed = 1.0
            } else {
                animChar.setAnimationState(.idle)
                animChar.animationSpeed = 1.0
            }
            
            animChar.hasShieldEquipped = hasShield
            animChar.update(deltaTime: dt)
        } else {
            // Fallback: Procedural character mesh with animation
            characterMesh.update(walkPhase: walkPhase, isJumping: isJumping, 
                                hasSwordEquipped: hasSword,
                                hasShieldEquipped: hasShield,
                                isAttacking: isAttacking, attackPhase: attackPhase,
                                swingType: currentSwingType)
        }
        
        // Update enemies
        updateEnemies(deltaTime: dt)
        enemyMesh.update(enemies: enemyManager.enemies)
        
        // Update NPCs
        npcManager.update(deltaTime: dt, playerPosition: characterPosition)
        npcMesh.update(npcs: npcManager.npcs)
        
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
        
        // Character shadow
        let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
        
        if useSkeletalAnimation, let animChar = animatedCharacter, let skinnedShadowPipeline = skinnedShadowPipelineState {
            // Use skeletal animation for shadow
            let fullModelMatrix = charModelMatrix * playerModelMatrix
            
            encoder.setRenderPipelineState(skinnedShadowPipeline)
            
            var skinnedUniforms = SkinnedUniforms()
            skinnedUniforms.modelMatrix = fullModelMatrix
            skinnedUniforms.viewProjectionMatrix = vp
            skinnedUniforms.lightViewProjectionMatrix = lightViewProjectionMatrix
            skinnedUniforms.lightDirection = currentLightDir
            skinnedUniforms.cameraPosition = cameraPosition
            skinnedUniforms.ambientIntensity = ambientIntensity
            skinnedUniforms.diffuseIntensity = diffuseIntensity
            skinnedUniforms.timeOfDay = timeOfDay
            
            memcpy(animChar.uniformBuffer.contents(), &skinnedUniforms, MemoryLayout<SkinnedUniforms>.stride)
            
            encoder.setVertexBuffer(animChar.mesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(animChar.uniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(animChar.mesh.boneMatrixBuffer, offset: 0, index: 2)
            
            // Draw with equipment visibility based on player state
            let showShield = player.equipment.hasShieldEquipped
            let showWeapon = player.equipment.hasSwordEquipped
            let drawRanges = animChar.mesh.getDrawRanges(showShield: showShield, showWeapon: showWeapon)
            for range in drawRanges {
                encoder.drawPrimitives(type: .triangle, vertexStart: range.start, vertexCount: range.count)
            }
            
            encoder.setRenderPipelineState(shadowPipelineState)
        } else if useSkeletalAnimation, playerModelVertexCount > 0, let playerBuffer = playerModelVertexBuffer {
            // Fallback: Use loaded player model for shadow (static)
            let fullModelMatrix = charModelMatrix * playerModelMatrix
            
            let charShadowPtr = characterUniformBuffer.contents().bindMemory(to: LitUniforms.self, capacity: 1)
            charShadowPtr.pointee = shadowUniforms
            charShadowPtr.pointee.modelMatrix = fullModelMatrix
            
            encoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(playerBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: playerModelVertexCount)
        } else if characterMesh.vertexCount > 0 {
            // Fallback to procedural character shadow
            let charShadowPtr = characterUniformBuffer.contents().bindMemory(to: LitUniforms.self, capacity: 1)
            charShadowPtr.pointee = shadowUniforms
            charShadowPtr.pointee.modelMatrix = charModelMatrix
            
        encoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(characterMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: characterMesh.vertexCount)
        }
        
        // Enemy shadows
        if useSkeletalEnemies, let skeletalMesh = enemySkeletalMesh, let skinnedShadowPipeline = skinnedShadowPipelineState {
            encoder.setRenderPipelineState(skinnedShadowPipeline)
            
            let enemies = enemyManager.enemies.filter { $0.isAlive || $0.stateTimer < 60.0 }
            
            for enemy in enemies {
                if let animatedEnemy = animatedEnemies[enemy.id] {
                    let worldMatrix = translation(enemy.position.x, enemy.position.y, enemy.position.z) *
                                     rotationY(enemy.yaw) *
                                     enemyModelMatrix
                    
                    var skinnedUniforms = SkinnedUniforms()
                    skinnedUniforms.modelMatrix = worldMatrix
                    skinnedUniforms.viewProjectionMatrix = vp
                    skinnedUniforms.lightViewProjectionMatrix = lightViewProjectionMatrix
                    skinnedUniforms.lightDirection = currentLightDir
                    skinnedUniforms.cameraPosition = cameraPosition
                    skinnedUniforms.ambientIntensity = ambientIntensity
                    skinnedUniforms.diffuseIntensity = diffuseIntensity
                    skinnedUniforms.timeOfDay = timeOfDay
                    
                    memcpy(animatedEnemy.uniformBuffer.contents(), &skinnedUniforms, MemoryLayout<SkinnedUniforms>.stride)
                    
                    encoder.setVertexBuffer(skeletalMesh.vertexBuffer, offset: 0, index: 0)
                    encoder.setVertexBuffer(animatedEnemy.uniformBuffer, offset: 0, index: 1)
                    encoder.setVertexBuffer(animatedEnemy.boneMatrixBuffer, offset: 0, index: 2)  // Use enemy's own bone matrices
                    
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: skeletalMesh.vertexCount)
                }
            }
            
            encoder.setRenderPipelineState(shadowPipelineState)
        }
        
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
        
        // Add point lights from lanterns
        // Lanterns are brighter at night (when ambient is lower)
        let lanternIntensity: Float = isDaytime ? 0.3 : 1.2
        
        // Find the 8 nearest lanterns to the camera for performance
        let sortedLanterns = lanternPositions
            .map { ($0, simd_distance($0, cameraPosition)) }
            .sorted { $0.1 < $1.1 }
            .prefix(8)
        
        let lanternArray = Array(sortedLanterns)
        if lanternArray.count > 0 { litUniforms.pointLight0 = simd_float4(lanternArray[0].0, lanternIntensity) }
        if lanternArray.count > 1 { litUniforms.pointLight1 = simd_float4(lanternArray[1].0, lanternIntensity) }
        if lanternArray.count > 2 { litUniforms.pointLight2 = simd_float4(lanternArray[2].0, lanternIntensity) }
        if lanternArray.count > 3 { litUniforms.pointLight3 = simd_float4(lanternArray[3].0, lanternIntensity) }
        if lanternArray.count > 4 { litUniforms.pointLight4 = simd_float4(lanternArray[4].0, lanternIntensity) }
        if lanternArray.count > 5 { litUniforms.pointLight5 = simd_float4(lanternArray[5].0, lanternIntensity) }
        if lanternArray.count > 6 { litUniforms.pointLight6 = simd_float4(lanternArray[6].0, lanternIntensity) }
        if lanternArray.count > 7 { litUniforms.pointLight7 = simd_float4(lanternArray[7].0, lanternIntensity) }
        litUniforms.pointLightCount = Int32(min(lanternArray.count, 8))
        
        memcpy(litUniformBuffer.contents(), &litUniforms, MemoryLayout<LitUniforms>.stride)
        encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
        
        // Draw landscape
        drawLandscape(encoder: encoder)
        
        // Draw character
        let charModelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
        
        if useSkeletalAnimation, let animChar = animatedCharacter, let skinnedPipeline = skinnedPipelineState {
            // Use skeletal animation with skinned pipeline
            let fullModelMatrix = charModelMatrix * playerModelMatrix
            
            encoder.setRenderPipelineState(skinnedPipeline)
            
            // Set character texture (use mesh texture if available, otherwise keep existing characterTexture)
            // Texture index 6 is characterTex in the fragment shader
            if let meshTexture = animChar.mesh.texture {
                encoder.setFragmentTexture(meshTexture, index: 6)
            }
            
            // Get active point lights
            var activePointLights: [PointLight] = []
            for (pos, _) in lanternArray {
                activePointLights.append(PointLight(position: pos, intensity: lanternIntensity))
            }
            
            // Draw the animated character with equipment visibility based on player state
            animChar.draw(
                encoder: encoder,
                modelMatrix: fullModelMatrix,
                viewProjectionMatrix: projectionMatrix * viewMatrix,
                lightViewProjectionMatrix: lightViewProjectionMatrix,
                lightDirection: isDaytime ? sunDirection : simd_normalize(simd_float3(0.3, -0.8, 0.2)),
                cameraPosition: cameraPosition,
                ambientIntensity: litUniforms.ambientIntensity,
                diffuseIntensity: litUniforms.diffuseIntensity,
                timeOfDay: timeOfDay,
                pointLights: activePointLights,
                showShield: player.equipment.hasShieldEquipped,
                showWeapon: player.equipment.hasSwordEquipped
            )
            
            // Restore lit pipeline and uniform buffer
            encoder.setRenderPipelineState(litPipelineState)
            encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
        } else if useSkeletalAnimation, playerModelVertexCount > 0, let playerBuffer = playerModelVertexBuffer {
            // Fallback: Use loaded player model as static mesh
            let fullModelMatrix = charModelMatrix * playerModelMatrix
            
            let charBufferPtr = characterUniformBuffer.contents().bindMemory(to: LitUniforms.self, capacity: 1)
            charBufferPtr.pointee = litUniforms
            charBufferPtr.pointee.modelMatrix = fullModelMatrix
            
            encoder.setVertexBuffer(characterUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(characterUniformBuffer, offset: 0, index: 1)
            encoder.setVertexBuffer(playerBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: playerModelVertexCount)
            
            encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
        } else if characterMesh.vertexCount > 0 {
            // Fallback to procedural character mesh
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
        
        // Draw NPCs (vendors)
        drawNPCs(encoder: encoder, litUniforms: litUniforms)
        
        // Draw cabin (USD model)
        drawCabin(encoder: encoder, litUniforms: litUniforms)
        
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
        
        // Vendor texture (index 18 - yellow shirt for vendors)
        encoder.setFragmentTexture(vendorTexture, index: 18)
        
        // Cabin texture (index 19 - USD model texture)
        encoder.setFragmentTexture(cabinTexture, index: 19)
        
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
        // Draw each enemy with its own model matrix
        let enemies = enemyManager.enemies.filter { $0.isAlive || $0.stateTimer < 60.0 }
        guard !enemies.isEmpty else { return }
        
        // Use skeletal animation if available
        if useSkeletalEnemies, let skeletalMesh = enemySkeletalMesh, skinnedPipelineState != nil {
            // Switch to skinned pipeline for skeletal enemies
            encoder.setRenderPipelineState(skinnedPipelineState!)
            
            // Bind the enemy texture (from USDZ or fallback to procedural)
            // Enemy vertices have materialIndex=12, which maps to texture slot 17 in the shader
            if let texture = skeletalMesh.texture {
                encoder.setFragmentTexture(texture, index: 17)  // Enemy texture slot (materialIndex 12)
            } else {
                // Fallback to procedural enemy texture if USDZ doesn't have one
                encoder.setFragmentTexture(enemyTexture, index: 17)
            }
            
            // Extract point lights from litUniforms
            var pointLights: [PointLight] = []
            if litUniforms.pointLightCount > 0 {
                pointLights.append(PointLight(position: simd_float3(litUniforms.pointLight0.x, litUniforms.pointLight0.y, litUniforms.pointLight0.z), intensity: litUniforms.pointLight0.w))
            }
            if litUniforms.pointLightCount > 1 {
                pointLights.append(PointLight(position: simd_float3(litUniforms.pointLight1.x, litUniforms.pointLight1.y, litUniforms.pointLight1.z), intensity: litUniforms.pointLight1.w))
            }
            if litUniforms.pointLightCount > 2 {
                pointLights.append(PointLight(position: simd_float3(litUniforms.pointLight2.x, litUniforms.pointLight2.y, litUniforms.pointLight2.z), intensity: litUniforms.pointLight2.w))
            }
            if litUniforms.pointLightCount > 3 {
                pointLights.append(PointLight(position: simd_float3(litUniforms.pointLight3.x, litUniforms.pointLight3.y, litUniforms.pointLight3.z), intensity: litUniforms.pointLight3.w))
            }
            
            // Draw each enemy with skeletal animation
            for enemy in enemies {
                if let animatedEnemy = animatedEnemies[enemy.id] {
                    // Create model matrix for this enemy
                    let worldMatrix = translation(enemy.position.x, enemy.position.y, enemy.position.z) *
                                     rotationY(enemy.yaw) *
                                     enemyModelMatrix
                    
                    // Draw the animated enemy
                    animatedEnemy.draw(
                        encoder: encoder,
                        modelMatrix: worldMatrix,
                        viewProjectionMatrix: projectionMatrix * viewMatrix,
                        lightViewProjectionMatrix: litUniforms.lightViewProjectionMatrix,
                        lightDirection: litUniforms.lightDirection,
                        cameraPosition: litUniforms.cameraPosition,
                        ambientIntensity: litUniforms.ambientIntensity,
                        diffuseIntensity: litUniforms.diffuseIntensity,
                        timeOfDay: litUniforms.timeOfDay,
                        pointLights: pointLights
                    )
                }
            }
            
            // Restore regular pipeline
            encoder.setRenderPipelineState(litPipelineState)
            
            // Restore landscape uniform buffer
            encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
            
        } else {
            // Fallback: Draw procedural enemy meshes
            guard enemyMesh.vertexCount > 0 else { return }
            
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
            for (index, _) in enemies.enumerated() {
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
    }
    
    /// Draw all NPCs (vendors)
    private func drawNPCs(encoder: MTLRenderCommandEncoder, litUniforms: LitUniforms) {
        guard npcMesh.vertexCount > 0 else { return }
        
        let npcs = npcManager.npcs
        guard !npcs.isEmpty else { return }
        
        encoder.setVertexBuffer(npcMesh.vertexBuffer, offset: 0, index: 0)
        
        // 256-byte aligned stride for uniform buffer offsets
        let uniformStride = (MemoryLayout<LitUniforms>.stride + 255) & ~255
        
        // First pass: write all NPC uniforms to buffer
        let bufferBase = npcUniformBuffer.contents()
        for (index, npc) in npcs.enumerated() {
            guard index < 10 else { break }  // Max 10 NPCs
            
            let npcModelMatrix = translation(npc.position.x, npc.position.y, npc.position.z) * rotationY(npc.yaw)
            
            var npcUniforms = litUniforms
            npcUniforms.modelMatrix = npcModelMatrix
            
            // Write to this NPC's slot in the buffer
            let offset = index * uniformStride
            let ptr = bufferBase.advanced(by: offset).bindMemory(to: LitUniforms.self, capacity: 1)
            ptr.pointee = npcUniforms
        }
        
        // Second pass: draw each NPC using its uniform offset
        for (index, _) in npcs.enumerated() {
            guard index < npcMesh.npcVertexRanges.count else { break }
            guard index < 10 else { break }
            
            let range = npcMesh.npcVertexRanges[index]
            guard range.count > 0 else { continue }
            
            let offset = index * uniformStride
            encoder.setVertexBuffer(npcUniformBuffer, offset: offset, index: 1)
            encoder.setFragmentBuffer(npcUniformBuffer, offset: offset, index: 1)
            
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
        
        // Apply running speed if R is held while moving forward
        isRunning = runPressed && forwardInput > 0.1
        let speedMultiplier: Float = isRunning ? runSpeedMultiplier : 1.0
        let targetSpeed = abs(forwardInput) * characterSpeed * speedMultiplier
        isMoving = targetSpeed > 0.1
        
        // Update footstep audio based on movement (only when grounded)
        let isWalkingOnGround = isMoving && !isJumping
        AudioManager.shared.updateFootsteps(isWalking: isWalkingOnGround)
        
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
        
        // Enemy collision detection
        for enemy in enemyManager.enemies where enemy.isAlive {
            let charPos2D = simd_float2(finalPosition.x, finalPosition.z)
            let enemyPos2D = simd_float2(enemy.position.x, enemy.position.z)
            let toChar = charPos2D - enemyPos2D
            let distance = simd_length(toChar)
            let enemyRadius: Float = 0.4
            let minDist = enemyRadius + characterRadius
            
            if distance < minDist && distance > 0.001 {
                let pushDirection = simd_normalize(toChar)
                let pushAmount = minDist - distance + 0.01
                finalPosition.x += pushDirection.x * pushAmount
                finalPosition.z += pushDirection.y * pushAmount
                collisionOccurred = true
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
            attackPhase += dt / effectiveAttackDuration
            
            // Check for attack completion
            var attackComplete = false
            
            if useSkeletalAnimation, let animChar = animatedCharacter {
                // Use actual animation completion for skeletal animation
                attackComplete = animChar.isAnimationComplete
            } else {
                // Use phase-based completion for procedural animation
                attackComplete = attackPhase >= 1.0
            }
            
            // Perform hit check partway through attack (at impact point ~40%)
            if !hasPerformedHitCheck && attackPhase >= 0.4 {
                performAttackHitCheck()
                hasPerformedHitCheck = true
            }
            
            if attackComplete {
                // Attack finished
                isAttacking = false
                attackPhase = 0
                attackCooldown = effectiveAttackCooldown
                hasPerformedHitCheck = false
            }
        }
    }
    
    private func startAttack() {
        isAttacking = true
        attackPhase = 0
        
        // Play sword swing sound
        AudioManager.shared.playSwordSwing()
        
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
                // Hit! Play metal hit sound
                AudioManager.shared.playMetalHit()
                
                // Calculate damage
                let baseDamage = player.effectiveDamage
                let isCritical = Float.random(in: 0...1) < 0.15  // 15% crit chance
                let damage = isCritical ? baseDamage * 2 : baseDamage
                
                let actualDamage = enemy.takeDamage(damage)
                
                // Show damage number
                enemyManager.addDamageNumber(actualDamage, at: enemy.position, isCritical: isCritical)
                
                print("[Combat] Hit \(enemy.type.rawValue) for \(actualDamage) damage\(isCritical ? " (CRITICAL!)" : "")")
                
                // Check if enemy died
                if !enemy.isAlive {
                    // Play death sound
                    AudioManager.shared.playDie()
                    
                    // Give XP and gold (scaled by enemy level)
                    player.gainXP(enemy.xpReward)
                    let goldDrop = Int.random(in: enemy.goldDropRange)
                    player.inventory.addGold(goldDrop)
                    print("[Combat] \(enemy.displayName) defeated! +\(enemy.xpReward) XP, +\(goldDrop) gold")
                    
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
        // Check if game is paused (menus open)
        let isPaused = hudViewModel?.isGamePaused ?? false
        
        if !isPaused {
            // Update enemy AI and animation (only when not paused)
            enemyManager.update(deltaTime: dt, playerPosition: characterPosition, terrain: Terrain.shared)
            
            // Try to respawn enemies if needed
            tryRespawnEnemies(deltaTime: dt)
            
            // Check if any enemy is attacking the player
            let enemyHits = enemyManager.checkEnemyAttacks(playerPosition: characterPosition)
            for (enemy, damage) in enemyHits {
                // Check for shield block
                let blockChance = player.effectiveBlockChance
                let blockRoll = Int.random(in: 1...100)
                
                if blockRoll <= blockChance {
                    // Blocked! Show floating "Blocked!" text like damage numbers
                    enemyManager.addBlockIndicator(at: characterPosition)
                    print("[Combat] BLOCKED attack from \(enemy.displayName)! (Roll: \(blockRoll) <= \(blockChance)%)")
                } else {
                    // Player takes damage (armor already reduces in takeDamage)
                    player.takeDamage(damage)
                    
                    // Play hurt sound
                    AudioManager.shared.playHurt()
                    
                    // Show damage number on player
                    enemyManager.addDamageNumber(damage, at: characterPosition)
                    
                    print("[Combat] Player hit by \(enemy.type.rawValue) for \(damage) damage! HP: \(player.vitals.currentHP)/\(player.effectiveMaxHP)")
                    
                    // Update HUD
                    Task { @MainActor in
                        hudViewModel?.update()
                    }
                }
            }
        }
        
        // Clean up dead enemies (always run to avoid buildup)
        enemyManager.removeDeadEnemies()
        
        // Update skeletal animation for enemies
        if useSkeletalEnemies {
            for enemy in enemyManager.enemies {
                if let animatedEnemy = getAnimatedEnemy(for: enemy) {
                    updateEnemyAnimationState(animatedEnemy: animatedEnemy, enemy: enemy)
                    animatedEnemy.update(deltaTime: dt)
                }
            }
            
            // Clean up animated enemies for removed enemies
            cleanupAnimatedEnemies()
        }
    }
    
    /// Project world position to screen position (in SwiftUI points, not pixels)
    private func worldToScreen(_ worldPos: simd_float3) -> CGPoint? {
        let vp = projectionMatrix * viewMatrix
        let clipPos = vp * simd_float4(worldPos.x, worldPos.y, worldPos.z, 1.0)
        
        // Behind camera check
        if clipPos.w <= 0 { return nil }
        
        // Normalized device coordinates
        let ndcX = clipPos.x / clipPos.w
        let ndcY = clipPos.y / clipPos.w
        
        // Get the actual view size in points (not pixels)
        // viewportSize is in pixels, so divide by content scale for SwiftUI coordinates
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        let viewWidth = viewportSize.width / scaleFactor
        let viewHeight = viewportSize.height / scaleFactor
        
        // Screen coordinates (0,0 is top-left in SwiftUI)
        let screenX = (ndcX + 1) * 0.5 * Float(viewWidth)
        let screenY = (1 - ndcY) * 0.5 * Float(viewHeight)  // Flip Y
        
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
        
        // Update enemy health bars
        updateEnemyHealthBarsDisplay()
    }
    
    /// Update HUD with enemy health bars (for damaged enemies)
    private func updateEnemyHealthBarsDisplay() {
        var healthBars: [EnemyHealthBar] = []
        
        for enemy in enemyManager.enemies {
            // Only show health bars for alive enemies that have been damaged recently (within 5 seconds)
            guard enemy.isAlive && enemy.lastDamageTime < 5.0 && enemy.hpPercentage < 1.0 else { continue }
            
            // Position above enemy's head
            let barPosition = enemy.position + simd_float3(0, 2.2, 0)
            
            guard let screenPos = worldToScreen(barPosition) else { continue }
            
            // Fade out over the last second
            let opacity: Double
            if enemy.lastDamageTime > 4.0 {
                opacity = Double(5.0 - enemy.lastDamageTime)
            } else {
                opacity = 1.0
            }
            
            let bar = EnemyHealthBar(
                id: enemy.id,
                screenPosition: screenPos,
                hpPercentage: enemy.hpPercentage,
                opacity: opacity,
                name: enemy.displayName
            )
            healthBars.append(bar)
        }
        
        Task { @MainActor in
            hudViewModel?.updateEnemyHealthBars(healthBars)
            hudViewModel?.updatePlayerPosition(x: characterPosition.x, y: characterPosition.y, z: characterPosition.z)
        }
    }
    
    private func updateCamera(deltaTime dt: Float) {
        // Camera stays directly behind the character (over-the-shoulder)
        // Character forward direction: (sin(yaw), 0, -cos(yaw))
        // Camera should be behind, so we negate the forward direction
        
        // Calculate camera direction (from character to camera)
        let cameraDirX = -sin(characterYaw)
        let cameraDirZ = cos(characterYaw)
        
        // Check for obstructions between character and camera
        // Start with full camera distance, reduce if obstructed
        var effectiveDistance = cameraDistance
        
        // Ray from character to camera position (in 2D, X-Z plane)
        let characterPos2D = simd_float2(characterPosition.x, characterPosition.z)
        let rayDir = simd_float2(cameraDirX, cameraDirZ)
        
        let minDistance: Float = 2.0  // Minimum camera distance
        
        // Check against camera blockers (trees with their foliage radius)
        for blocker in cameraBlockers {
            // Vector from character to blocker
            let toBlocker = blocker.position - characterPos2D
            
            // Project blocker center onto the camera ray
            let projLength = simd_dot(toBlocker, rayDir)
            
            // Only check objects between character and camera
            if projLength < 0.5 || projLength > effectiveDistance + blocker.radius { continue }
            
            // Find closest point on ray to blocker center
            let closestPointOnRay = characterPos2D + rayDir * projLength
            let distToCenter = simd_length(blocker.position - closestPointOnRay)
            
            // Check if ray passes through the blocker's visual area
            if distToCenter < blocker.radius {
                // Calculate where the ray enters the blocker
                let halfChord = sqrt(max(0, blocker.radius * blocker.radius - distToCenter * distToCenter))
                let enterDistance = projLength - halfChord
                
                // Reduce camera distance to just before the blocker
                if enterDistance > minDistance && enterDistance < effectiveDistance {
                    effectiveDistance = max(minDistance, enterDistance - 0.5)
                }
            }
        }
        
        // Calculate camera position with potentially reduced distance
        let offsetX = cameraDirX * effectiveDistance
        let offsetZ = cameraDirZ * effectiveDistance
        
        // Target camera position (behind and above the character)
        let targetCameraPos = simd_float3(
            characterPosition.x + offsetX,
            characterPosition.y + cameraHeight,
            characterPosition.z + offsetZ
        )
        
        // Smooth camera position follow (faster when avoiding obstacles)
        let positionSmoothness: Float = effectiveDistance < cameraDistance ? 25.0 : 12.0
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
    
    // MARK: - USD Model Loading
    
    /// Load the cabin USD model (medieval wooden house)
    // MARK: - Load Player Model (USD)
    
    /// Static player model data (when loaded from USDZ)
    private var playerModelVertexBuffer: MTLBuffer?
    private var playerModelVertexCount: Int = 0
    private var playerModelMatrix: simd_float4x4 = matrix_identity_float4x4
    private var playerModelTexture: MTLTexture?
    
    /// Load the player model from FBX (with skeleton and animations)
    private func loadPlayerModel() {
        let loader = USDModelLoader(device: device)
        
        // Try to find Walking.fbx (base character with walk animation)
        var playerURL: URL?
        
        // Try 1: USDZ format (exported from Blender or Reality Converter)
        if let url = Bundle.main.url(forResource: "Walking", withExtension: "usdz") {
            playerURL = url
            print("[Player] Found Walking.usdz directly in bundle")
        }
        // Try 2: USDZ in Animations subdirectory
        else if let url = Bundle.main.url(forResource: "Walking", withExtension: "usdz", subdirectory: "Animations") {
            playerURL = url
            print("[Player] Found Walking.usdz in Animations subdirectory")
        }
        // Try 3: GLB format
        else if let url = Bundle.main.url(forResource: "Walking", withExtension: "glb") {
            playerURL = url
            print("[Player] Found Walking.glb directly in bundle")
        }
        // Try 4: GLB in Animations subdirectory
        else if let url = Bundle.main.url(forResource: "Walking", withExtension: "glb", subdirectory: "Animations") {
            playerURL = url
            print("[Player] Found Walking.glb in Animations subdirectory")
        }
        // Try 5: FBX format
        else if let url = Bundle.main.url(forResource: "Walking", withExtension: "fbx") {
            playerURL = url
            print("[Player] Found Walking.fbx directly in bundle")
        }
        // Try 4: FBX in Animations subdirectory
        else if let url = Bundle.main.url(forResource: "Walking", withExtension: "fbx", subdirectory: "Animations") {
            playerURL = url
            print("[Player] Found Walking.fbx in Animations subdirectory")
        }
        // Try 6: Fallback to USDZ
        else if let url = Bundle.main.url(forResource: "player-model", withExtension: "usdz") {
            playerURL = url
            print("[Player] Falling back to player-model.usdz")
        }
        else if let url = Bundle.main.url(forResource: "player-model", withExtension: "usdz", subdirectory: "usdc") {
            playerURL = url
            print("[Player] Falling back to player-model.usdz in usdc subdirectory")
        }
        else {
            print("[Player] Could not find player model files in bundle")
            // Search for any FBX or USDZ files
            if let resourcePath = Bundle.main.resourcePath {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                    while let file = enumerator.nextObject() as? String {
                        if file.contains(".fbx") || file.contains(".usdz") {
                            print("[Player]   Found: \(file)")
                        }
                    }
                }
            }
            return
        }
        
        guard let finalURL = playerURL else { return }
        
        // Print the asset hierarchy for debugging
        loader.printAssetHierarchy(from: finalURL)
        
        // Try to load as skeletal mesh first
        let skeletalLoader = SkeletalMeshLoader(device: device)
        
        // First, try loading from the new Paladin animations
        var baseAnimationURL: URL? = nil
        
        // Try to find the idle animation as the base (it has the full mesh + skeleton)
        if let url = Bundle.main.url(forResource: "sword-and-shield-idle", withExtension: "usdz") {
            baseAnimationURL = url
            print("[Player] Found sword-and-shield-idle.usdz as base")
        } else if let url = Bundle.main.url(forResource: "sword-and-shield-idle", withExtension: "usdz", subdirectory: "Animations") {
            baseAnimationURL = url
            print("[Player] Found sword-and-shield-idle.usdz in Animations subdirectory")
        }
        
        // Use the new base animation URL if found, otherwise fall back to original
        let meshURL = baseAnimationURL ?? finalURL
        
        if let skeletalMesh = skeletalLoader.loadSkeletalMesh(from: meshURL, materialIndex: MaterialIndex.character.rawValue) {
            print("[Player] Successfully loaded skeletal mesh!")
            
            // Load additional animations from the Animations folder
            loadAdditionalAnimations(into: skeletalMesh, loader: skeletalLoader)
            
            animatedCharacter = AnimatedCharacter(device: device, mesh: skeletalMesh)
            
            // Calculate model transform based on bounds
            let bounds = skeletalMesh.boundingBox
            let modelSize = bounds.max - bounds.min
            let modelCenter = (bounds.max + bounds.min) / 2
            
            print("[Player] Model bounds: min=\(bounds.min), max=\(bounds.max)")
            print("[Player] Model size: \(modelSize)")
            
            // Detect coordinate system for Mixamo models:
            // - Y-up: min.y is near zero (feet on ground), max.y is positive (head)
            // - Z-up: min.z is near zero, max.z is positive
            // Don't use size comparison as characters with arms/weapons can be wider than tall
            let isYUp = abs(bounds.min.y) < abs(bounds.max.y) * 0.1 && bounds.max.y > bounds.max.z
            let isZUp = abs(bounds.min.z) < abs(bounds.max.z) * 0.1 && bounds.max.z > bounds.max.y
            
            if isYUp || (!isZUp && modelSize.y > 50) {
                // Y-up model (typical for Mixamo exports)
                let modelHeight = modelSize.y
                let targetHeight: Float = 2.0
                let scale = modelHeight > 0.001 ? targetHeight / modelHeight : 1.0
                let scaledMinHeight = bounds.min.y * scale
                
                playerModelMatrix = translation(0, -scaledMinHeight, 0) *
                                   rotationY(.pi) *
                                   scaling(scale, scale, scale) *
                                   translation(-modelCenter.x, 0, -modelCenter.z)
                
                print("[Player] Y-up skeletal model. Height: \(modelHeight), Scale: \(scale)")
            } else if isZUp {
                // Z-up model
                let modelHeight = modelSize.z
                let targetHeight: Float = 2.0
                let scale = modelHeight > 0.001 ? targetHeight / modelHeight : 1.0
                let scaledMinHeight = bounds.min.z * scale
                
                playerModelMatrix = translation(0, -scaledMinHeight, 0) *
                                   rotationY(.pi) *
                                   rotationX(.pi / 2) *
                                   scaling(scale, scale, scale) *
                                   translation(-modelCenter.x, -modelCenter.y, 0)
                
                print("[Player] Z-up skeletal model. Height: \(modelHeight), Scale: \(scale)")
            } else {
                // Fallback: assume Y-up for humanoid models
                let modelHeight = modelSize.y
                let targetHeight: Float = 2.0
                let scale = modelHeight > 0.001 ? targetHeight / modelHeight : 1.0
                let scaledMinHeight = bounds.min.y * scale
                
                playerModelMatrix = translation(0, -scaledMinHeight, 0) *
                                   rotationY(.pi) *
                                   scaling(scale, scale, scale) *
                                   translation(-modelCenter.x, 0, -modelCenter.z)
                
                print("[Player] Unknown orientation, assuming Y-up. Height: \(modelHeight), Scale: \(scale)")
            }
            
            playerModelTexture = characterTexture
            useSkeletalAnimation = true
            
            print("[Player] ✅ Skeletal animation enabled with \(skeletalMesh.bones.count) bones!")
            print("[Player] ✅ Loaded \(skeletalMesh.animations.count) animations")
            return
        }
        
        // Fallback: Load as static mesh
        print("[Player] Falling back to static mesh loading...")
        if let model = loader.loadModel(from: finalURL, materialIndex: MaterialIndex.character.rawValue) {
            playerModelVertexBuffer = model.vertexBuffer
            playerModelVertexCount = model.vertexCount
            
            // Calculate scale and orientation fix
            let bounds = model.boundingBox
            let modelSize = bounds.max - bounds.min
            let modelCenter = (bounds.max + bounds.min) / 2
            
            print("[Player] Model bounds: min=\(bounds.min), max=\(bounds.max)")
            print("[Player] Model size: \(modelSize)")
            print("[Player] Vertex count: \(model.vertexCount)")
            
            // Check which axis is tallest to determine up-axis
            let isYUp = modelSize.y > modelSize.z && modelSize.y > modelSize.x
            let isZUp = modelSize.z > modelSize.y && modelSize.z > modelSize.x
            
            let modelHeight: Float
            let scaledMinHeight: Float
            
            if isYUp {
                // Model uses Y-up (like Blender export)
                modelHeight = modelSize.y
                let targetHeight: Float = 2.0
                let scale = modelHeight > 0.001 ? targetHeight / modelHeight : 1.0
                scaledMinHeight = bounds.min.y * scale
                
                // Y-up: no rotation needed, just scale and position
                playerModelMatrix = translation(0, -scaledMinHeight, 0) *  // Lift so feet are at ground
                                   rotationY(.pi) *                        // Face forward
                                   scaling(scale, scale, scale) *
                                   translation(-modelCenter.x, 0, -modelCenter.z)  // Center horizontally
                
                print("[Player] Y-up model. Scale: \(scale), modelHeight: \(modelHeight)")
            } else if isZUp {
                // Model uses Z-up (like some other software)
                modelHeight = modelSize.z
                let targetHeight: Float = 2.0
                let scale = modelHeight > 0.001 ? targetHeight / modelHeight : 1.0
                scaledMinHeight = bounds.min.z * scale
                
                // Z-up: rotate 90 degrees around X
                playerModelMatrix = translation(0, -scaledMinHeight, 0) *
                                   rotationY(.pi) *
                                   rotationX(.pi / 2) *
                                   scaling(scale, scale, scale) *
                                   translation(-modelCenter.x, -modelCenter.y, 0)
                
                print("[Player] Z-up model. Scale: \(scale), modelHeight: \(modelHeight)")
            } else {
                // Fallback
                modelHeight = max(modelSize.x, max(modelSize.y, modelSize.z))
                let targetHeight: Float = 2.0
                let scale = modelHeight > 0.001 ? targetHeight / modelHeight : 1.0
                
                playerModelMatrix = scaling(scale, scale, scale)
                print("[Player] Unknown orientation. Scale: \(scale)")
            }
            
            // Use the existing character texture for now
            playerModelTexture = characterTexture
            
            useSkeletalAnimation = true  // Repurposing this flag to mean "use loaded model"
            
            print("[Player] ✅ Player model loaded with \(playerModelVertexCount) vertices")
        } else {
            print("[Player] Failed to load player model, using procedural character")
        }
    }
    
    /// Load additional animations from USDZ files in the bundle
    private func loadAdditionalAnimations(into mesh: SkeletalMesh, loader: SkeletalMeshLoader) {
        // List of animation files to load (name -> filename without extension)
        let animationFiles: [(name: String, filename: String)] = [
            // Idle animations
            ("sword-and-shield-idle", "sword-and-shield-idle"),
            ("sword-and-shield-idle-2", "sword-and-shield-idle-2"),
            ("sword-and-shield-idle-3", "sword-and-shield-idle-3"),
            ("sword-and-shield-idle-4", "sword-and-shield-idle-4"),
            
            // Walk/Run animations
            ("sword-and-shield-walk", "sword-and-shield-walk"),
            ("sword-and-shield-walk-2", "sword-and-shield-walk-2"),
            ("sword-and-shield-run", "sword-and-shield-run"),
            ("sword-and-shield-run-2", "sword-and-shield-run-2"),
            
            // Strafe animations
            ("sword-and-shield-strafe", "sword-and-shield-strafe"),
            ("sword-and-shield-strafe-2", "sword-and-shield-strafe-2"),
            ("sword-and-shield-strafe-3", "sword-and-shield-strafe-3"),
            ("sword-and-shield-strafe-4", "sword-and-shield-strafe-4"),
            
            // Attack animations (slashes and attacks)
            ("sword-and-shield-slash", "sword-and-shield-slash"),
            ("sword-and-shield-slash-2", "sword-and-shield-slash-2"),
            ("sword-and-shield-slash-3", "sword-and-shield-slash-3"),
            ("sword-and-shield-slash-4", "sword-and-shield-slash-4"),
            ("sword-and-shield-slash-5", "sword-and-shield-slash-5"),
            ("sword-and-shield-attack", "sword-and-shield-attack"),
            ("sword-and-shield-attack-2", "sword-and-shield-attack-2"),
            ("sword-and-shield-attack-3", "sword-and-shield-attack-3"),
            ("sword-and-shield-attack-4", "sword-and-shield-attack-4"),
            ("sword-and-shield-kick", "sword-and-shield-kick"),
            
            // Block animations
            ("sword-and-shield-block", "sword-and-shield-block"),
            ("sword-and-shield-block-2", "sword-and-shield-block-2"),
            ("sword-and-shield-block-idle", "sword-and-shield-block-idle"),
            
            // Crouch animations
            ("sword-and-shield-crouch", "sword-and-shield-crouch"),
            ("sword-and-shield-crouch-idle", "sword-and-shield-crouch-idle"),
            ("sword-and-shield-crouch-block", "sword-and-shield-crouch-block"),
            ("sword-and-shield-crouch-block-2", "sword-and-shield-crouch-block-2"),
            ("sword-and-shield-crouch-block-idle", "sword-and-shield-crouch-block-idle"),
            ("sword-and-shield-crouching", "sword-and-shield-crouching"),
            ("sword-and-shield-crouching-2", "sword-and-shield-crouching-2"),
            ("sword-and-shield-crouching-3", "sword-and-shield-crouching-3"),
            
            // Jump animations
            ("sword-and-shield-jump", "sword-and-shield-jump"),
            ("sword-and-shield-jump-2", "sword-and-shield-jump-2"),
            
            // Death animations
            ("sword-and-shield-death", "sword-and-shield-death"),
            ("sword-and-shield-death-2", "sword-and-shield-death-2"),
            
            // Impact/Hit reactions
            ("sword-and-shield-impact", "sword-and-shield-impact"),
            ("sword-and-shield-impact-2", "sword-and-shield-impact-2"),
            ("sword-and-shield-impact-3", "sword-and-shield-impact-3"),
            
            // Turn animations
            ("sword-and-shield-turn", "sword-and-shield-turn"),
            ("sword-and-shield-turn-2", "sword-and-shield-turn-2"),
            ("sword-and-shield-180-turn", "sword-and-shield-180-turn"),
            ("sword-and-shield-180-turn-2", "sword-and-shield-180-turn-2"),
            
            // Special animations
            ("sword-and-shield-casting", "sword-and-shield-casting"),
            ("sword-and-shield-casting-2", "sword-and-shield-casting-2"),
            ("sword-and-shield-power-up", "sword-and-shield-power-up"),
            
            // Draw/Sheath sword animations
            ("draw-sword-1", "draw-sword-1"),
            ("draw-sword-2", "draw-sword-2"),
            ("sheath-sword-1", "sheath-sword-1"),
            ("sheath-sword-2", "sheath-sword-2"),
        ]
        
        var loadedCount = 0
        
        for (name, filename) in animationFiles {
            // Skip if this animation was already loaded with the mesh
            if mesh.animations[name] != nil {
                continue
            }
            
            // Try to find the file in bundle
            var url: URL? = nil
            
            // Try directly in bundle
            if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "usdz") {
                url = bundleURL
            }
            // Try in Animations subdirectory
            else if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "usdz", subdirectory: "Animations") {
                url = bundleURL
            }
            
            if let animURL = url {
                if loader.loadAnimationIntoMesh(from: animURL, name: name, mesh: mesh) {
                    loadedCount += 1
                }
            }
        }
        
        print("[Player] Loaded \(loadedCount) additional animations")
        print("[Player] Available animations: \(mesh.animations.keys.sorted().joined(separator: ", "))")
    }
    
    // MARK: - Enemy Skeletal Animation Loading
    
    /// Load the enemy skeletal model
    private func loadEnemyModel() {
        let skeletalLoader = SkeletalMeshLoader(device: device)
        
        // Try to find the idle animation as the base (it has the full mesh + skeleton)
        var baseAnimationURL: URL? = nil
        
        // Try to find mutant-idle as the base enemy model
        if let url = Bundle.main.url(forResource: "mutant-idle", withExtension: "usdz") {
            baseAnimationURL = url
            print("[Enemy] Found mutant-idle.usdz as base")
        } else if let url = Bundle.main.url(forResource: "mutant-idle", withExtension: "usdz", subdirectory: "Animations") {
            baseAnimationURL = url
            print("[Enemy] Found mutant-idle.usdz in Animations subdirectory")
        }
        
        guard let meshURL = baseAnimationURL else {
            print("[Enemy] Could not find mutant-idle.usdz")
            // List available enemy animation files
            if let resourcePath = Bundle.main.resourcePath {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                    print("[Enemy] Searching bundle for mutant files...")
                    while let file = enumerator.nextObject() as? String {
                        if file.lowercased().contains("mutant") {
                            print("[Enemy]   Found: \(file)")
                        }
                    }
                }
            }
            return
        }
        
        if let skeletalMesh = skeletalLoader.loadSkeletalMesh(from: meshURL, materialIndex: MaterialIndex.enemy.rawValue) {
            print("[Enemy] Successfully loaded skeletal mesh!")
            
            // Load additional enemy animations
            loadEnemyAnimations(into: skeletalMesh, loader: skeletalLoader)
            
            // Store the mesh
            enemySkeletalMesh = skeletalMesh
            
            // Calculate model transform based on bounds
            let bounds = skeletalMesh.boundingBox
            let modelSize = bounds.max - bounds.min
            let modelCenter = (bounds.max + bounds.min) / 2
            
            print("[Enemy] Model bounds: min=\(bounds.min), max=\(bounds.max)")
            print("[Enemy] Model size: \(modelSize)")
            
            // Detect coordinate system (same as player)
            let isYUp = abs(bounds.min.y) < abs(bounds.max.y) * 0.1 && bounds.max.y > bounds.max.z
            
            let modelHeight: Float
            let targetHeight: Float = 2.2  // Enemies slightly taller than player
            
            if isYUp {
                modelHeight = modelSize.y
            } else {
                modelHeight = modelSize.z
            }
            
            enemyModelScale = modelHeight > 0.001 ? targetHeight / modelHeight : 1.0
            let scaledMinHeight = (isYUp ? bounds.min.y : bounds.min.z) * enemyModelScale
            
            if isYUp {
                enemyModelMatrix = translation(0, -scaledMinHeight, 0) *
                                   rotationY(.pi) *
                                   scaling(enemyModelScale, enemyModelScale, enemyModelScale) *
                                   translation(-modelCenter.x, 0, -modelCenter.z)
            } else {
                enemyModelMatrix = translation(0, -scaledMinHeight, 0) *
                                   rotationY(.pi) *
                                   rotationX(.pi / 2) *
                                   scaling(enemyModelScale, enemyModelScale, enemyModelScale) *
                                   translation(-modelCenter.x, -modelCenter.y, 0)
            }
            
            useSkeletalEnemies = true
            
            print("[Enemy] ✅ Skeletal animation enabled with \(skeletalMesh.bones.count) bones!")
            print("[Enemy] ✅ Loaded \(skeletalMesh.animations.count) animations")
            print("[Enemy] Model scale: \(enemyModelScale)")
            if skeletalMesh.texture != nil {
                print("[Enemy] ✅ Texture loaded from USDZ")
            } else {
                print("[Enemy] ⚠️ No texture in USDZ, will use fallback texture")
            }
        } else {
            print("[Enemy] Failed to load skeletal mesh, using procedural enemies")
        }
    }
    
    /// Load additional enemy animations from USDZ files
    private func loadEnemyAnimations(into mesh: SkeletalMesh, loader: SkeletalMeshLoader) {
        // List of enemy animation files
        let animationFiles: [(name: String, filename: String)] = [
            // Idle animations
            ("mutant-idle", "mutant-idle"),
            ("mutant-idle-2", "mutant-idle-2"),
            ("mutant-breathing-idle", "mutant-breathing-idle"),
            
            // Movement animations
            ("mutant-walking", "mutant-walking"),
            ("mutant-run", "mutant-run"),
            
            // Attack animations
            ("mutant-punch", "mutant-punch"),
            ("mutant-swiping", "mutant-swiping"),
            ("mutant-jump-attack", "mutant-jump-attack"),
            
            // Roar/aggro animations
            ("mutant-roaring", "mutant-roaring"),
            ("mutant-flexing-muscles", "mutant-flexing-muscles"),
            
            // Death animation
            ("mutant-dying", "mutant-dying"),
            
            // Jump animations
            ("mutant-jumping", "mutant-jumping"),
            ("mutant-jumping-2", "mutant-jumping-2"),
            
            // Turn animations
            ("mutant-left-turn-45", "mutant-left-turn-45"),
            ("mutant-right-turn-45", "mutant-right-turn-45"),
            ("mutant-right-turn-45-2", "mutant-right-turn-45-2"),
            ("mutant-right-turn-90", "mutant-right-turn-90"),
        ]
        
        var loadedCount = 0
        
        for (name, filename) in animationFiles {
            // Skip if already loaded
            if mesh.animations[name] != nil {
                continue
            }
            
            // Try to find the file in bundle
            var url: URL? = nil
            
            // Try directly in bundle
            if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "usdz") {
                url = bundleURL
            }
            // Try in Animations subdirectory
            else if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "usdz", subdirectory: "Animations") {
                url = bundleURL
            }
            
            if let animURL = url {
                if loader.loadAnimationIntoMesh(from: animURL, name: name, mesh: mesh) {
                    loadedCount += 1
                }
            }
        }
        
        print("[Enemy] Loaded \(loadedCount) additional animations")
        print("[Enemy] Available animations: \(mesh.animations.keys.sorted().joined(separator: ", "))")
    }
    
    /// Create or get an AnimatedEnemy instance for a given enemy
    private func getAnimatedEnemy(for enemy: Enemy) -> AnimatedEnemy? {
        if let existing = animatedEnemies[enemy.id] {
            return existing
        }
        
        guard let mesh = enemySkeletalMesh else { return nil }
        
        let animatedEnemy = AnimatedEnemy(device: device, mesh: mesh)
        animatedEnemies[enemy.id] = animatedEnemy
        return animatedEnemy
    }
    
    /// Update animation state for an enemy based on its AI state
    private func updateEnemyAnimationState(animatedEnemy: AnimatedEnemy, enemy: Enemy) {
        let newState: EnemyAnimationState
        
        switch enemy.state {
        case .idle:
            newState = .idle
        case .patrolling:
            newState = .walking
        case .chasing:
            newState = .running
        case .attacking:
            newState = .attacking
        case .hurt:
            newState = .hurt
        case .dead:
            if animatedEnemy.animationState == .dying && animatedEnemy.isAnimationComplete {
                newState = .dead
            } else if animatedEnemy.animationState != .dying && animatedEnemy.animationState != .dead {
                newState = .dying
            } else {
                newState = animatedEnemy.animationState
            }
        }
        
        animatedEnemy.setAnimationState(newState)
    }
    
    /// Clean up animated enemies that are no longer needed
    private func cleanupAnimatedEnemies() {
        let activeEnemyIDs = Set(enemyManager.enemies.map { $0.id })
        
        // Remove animated enemies for dead enemies that have been removed from manager
        for enemyID in animatedEnemies.keys {
            if !activeEnemyIDs.contains(enemyID) {
                animatedEnemies.removeValue(forKey: enemyID)
            }
        }
    }
    
    private func loadCabinModel() {
        let loader = USDModelLoader(device: device)
        
        // Try to load the medieval wooden house model - check multiple possible locations
        var cabinURL: URL?
        
        // Try 1: Direct in bundle (if added as group, files are flattened)
        if let url = Bundle.main.url(forResource: "medieval_woodenhouse", withExtension: "usdc") {
            cabinURL = url
            print("[Cabin] Found medieval_woodenhouse.usdc directly in bundle: \(url.path)")
        }
        // Try 2: In usdc subdirectory (folder reference)
        else if let url = Bundle.main.url(forResource: "medieval_woodenhouse", withExtension: "usdc", subdirectory: "usdc") {
            cabinURL = url
            print("[Cabin] Found medieval_woodenhouse.usdc in usdc subdirectory: \(url.path)")
        }
        // Try 3: List what's actually in the bundle for debugging
        else {
            print("[Cabin] Could not find medieval_woodenhouse.usdc - searching bundle...")
            if let resourcePath = Bundle.main.resourcePath {
                let fileManager = FileManager.default
                if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                    while let file = enumerator.nextObject() as? String {
                        if file.contains("medieval") || file.contains("woodenhouse") || file.contains("usdc") {
                            print("[Cabin]   Found: \(file)")
                        }
                    }
                }
            }
            print("[Cabin] medieval_woodenhouse.usdc not found in bundle")
            return
        }
        
        guard let finalURL = cabinURL else { return }
        
        if let model = loader.loadModel(from: finalURL, materialIndex: MaterialIndex.cabin.rawValue) {
            cabinVertexBuffer = model.vertexBuffer
            cabinVertexCount = model.vertexCount
            
            // Position the cabin in the world
            // Scale and position based on bounds
            let bounds = model.boundingBox
            let modelSize = bounds.max - bounds.min
            let modelCenter = (bounds.max + bounds.min) / 2
            
            print("[Cabin] Model bounds: min=\(bounds.min), max=\(bounds.max)")
            print("[Cabin] Model size: \(modelSize), center: \(modelCenter)")
            print("[Cabin] Vertex count: \(model.vertexCount)")
            
            // Scale to reasonable size (about 15 units tall - 3x larger)
            // USD models can be in various units (cm, m, etc.) so we normalize
            let maxDimension = max(modelSize.x, max(modelSize.y, modelSize.z))
            let targetSize: Float = 15.0
            let scale = maxDimension > 0.001 ? targetSize / maxDimension : 1.0
            
            // Position near player spawn
            let terrainY = Terrain.heightAt(x: 8, z: 10)
            
            // After rotation, the model's Z extent becomes Y (height)
            // We need to lift the model so its bottom sits on the ground
            let scaledHeight = modelSize.z * scale  // Z becomes height after X rotation
            let liftOffset = scaledHeight / 2  // Lift by half the height to put bottom at ground
            
            let cabinPosition = simd_float3(8, terrainY + liftOffset, 10)
            
            // Create model matrix: translate to position, rotate to fix orientation (Z-up to Y-up),
            // scale, and center the model horizontally
            cabinModelMatrix = translation(cabinPosition.x, cabinPosition.y, cabinPosition.z) *
                               rotationX(.pi / 2) *  // Convert Z-up to Y-up (positive rotation)
                               scaling(scale, scale, scale) *
                               translation(-modelCenter.x, -modelCenter.y, -modelCenter.z)
            
            print("[Cabin] Loaded cabin model at position \(cabinPosition) with scale \(scale)")
        } else {
            print("[Cabin] Failed to load cabin model - file may not be in bundle")
        }
        
        // Note: The EXR texture "color_0C0C0C" is just a solid dark color placeholder
        // We use the generated fallback texture which has wood grain detail instead
        print("[Cabin] Using generated wood texture for cabin")
    }
    
    /// Draw the cabin model
    private func drawCabin(encoder: MTLRenderCommandEncoder, litUniforms: LitUniforms) {
        guard let vertexBuffer = cabinVertexBuffer, cabinVertexCount > 0 else { return }
        
        // Create uniforms with cabin's model matrix
        var cabinUniforms = litUniforms
        cabinUniforms.modelMatrix = cabinModelMatrix
        
        // Use dedicated cabin uniform buffer (not character's!)
        let bufferPtr = cabinUniformBuffer.contents().bindMemory(to: LitUniforms.self, capacity: 1)
        bufferPtr.pointee = cabinUniforms
        
        encoder.setVertexBuffer(cabinUniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(cabinUniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cabinVertexCount)
        
        // Restore landscape uniform buffer
        encoder.setVertexBuffer(litUniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(litUniformBuffer, offset: 0, index: 1)
    }
}
