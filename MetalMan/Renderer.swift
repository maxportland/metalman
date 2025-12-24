import Metal
import MetalKit
import simd

final class Renderer: NSObject, MTKViewDelegate {
    struct Vertex {
        var position: simd_float3
        var color: simd_float4
    }
    
    // MARK: - Isometric 3rd Person Camera System
    // 
    // For isometric games, movement is typically relative to SCREEN direction:
    // - Up arrow = move towards top of screen (negative Z in world)
    // - Down arrow = move towards bottom of screen (positive Z in world)
    // - Left arrow = move towards left of screen (negative X in world)
    // - Right arrow = move towards right of screen (positive X in world)
    //
    // The camera maintains a fixed offset from the character and always looks at them.
    
    // MARK: - Properties
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let depthStencilStateNoWrite: MTLDepthStencilState
    let depthStencilStateAlways: MTLDepthStencilState
    var library: MTLLibrary
    
    // Input from keyboard/touch
    var movementVector: simd_float2 = .zero  // x = left/right, y = forward/back
    var lookDelta: simd_float2 = .zero       // unused for isometric, but kept for future
    
    // Character state
    private var characterPosition: simd_float3 = .zero
    private var characterVelocity: simd_float3 = .zero  // Current velocity for smooth movement
    private var characterYaw: Float = 0  // Character facing direction (radians)
    private var targetYaw: Float = 0     // Target facing direction for smooth turning
    
    // Walking animation state
    private var walkPhase: Float = 0     // 0 to 2π, cycles during walking
    private var walkSpeed: Float = 12.0  // How fast the legs cycle (radians per unit distance)
    private var isMoving: Bool = false   // Track if character is currently moving
    
    // Movement configuration
    private let characterSpeed: Float = 6.0    // Max speed (units per second)
    private let acceleration: Float = 40.0     // How fast to reach max speed (snappier)
    private let deceleration: Float = 25.0     // How fast to stop
    private let turnSpeed: Float = 15.0        // How fast to turn (radians per second)
    
    // Camera configuration for isometric view
    // Camera sits at a fixed offset relative to world axes (not character facing)
    private var cameraPosition: simd_float3 = simd_float3(0, 8, 10)
    private let cameraHeight: Float = 8.0      // How high above character
    private let cameraDistance: Float = 10.0   // How far behind (in Z)
    private let cameraDamping: Float = 0.03    // Slower follow so landscape movement is visible
    
    private var viewportSize: CGSize = .zero
    
    // Projection and view matrices
    private var projectionMatrix = matrix_identity_float4x4
    private var viewMatrix = matrix_identity_float4x4
    
    // Buffers
    private var gridVertexBuffer: MTLBuffer
    private var gridVertexCount: Int = 0
    
    private var stickFigureVertexBuffer: MTLBuffer
    private var stickFigureVertexCount: Int = 0
    
    // Landscape elements for visual reference
    private var landscapeVertexBuffer: MTLBuffer
    private var landscapeVertexCount: Int = 0
    
    // Splash cube (startup spinner) - disabled for testing
    private var cubeVertexBuffer: MTLBuffer?
    private var cubeVertexCount: Int = 0
    private var showSplashCube: Bool = false  // Disabled for now
    private var cubeAngle: Float = 0 // radians
    private var cubeSpinsRemaining: Int = 3 // spin count
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    
    // Uniform buffer for MVP matrix
    private var uniformBuffer: MTLBuffer

    private var forceTriangleTest: Bool = false
    
    private static var didLogViewConfig = false
    
    // MARK: - Init
    
    init(device: MTLDevice, view: MTKView) {
        self.device = device
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = commandQueue
        
        // Create library from source
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
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
        """
        
        do {
            self.library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            fatalError("Failed to create library: \(error)")
        }
        
        // Create pipeline state
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        let vertexDescriptor = MTLVertexDescriptor()
        // position attribute 0 (float3) at offset 0
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // color attribute 1 (float4) at offset 12
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        // layout for buffer 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Renderer.Vertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
        
        // Depth stencil state
        let depthStencilDesc = MTLDepthStencilDescriptor()
        depthStencilDesc.depthCompareFunction = .less
        depthStencilDesc.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthStencilDesc) else {
            fatalError("Failed to create depth stencil state")
        }
        depthStencilState = depthState
        
        let depthStencilDescNoWrite = MTLDepthStencilDescriptor()
        depthStencilDescNoWrite.depthCompareFunction = .less
        depthStencilDescNoWrite.isDepthWriteEnabled = false
        guard let depthStateNoWrite = device.makeDepthStencilState(descriptor: depthStencilDescNoWrite) else {
            fatalError("Failed to create depth stencil state (no write)")
        }
        depthStencilStateNoWrite = depthStateNoWrite

        let depthAlwaysDesc = MTLDepthStencilDescriptor()
        depthAlwaysDesc.depthCompareFunction = .always
        depthAlwaysDesc.isDepthWriteEnabled = false
        guard let depthAlways = device.makeDepthStencilState(descriptor: depthAlwaysDesc) else {
            fatalError("Failed to create depth stencil state (always)")
        }
        depthStencilStateAlways = depthAlways
        
        // Create buffers
        (gridVertexBuffer, gridVertexCount) = Renderer.makeGridVertices(device: device)
        (stickFigureVertexBuffer, stickFigureVertexCount) = Renderer.makeStickFigureVertices(device: device)
        (cubeVertexBuffer, cubeVertexCount) = Renderer.makeCubeVertices(device: device)
        (landscapeVertexBuffer, landscapeVertexCount) = Renderer.makeLandscapeVertices(device: device)
        
        // Create uniform buffer large enough for 3 MVP matrices (grid, landscape, stick figure)
        uniformBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride * 3, options: [])!
        
        super.init()
        
        // Initialize stick figure animation (sets initial vertex data)
        updateStickFigureAnimation()
        
        // Setup view properties
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.15, green: 0.17, blue: 0.2, alpha: 1.0)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        // Note: delegate is set by the Coordinator in MetalGameView
        
        viewportSize = view.drawableSize
        
        // If viewport size is zero, use a default and wait for size change callback
        if viewportSize.width == 0 || viewportSize.height == 0 {
            viewportSize = CGSize(width: 1024, height: 768) // Default fallback
        }
        
        updateProjection(size: viewportSize)
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        updateProjection(size: size)
    }
    
    func draw(in view: MTKView) {
        // Update viewport size if it changed
        let currentSize = view.drawableSize
        if currentSize.width > 0 && currentSize.height > 0 && (viewportSize.width != currentSize.width || viewportSize.height != currentSize.height) {
            viewportSize = currentSize
            updateProjection(size: currentSize)
        }
        
        guard let drawable = view.currentDrawable else { return }
        guard let descriptor = view.currentRenderPassDescriptor else { return }
        
        // Time delta for animations
        let now = CACurrentMediaTime()
        
        // Ensure we have a valid projection matrix
        if viewportSize.width == 0 || viewportSize.height == 0 {
            lastFrameTime = now
            return
        }
        
        // Calculate delta time for frame-rate independent movement
        // Clamp to reasonable range to prevent huge jumps on first frame or after pause
        var dt = Float(now - lastFrameTime)
        dt = min(max(dt, 0.0), 0.1)  // Clamp between 0 and 100ms
        
        // Update character position from input
        updateCharacter(deltaTime: dt)
        
        // Update camera to follow character
        updateCamera(deltaTime: dt)
        
        // Build view matrix (camera looks at character)
        viewMatrix = buildViewMatrix()
        
        // VP matrix (view-projection)
        let vp = projectionMatrix * viewMatrix
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthStencilState)
        
        let matrixStride = MemoryLayout<simd_float4x4>.stride
        
        // Write all MVP matrices to uniform buffer at different offsets
        var gridMVP = vp  // Grid uses just view-projection (no model transform)
        var landscapeMVP = vp  // Landscape also uses just view-projection
        
        // Stick figure uses model transform (translate + rotate)
        let modelMatrix = translation(characterPosition.x, characterPosition.y, characterPosition.z) * rotationY(characterYaw)
        var stickFigureMVP = projectionMatrix * viewMatrix * modelMatrix
        
        // Copy matrices to buffer at different offsets
        memcpy(uniformBuffer.contents(), &gridMVP, matrixStride)
        memcpy(uniformBuffer.contents() + matrixStride, &landscapeMVP, matrixStride)
        memcpy(uniformBuffer.contents() + matrixStride * 2, &stickFigureMVP, matrixStride)
        
        // Draw grid (offset 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(gridVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridVertexCount)
        
        // Draw landscape elements (offset 1)
        encoder.setVertexBuffer(uniformBuffer, offset: matrixStride, index: 1)
        encoder.setVertexBuffer(landscapeVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: landscapeVertexCount)
        
        // Update animated stick figure vertices based on walk phase
        updateStickFigureAnimation()
        
        // Draw stick figure (offset 2)
        encoder.setVertexBuffer(uniformBuffer, offset: matrixStride * 2, index: 1)
        encoder.setDepthStencilState(depthStencilStateNoWrite)
        encoder.setVertexBuffer(stickFigureVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: stickFigureVertexCount)
        encoder.setDepthStencilState(depthStencilState)
        
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // Update last frame time for next frame's delta calculation
        lastFrameTime = now
    }
    
    // MARK: - Character & Camera Update
    
    /// Update character position based on input with smooth acceleration/deceleration
    /// Movement is relative to SCREEN/WORLD axes for isometric feel:
    /// - movementVector.x: left/right on screen = -X/+X in world
    /// - movementVector.y: up/down on screen = -Z/+Z in world
    private func updateCharacter(deltaTime dt: Float) {
        let inputLength = simd_length(movementVector)
        
        if inputLength > 0.001 {
            // Has input - accelerate towards target velocity
            isMoving = true
            
            // Convert screen-relative input to world movement direction
            let worldMoveDir = simd_float3(
                movementVector.x,   // Left/right maps to X
                0,                   // No vertical movement
                -movementVector.y    // Forward/back maps to -Z (up = forward = -Z)
            )
            
            // Normalize to prevent faster diagonal movement
            let dirLength = simd_length(worldMoveDir)
            let normalizedDir = dirLength > 0 ? worldMoveDir / dirLength : worldMoveDir
            
            // Target velocity at max speed
            let targetVelocity = normalizedDir * characterSpeed
            
            // Smoothly accelerate towards target velocity
            let velocityDiff = targetVelocity - characterVelocity
            let accelerationStep = acceleration * dt
            if simd_length(velocityDiff) < accelerationStep {
                characterVelocity = targetVelocity
            } else {
                characterVelocity += simd_normalize(velocityDiff) * accelerationStep
            }
            
            // Update target facing direction
            targetYaw = atan2f(normalizedDir.x, -normalizedDir.z)
            
        } else {
            // No input - decelerate to stop
            let currentSpeed = simd_length(characterVelocity)
            if currentSpeed > 0.01 {
                let decelerationStep = deceleration * dt
                if currentSpeed < decelerationStep {
                    characterVelocity = .zero
                    isMoving = false
                } else {
                    characterVelocity -= simd_normalize(characterVelocity) * decelerationStep
                }
            } else {
                characterVelocity = .zero
                isMoving = false
            }
        }
        
        // Apply velocity to position
        characterPosition += characterVelocity * dt
        
        // Keep character within the grid bounds (-9 to +9 to stay inside the posts)
        let boundMin: Float = -9.0
        let boundMax: Float = 9.0
        characterPosition.x = max(boundMin, min(boundMax, characterPosition.x))
        characterPosition.z = max(boundMin, min(boundMax, characterPosition.z))
        
        // Smoothly interpolate facing direction
        var yawDiff = targetYaw - characterYaw
        // Normalize angle difference to [-π, π]
        while yawDiff > .pi { yawDiff -= 2 * .pi }
        while yawDiff < -.pi { yawDiff += 2 * .pi }
        
        let maxTurnThisFrame = turnSpeed * dt
        if abs(yawDiff) < maxTurnThisFrame {
            characterYaw = targetYaw
        } else {
            characterYaw += (yawDiff > 0 ? 1 : -1) * maxTurnThisFrame
        }
        
        // Update walk animation phase based on distance traveled
        let distanceThisFrame = simd_length(characterVelocity) * dt
        if isMoving {
            walkPhase += distanceThisFrame * walkSpeed
            // Keep phase in [0, 2π]
            while walkPhase > 2 * .pi { walkPhase -= 2 * .pi }
        } else {
            // Gradually return walk phase to neutral (legs together)
            // Neutral is at phase 0 or π (legs vertical)
            let neutralPhase: Float = 0
            let phaseDiff = neutralPhase - walkPhase
            let returnSpeed: Float = 8.0 * dt
            if abs(phaseDiff) < returnSpeed || abs(phaseDiff) > 2 * .pi - returnSpeed {
                walkPhase = neutralPhase
            } else if walkPhase < .pi {
                walkPhase -= returnSpeed
                if walkPhase < 0 { walkPhase = 0 }
            } else {
                walkPhase += returnSpeed
                if walkPhase > 2 * .pi { walkPhase = 0 }
            }
        }
    }
    
    /// Update camera to smoothly follow the character
    /// Camera maintains a fixed offset behind/above the character
    private func updateCamera(deltaTime dt: Float) {
        // Target camera position: fixed offset from character in world space
        let targetPosition = simd_float3(
            characterPosition.x,                    // Follow character X
            characterPosition.y + cameraHeight,    // Above character
            characterPosition.z + cameraDistance   // Behind character (positive Z)
        )
        
        // Smoothly interpolate camera position for fluid following
        let smoothSpeed: Float = 5.0  // How quickly camera catches up
        let t = min(smoothSpeed * dt, 1.0)
        cameraPosition = simd_mix(cameraPosition, targetPosition, simd_float3(repeating: t))
    }
    
    /// Build view matrix: camera looks at character
    private func buildViewMatrix() -> simd_float4x4 {
        // Look at the character's center (slightly above feet)
        let lookTarget = characterPosition + simd_float3(0, 1.0, 0)
        return lookAt(eye: cameraPosition, center: lookTarget, up: simd_float3(0, 1, 0))
    }
    
    /// Update stick figure vertices with walking animation
    private func updateStickFigureAnimation() {
        var vertices: [Vertex] = []
        
        let bodyColor = simd_float4(1, 0.85, 0.1, 1)
        let circleColor = simd_float4(1, 0.6, 0.1, 1)
        
        // Walk animation parameters
        // Legs swing forward/back based on walkPhase
        // Left leg: sin(walkPhase), Right leg: sin(walkPhase + π) = -sin(walkPhase)
        let legSwingAmount: Float = 0.4  // How far legs swing forward/back
        let armSwingAmount: Float = 0.25 // How far arms swing (opposite to legs)
        
        let leftLegSwing = sin(walkPhase) * legSwingAmount
        let rightLegSwing = -sin(walkPhase) * legSwingAmount  // Opposite phase
        let leftArmSwing = -sin(walkPhase) * armSwingAmount   // Arms opposite to legs
        let rightArmSwing = sin(walkPhase) * armSwingAmount
        
        // Slight body bob while walking
        let bodyBob = abs(sin(walkPhase * 2)) * 0.05
        let bodyOffset = simd_float3(0, bodyBob, 0)
        
        // Head circle (static, just offset by body bob)
        let headRadius: Float = 0.3
        let headCenter = simd_float3(0, 1.8, 0) + bodyOffset
        let segments = 16
        var lastPoint = simd_float3(0, 0, 0)
        var firstPoint = simd_float3(0, 0, 0)
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let x = cos(angle) * headRadius
            let y = sin(angle) * headRadius
            let point = simd_float3(x, y, 0) + headCenter
            if i == 0 {
                firstPoint = point
            } else {
                vertices.append(Vertex(position: lastPoint, color: circleColor))
                vertices.append(Vertex(position: point, color: circleColor))
            }
            lastPoint = point
        }
        vertices.append(Vertex(position: lastPoint, color: circleColor))
        vertices.append(Vertex(position: firstPoint, color: circleColor))
        
        // Spine: from hip (0, 0.7, 0) to neck (0, 1.5, 0)
        let hip = simd_float3(0, 0.7, 0) + bodyOffset
        let neck = simd_float3(0, 1.5, 0) + bodyOffset
        vertices.append(Vertex(position: hip, color: bodyColor))
        vertices.append(Vertex(position: neck, color: bodyColor))
        
        // Arms with swing animation
        let leftShoulder = simd_float3(0, 1.4, 0) + bodyOffset
        let rightShoulder = simd_float3(0, 1.4, 0) + bodyOffset
        
        // Left arm swings forward/back in Z
        let leftElbow = simd_float3(-0.35, 1.15, leftArmSwing * 0.5) + bodyOffset
        let leftHand = simd_float3(-0.5, 0.9, leftArmSwing) + bodyOffset
        vertices.append(Vertex(position: leftShoulder, color: bodyColor))
        vertices.append(Vertex(position: leftElbow, color: bodyColor))
        vertices.append(Vertex(position: leftElbow, color: bodyColor))
        vertices.append(Vertex(position: leftHand, color: bodyColor))
        
        // Right arm
        let rightElbow = simd_float3(0.35, 1.15, rightArmSwing * 0.5) + bodyOffset
        let rightHand = simd_float3(0.5, 0.9, rightArmSwing) + bodyOffset
        vertices.append(Vertex(position: rightShoulder, color: bodyColor))
        vertices.append(Vertex(position: rightElbow, color: bodyColor))
        vertices.append(Vertex(position: rightElbow, color: bodyColor))
        vertices.append(Vertex(position: rightHand, color: bodyColor))
        
        // Legs with walking animation
        // Each leg has: hip -> knee -> foot
        // The leg swings from the hip, knee bends during stride
        
        // Left leg
        let leftHip = simd_float3(-0.15, 0.7, 0) + bodyOffset
        // Knee position: forward/back based on swing, height varies with bend
        let leftKneeBend = max(0, sin(walkPhase)) * 0.15  // Knee bends when leg is forward
        let leftKnee = simd_float3(-0.15, 0.35 + leftKneeBend, leftLegSwing * 0.6)
        // Foot position: follows the swing arc
        let leftFootHeight = max(0, sin(walkPhase)) * 0.1  // Foot lifts when swinging forward
        let leftFoot = simd_float3(-0.15, leftFootHeight, leftLegSwing)
        
        vertices.append(Vertex(position: leftHip, color: bodyColor))
        vertices.append(Vertex(position: leftKnee, color: bodyColor))
        vertices.append(Vertex(position: leftKnee, color: bodyColor))
        vertices.append(Vertex(position: leftFoot, color: bodyColor))
        
        // Right leg (opposite phase)
        let rightHip = simd_float3(0.15, 0.7, 0) + bodyOffset
        let rightKneeBend = max(0, -sin(walkPhase)) * 0.15  // Opposite phase
        let rightKnee = simd_float3(0.15, 0.35 + rightKneeBend, rightLegSwing * 0.6)
        let rightFootHeight = max(0, -sin(walkPhase)) * 0.1
        let rightFoot = simd_float3(0.15, rightFootHeight, rightLegSwing)
        
        vertices.append(Vertex(position: rightHip, color: bodyColor))
        vertices.append(Vertex(position: rightKnee, color: bodyColor))
        vertices.append(Vertex(position: rightKnee, color: bodyColor))
        vertices.append(Vertex(position: rightFoot, color: bodyColor))
        
        // Update the buffer
        stickFigureVertexCount = vertices.count
        vertices.withUnsafeBytes { ptr in
            memcpy(stickFigureVertexBuffer.contents(), ptr.baseAddress!, ptr.count)
        }
    }
    
    private func updateProjection(size: CGSize) {
        // Handle zero or invalid size
        guard size.width > 0 && size.height > 0 else {
            let defaultAspect: Float = 16.0 / 9.0
            projectionMatrix = perspectiveFovRH(fovYRadians: 45 * .pi / 180, aspectRatio: defaultAspect, nearZ: 0.1, farZ: 100)
            return
        }
        
        let aspect = Float(size.width / size.height)
        
        // Use a narrower FOV for more isometric feel
        projectionMatrix = perspectiveFovRH(fovYRadians: 45 * .pi / 180, aspectRatio: aspect, nearZ: 0.1, farZ: 100)
    }
    
    // MARK: - Static helpers for geometry
    
    private static func makeGridVertices(device: MTLDevice) -> (MTLBuffer, Int) {
        // Grid of lines from -10 to 10 on X and Z axes, Y=0 plane
        // Lines spaced by 1 unit
        var vertices: [Vertex] = []
        
        let gridMin: Int = -10
        let gridMax: Int = 10
        let gridColor = simd_float4(0.4, 0.4, 0.4, 1)
        
        for i in gridMin...gridMax {
            // Lines parallel to X axis (varying Z)
            vertices.append(Vertex(position: simd_float3(Float(gridMin), 0, Float(i)), color: gridColor))
            vertices.append(Vertex(position: simd_float3(Float(gridMax), 0, Float(i)), color: gridColor))
            
            // Lines parallel to Z axis (varying X)
            vertices.append(Vertex(position: simd_float3(Float(i), 0, Float(gridMin)), color: gridColor))
            vertices.append(Vertex(position: simd_float3(Float(i), 0, Float(gridMax)), color: gridColor))
        }
        
        let vertexCount = vertices.count
        let buffer = device.makeBuffer(bytes: vertices,
                                       length: MemoryLayout<Vertex>.stride * vertexCount,
                                       options: [])!
        return (buffer, vertexCount)
    }
    
    private static func makeStickFigureVertices(device: MTLDevice) -> (MTLBuffer, Int) {
        // Create a buffer large enough for the animated stick figure
        // The animated figure has: head (34), spine (2), arms (8), legs (8) = ~52 vertices
        // Allocate extra space for safety
        let maxVertices = 100
        let bufferSize = MemoryLayout<Vertex>.stride * maxVertices
        let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
        
        // Initial vertex count will be set by updateStickFigureAnimation()
        return (buffer, 0)
    }
    
    private static func makeLandscapeVertices(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [Vertex] = []
        
        // Colors for different elements
        let treeGreen = simd_float4(0.2, 0.7, 0.3, 1)
        let treeBrown = simd_float4(0.5, 0.3, 0.1, 1)
        let rockGray = simd_float4(0.5, 0.5, 0.55, 1)
        let postRed = simd_float4(0.9, 0.2, 0.2, 1)
        let postBlue = simd_float4(0.2, 0.4, 0.9, 1)
        let postYellow = simd_float4(0.9, 0.8, 0.2, 1)
        let postPurple = simd_float4(0.7, 0.2, 0.8, 1)
        
        // Helper to add a tree at position (wireframe cone + trunk)
        func addTree(at pos: simd_float3, height: Float = 2.5, radius: Float = 0.8) {
            // Trunk (vertical line)
            let trunkTop = pos + simd_float3(0, height * 0.4, 0)
            vertices.append(Vertex(position: pos, color: treeBrown))
            vertices.append(Vertex(position: trunkTop, color: treeBrown))
            
            // Cone (triangular wireframe from trunk top to apex)
            let apex = pos + simd_float3(0, height, 0)
            let segments = 6
            for i in 0..<segments {
                let angle1 = Float(i) / Float(segments) * 2 * .pi
                let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
                
                let p1 = trunkTop + simd_float3(cos(angle1) * radius, 0, sin(angle1) * radius)
                let p2 = trunkTop + simd_float3(cos(angle2) * radius, 0, sin(angle2) * radius)
                
                // Base edge
                vertices.append(Vertex(position: p1, color: treeGreen))
                vertices.append(Vertex(position: p2, color: treeGreen))
                
                // Edge to apex
                vertices.append(Vertex(position: p1, color: treeGreen))
                vertices.append(Vertex(position: apex, color: treeGreen))
            }
        }
        
        // Helper to add a rock/boulder (wireframe cube)
        func addRock(at pos: simd_float3, size: Float = 0.4) {
            let s = size
            let corners = [
                pos + simd_float3(-s, 0, -s),
                pos + simd_float3( s, 0, -s),
                pos + simd_float3( s, 0,  s),
                pos + simd_float3(-s, 0,  s),
                pos + simd_float3(-s, s * 1.5, -s),
                pos + simd_float3( s, s * 1.5, -s),
                pos + simd_float3( s, s * 1.5,  s),
                pos + simd_float3(-s, s * 1.5,  s),
            ]
            // Bottom edges
            let edges = [
                (0, 1), (1, 2), (2, 3), (3, 0),  // bottom
                (4, 5), (5, 6), (6, 7), (7, 4),  // top
                (0, 4), (1, 5), (2, 6), (3, 7)   // verticals
            ]
            for (a, b) in edges {
                vertices.append(Vertex(position: corners[a], color: rockGray))
                vertices.append(Vertex(position: corners[b], color: rockGray))
            }
        }
        
        // Helper to add a vertical post/pole with color
        func addPost(at pos: simd_float3, height: Float = 1.5, color: simd_float4) {
            let top = pos + simd_float3(0, height, 0)
            vertices.append(Vertex(position: pos, color: color))
            vertices.append(Vertex(position: top, color: color))
            
            // Add a small cross at top for visibility
            let crossSize: Float = 0.15
            vertices.append(Vertex(position: top + simd_float3(-crossSize, 0, 0), color: color))
            vertices.append(Vertex(position: top + simd_float3( crossSize, 0, 0), color: color))
            vertices.append(Vertex(position: top + simd_float3(0, 0, -crossSize), color: color))
            vertices.append(Vertex(position: top + simd_float3(0, 0,  crossSize), color: color))
        }
        
        // Place trees around the grid
        addTree(at: simd_float3(-7, 0, -5), height: 3.0, radius: 1.0)
        addTree(at: simd_float3(-5, 0, -8), height: 2.5, radius: 0.7)
        addTree(at: simd_float3(-3, 0, 6), height: 2.8, radius: 0.9)
        addTree(at: simd_float3(4, 0, -7), height: 3.2, radius: 1.1)
        addTree(at: simd_float3(6, 0, -4), height: 2.4, radius: 0.6)
        addTree(at: simd_float3(7, 0, 3), height: 2.9, radius: 0.85)
        addTree(at: simd_float3(2, 0, 8), height: 2.6, radius: 0.75)
        addTree(at: simd_float3(-6, 0, 4), height: 3.1, radius: 0.95)
        addTree(at: simd_float3(8, 0, -2), height: 2.3, radius: 0.65)
        addTree(at: simd_float3(-8, 0, -2), height: 2.7, radius: 0.8)
        
        // Place rocks scattered around
        addRock(at: simd_float3(-2, 0, -4), size: 0.35)
        addRock(at: simd_float3(3, 0, -3), size: 0.45)
        addRock(at: simd_float3(-4, 0, 2), size: 0.3)
        addRock(at: simd_float3(5, 0, 5), size: 0.5)
        addRock(at: simd_float3(-1, 0, 7), size: 0.4)
        addRock(at: simd_float3(1, 0, -6), size: 0.35)
        addRock(at: simd_float3(-5, 0, -3), size: 0.45)
        addRock(at: simd_float3(6, 0, -6), size: 0.38)
        
        // Place colored posts at corners and key positions for orientation
        addPost(at: simd_float3(0, 0, 0), height: 2.0, color: postYellow)      // Origin marker (tall yellow)
        addPost(at: simd_float3(-9, 0, -9), height: 1.8, color: postRed)       // Corner 1
        addPost(at: simd_float3( 9, 0, -9), height: 1.8, color: postBlue)      // Corner 2
        addPost(at: simd_float3(-9, 0,  9), height: 1.8, color: postPurple)    // Corner 3
        addPost(at: simd_float3( 9, 0,  9), height: 1.8, color: postRed)       // Corner 4
        
        // Additional posts along edges for reference
        addPost(at: simd_float3(0, 0, -9), height: 1.2, color: postBlue)       // North edge center
        addPost(at: simd_float3(0, 0,  9), height: 1.2, color: postPurple)     // South edge center
        addPost(at: simd_float3(-9, 0, 0), height: 1.2, color: postRed)        // West edge center
        addPost(at: simd_float3( 9, 0, 0), height: 1.2, color: postBlue)       // East edge center
        
        let vertexCount = vertices.count
        let buffer = device.makeBuffer(bytes: vertices,
                                       length: MemoryLayout<Vertex>.stride * vertexCount,
                                       options: [])!
        return (buffer, vertexCount)
    }
    
    private static func makeCubeVertices(device: MTLDevice) -> (MTLBuffer?, Int) {
        // 12 triangles, 36 vertices, each with position and color
        struct V { var p: simd_float3; var c: simd_float4 }
        let cRed = simd_float4(1,0,0,1)
        let cGreen = simd_float4(0,1,0,1)
        let cBlue = simd_float4(0,0,1,1)
        let cYellow = simd_float4(1,1,0,1)
        let cCyan = simd_float4(0,1,1,1)
        let cMagenta = simd_float4(1,0,1,1)
        let s: Float = 1.5 // size (increased from 0.8)
        // Define 6 faces, two triangles each
        var verts: [Vertex] = []
        func addTri(_ a: simd_float3, _ b: simd_float3, _ c: simd_float3, _ color: simd_float4) {
            verts.append(Vertex(position: a, color: color))
            verts.append(Vertex(position: b, color: color))
            verts.append(Vertex(position: c, color: color))
        }
        // Front (z = +s)
        addTri(simd_float3(-s,-s, s), simd_float3( s,-s, s), simd_float3( s, s, s), cRed)
        addTri(simd_float3(-s,-s, s), simd_float3( s, s, s), simd_float3(-s, s, s), cRed)
        // Back (z = -s)
        addTri(simd_float3( s,-s,-s), simd_float3(-s,-s,-s), simd_float3(-s, s,-s), cGreen)
        addTri(simd_float3( s,-s,-s), simd_float3(-s, s,-s), simd_float3( s, s,-s), cGreen)
        // Left (x = -s)
        addTri(simd_float3(-s,-s,-s), simd_float3(-s,-s, s), simd_float3(-s, s, s), cBlue)
        addTri(simd_float3(-s,-s,-s), simd_float3(-s, s, s), simd_float3(-s, s,-s), cBlue)
        // Right (x = +s)
        addTri(simd_float3( s,-s, s), simd_float3( s,-s,-s), simd_float3( s, s,-s), cYellow)
        addTri(simd_float3( s,-s, s), simd_float3( s, s,-s), simd_float3( s, s, s), cYellow)
        // Top (y = +s)
        addTri(simd_float3(-s, s, s), simd_float3( s, s, s), simd_float3( s, s,-s), cCyan)
        addTri(simd_float3(-s, s, s), simd_float3( s, s,-s), simd_float3(-s, s,-s), cCyan)
        // Bottom (y = -s)
        addTri(simd_float3(-s,-s,-s), simd_float3( s,-s,-s), simd_float3( s,-s, s), cMagenta)
        addTri(simd_float3(-s,-s,-s), simd_float3( s,-s, s), simd_float3(-s,-s, s), cMagenta)
        let count = verts.count
        let buf = device.makeBuffer(bytes: verts, length: MemoryLayout<Vertex>.stride * count, options: [])
        return (buf, count)
    }
}

// MARK: - Math helpers

func perspectiveFovRH(fovYRadians fovY: Float, aspectRatio aspect: Float, nearZ near: Float, farZ far: Float) -> simd_float4x4 {
    // Right handed coordinate system
    let yScale = 1 / tan(fovY * 0.5)
    let xScale = yScale / aspect
    let zRange = far - near
    let zScale = -(far + near) / zRange
    let wzScale = -2 * far * near / zRange
    
    return simd_float4x4(
        simd_float4(xScale,    0,       0,     0),
        simd_float4(0,       yScale,    0,     0),
        simd_float4(0,         0,    zScale,  -1),
        simd_float4(0,         0,   wzScale,  0)
    )
}

func lookAt(eye: simd_float3, center: simd_float3, up: simd_float3) -> simd_float4x4 {
    let z = simd_normalize(eye - center) // forward
    let x = simd_normalize(simd_cross(up, z))
    let y = simd_cross(z, x)
    
    let col0 = simd_float4(x.x, y.x, z.x, 0)
    let col1 = simd_float4(x.y, y.y, z.y, 0)
    let col2 = simd_float4(x.z, y.z, z.z, 0)
    let col3 = simd_float4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
    
    return simd_float4x4(columns: (col0, col1, col2, col3))
}
func rotationY(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4( c, 0,  s, 0),
        simd_float4( 0, 1,  0, 0),
        simd_float4(-s, 0,  c, 0),
        simd_float4( 0, 0,  0, 1)
    )
}

func rotationX(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4(1,  0, 0, 0),
        simd_float4(0,  c, -s, 0),
        simd_float4(0,  s,  c, 0),
        simd_float4(0,  0, 0, 1)
    )
}

func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        simd_float4(1,0,0,0),
        simd_float4(0,1,0,0),
        simd_float4(0,0,1,0),
        simd_float4(x,y,z,1)
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

