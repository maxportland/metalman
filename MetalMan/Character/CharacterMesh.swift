import Metal
import simd

/// Types of sword swings available
enum SwingType: Int, CaseIterable {
    case oberhaw = 0    // Overhead descending cut
    case mittelhaw = 1  // Horizontal slash
    case unterhaw = 2   // Upward cut
    case zornhaw = 3    // Diagonal 45-degree cut
    case thrust = 4     // Forward thrust/pierce
    
    var name: String {
        switch self {
        case .oberhaw: return "Oberhaw"
        case .mittelhaw: return "Mittelhaw"
        case .unterhaw: return "Unterhaw"
        case .zornhaw: return "Zornhaw"
        case .thrust: return "Thrust"
        }
    }
}

/// Generates and animates the 3D character mesh
class CharacterMesh {
    private let maxVertices = 2000
    let vertexBuffer: MTLBuffer
    private(set) var vertexCount: Int = 0
    
    init(device: MTLDevice) {
        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<TexturedVertex>.stride * maxVertices,
            options: .storageModeShared
        )!
    }
    
    /// Updates the character mesh with walking/jumping animation
    /// - Parameters:
    ///   - walkPhase: Current phase of the walking animation cycle
    ///   - isJumping: Whether the character is currently jumping
    ///   - hasSwordEquipped: Whether a sword is equipped in the right hand
    ///   - hasShieldEquipped: Whether a shield is equipped in the left hand
    ///   - isAttacking: Whether currently performing an attack
    ///   - attackPhase: Progress through attack animation (0 to 1)
    ///   - swingType: Type of sword swing being performed
    func update(walkPhase: Float, isJumping: Bool, hasSwordEquipped: Bool = false,
                hasShieldEquipped: Bool = false,
                isAttacking: Bool = false, attackPhase: Float = 0, swingType: SwingType = .mittelhaw) {
        var vertices: [TexturedVertex] = []
        
        // Animation parameters
        let legSwingAmount: Float = 0.5
        let armSwingAmount: Float = 0.35
        
        // Body bob during walking
        let bodyBob: Float = isJumping ? 0.0 : abs(sin(walkPhase * 2)) * 0.03
        
        // Material index for character (5)
        let matChar: UInt32 = MaterialIndex.character.rawValue
        
        // ========== BODY MOVEMENT DURING ATTACKS ==========
        // These modifiers affect torso, hips, and head
        var torsoTwist: Float = 0      // Rotation around Y axis (left/right twist)
        var torsoLean: Float = 0       // Forward/backward lean
        var torsoTilt: Float = 0       // Side-to-side tilt
        var hipShiftX: Float = 0       // Weight shift left/right
        var hipShiftZ: Float = 0       // Weight shift forward/back
        var shoulderDropRight: Float = 0 // Right shoulder drops during swing
        var headTurn: Float = 0        // Head follows the swing direction
        
        if isAttacking && !isJumping {
            let windUpT = min(attackPhase / 0.25, 1.0)
            let swingT = max(0, (attackPhase - 0.25) / 0.75)
            
            switch swingType {
            case .oberhaw:
                // Overhead cut - lean back then drive forward, rise on toes
                if attackPhase < 0.25 {
                    torsoLean = windUpT * 0.15           // Lean back during windup
                    shoulderDropRight = -windUpT * 0.08  // Raise right shoulder
                    hipShiftZ = windUpT * 0.05           // Shift weight back
                } else {
                    torsoLean = 0.15 - swingT * 0.35     // Drive forward
                    shoulderDropRight = -0.08 + swingT * 0.15 // Drop shoulder with swing
                    hipShiftZ = 0.05 - swingT * 0.12     // Weight forward
                }
                
            case .mittelhaw:
                // Horizontal slash - strong hip and torso rotation
                if attackPhase < 0.25 {
                    torsoTwist = windUpT * 0.4           // Twist right (wind up)
                    hipShiftX = windUpT * 0.08           // Weight shifts right
                    shoulderDropRight = windUpT * 0.05   // Right shoulder back
                    headTurn = windUpT * 0.2             // Look right
                } else {
                    torsoTwist = 0.4 - swingT * 0.8      // Twist left (follow through)
                    hipShiftX = 0.08 - swingT * 0.16     // Weight transfers left
                    shoulderDropRight = 0.05 - swingT * 0.12 // Shoulder comes forward
                    headTurn = 0.2 - swingT * 0.4        // Head follows
                    torsoTilt = swingT * 0.1             // Slight tilt into swing
                }
                
            case .unterhaw:
                // Upward cut - crouch then rise explosively
                if attackPhase < 0.25 {
                    torsoLean = -windUpT * 0.2           // Crouch forward
                    shoulderDropRight = windUpT * 0.1    // Right shoulder drops
                    hipShiftZ = -windUpT * 0.06          // Weight forward
                } else {
                    torsoLean = -0.2 + swingT * 0.3      // Rise up and back
                    shoulderDropRight = 0.1 - swingT * 0.15 // Shoulder rises
                    hipShiftZ = -0.06 + swingT * 0.1     // Weight back
                }
                
            case .zornhaw:
                // Diagonal wrath cut - combines rotation and lean
                if attackPhase < 0.25 {
                    torsoTwist = windUpT * 0.3           // Twist right
                    torsoLean = windUpT * 0.1            // Lean back slightly
                    shoulderDropRight = -windUpT * 0.06  // Raise shoulder
                    hipShiftX = windUpT * 0.06
                    headTurn = windUpT * 0.15
                } else {
                    torsoTwist = 0.3 - swingT * 0.6      // Twist through
                    torsoLean = 0.1 - swingT * 0.25      // Lean into strike
                    shoulderDropRight = -0.06 + swingT * 0.14 // Drop with power
                    hipShiftX = 0.06 - swingT * 0.12
                    headTurn = 0.15 - swingT * 0.3
                    torsoTilt = swingT * 0.08
                }
                
            case .thrust:
                // Forward thrust - lunge motion
                if attackPhase < 0.25 {
                    hipShiftZ = -windUpT * 0.04          // Slight pull back
                    torsoLean = windUpT * 0.05           // Coil slightly
                } else {
                    let lungeT = sin(swingT * .pi)
                    hipShiftZ = -0.04 + lungeT * 0.15    // Drive forward
                    torsoLean = 0.05 - lungeT * 0.2      // Lean into thrust
                    shoulderDropRight = lungeT * 0.08    // Shoulder extends
                }
            }
        }
        
        // Character dimensions with body movement applied
        let baseHipY: Float = 0.85 + bodyBob
        let hipY: Float = baseHipY
        let shoulderY: Float = 1.45 + bodyBob + shoulderDropRight * 0.5
        let neckY: Float = 1.55 + bodyBob
        let headY: Float = 1.75 + bodyBob
        
        // Apply hip shift for weight transfer
        let hipCenter = simd_float3(hipShiftX, hipY, hipShiftZ)
        
        // ========== HEAD ==========
        // Head follows swing direction slightly
        let headOffset = simd_float3(headTurn * 0.1 + hipShiftX * 0.5, 0, torsoLean * -0.15 + hipShiftZ * 0.5)
        addSphere(center: simd_float3(0, headY, 0) + headOffset, radius: 0.22, latSegments: 8, lonSegments: 12,
                  uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // ========== NECK ==========
        let neckBase = simd_float3(hipShiftX * 0.8, shoulderY, hipShiftZ * 0.8 - torsoLean * 0.1)
        let neckTop = simd_float3(0, neckY, 0) + headOffset * 0.7
        addLimb(from: neckBase, to: neckTop,
                radius: 0.08, segments: 6, uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // ========== TORSO ==========
        // Torso with twist, lean, and tilt
        let torsoCenter = simd_float3(hipShiftX * 0.5, (hipY + shoulderY) / 2, hipShiftZ * 0.5 - torsoLean * 0.08)
        addRotatedBox(center: torsoCenter, size: simd_float3(0.4, shoulderY - hipY, 0.22),
                      yaw: torsoTwist, pitch: torsoLean, roll: torsoTilt,
                      uvYStart: 0.5, uvYEnd: 0.75, material: matChar, vertices: &vertices)
        
        // ========== ARMS ==========
        let shoulderWidth: Float = 0.25
        let upperArmLength: Float = 0.30
        let forearmLength: Float = 0.28
        
        // Shoulder positions affected by torso twist
        let leftShoulderOffset = simd_float3(
            -shoulderWidth * cos(torsoTwist) + hipShiftX * 0.8,
            shoulderY - 0.05 - torsoTilt * 0.05,
            -shoulderWidth * sin(torsoTwist) * 0.3 + hipShiftZ * 0.8 - torsoLean * 0.08
        )
        let rightShoulderOffset = simd_float3(
            shoulderWidth * cos(torsoTwist) + hipShiftX * 0.8 + shoulderDropRight * 0.1,
            shoulderY - 0.05 + shoulderDropRight + torsoTilt * 0.05,
            shoulderWidth * sin(torsoTwist) * 0.3 + hipShiftZ * 0.8 - torsoLean * 0.08
        )
        
        if isJumping {
            // Jumping arm pose: arms raised up and slightly bent
            // Left arm - raised up
            let leftShoulderPos = simd_float3(-shoulderWidth, shoulderY - 0.05, 0)
            let leftElbowPos = leftShoulderPos + simd_float3(-0.1, upperArmLength * 0.7, -0.05)
            let leftHandPos = leftElbowPos + simd_float3(-0.05, forearmLength * 0.5, 0.1)
            
            addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Shield in left hand (if equipped) - held in front during jump
            if hasShieldEquipped {
                addShield(at: leftHandPos, facingAngle: 0, isBlocking: false, vertices: &vertices)
            }
            
            // Right arm - raised up
            let rightShoulderPos = simd_float3(shoulderWidth, shoulderY - 0.05, 0)
            let rightElbowPos = rightShoulderPos + simd_float3(0.1, upperArmLength * 0.7, -0.05)
            let rightHandPos = rightElbowPos + simd_float3(0.05, forearmLength * 0.5, 0.1)
            
            addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Sword in right hand (if equipped) - held up during jump
            if hasSwordEquipped {
                addSword(at: rightHandPos, swingAngle: 0.5, vertices: &vertices)
            }
        } else {
            // Walking/attacking arm animation
            let leftArmSwing = sin(walkPhase) * armSwingAmount
            let rightArmSwing = -sin(walkPhase) * armSwingAmount
            
            // Left arm - follows body movement, counter-balances during attacks
            let leftShoulderPos = leftShoulderOffset
            var leftElbowOffset = simd_float3(-0.08, -0.30, leftArmSwing * 0.3)
            var leftHandOffset = simd_float3(-0.05, -0.30, leftArmSwing * 0.5)
            
            // Left arm counter-movement during attacks
            if isAttacking {
                let counterSwing = -torsoTwist * 0.5  // Counter-balance the twist
                leftElbowOffset.z += counterSwing * 0.2
                leftHandOffset.z += counterSwing * 0.3
                // Slight guard position during attack
                leftElbowOffset.y += 0.05
                leftElbowOffset.z -= 0.1
                leftHandOffset.y += 0.1
                leftHandOffset.z -= 0.15
            }
            
            let leftElbowPos = leftShoulderPos + leftElbowOffset
            let leftHandPos = leftElbowPos + leftHandOffset
            
            addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Shield in left hand (if equipped)
            if hasShieldEquipped {
                // Shield faces forward, slightly angled during attacks for guard position
                let shieldAngle = isAttacking ? -0.3 : leftArmSwing * 0.2
                addShield(at: leftHandPos, facingAngle: shieldAngle, isBlocking: isAttacking, vertices: &vertices)
            }
            
            // Right arm - with attack animation support
            let rightShoulderPos = rightShoulderOffset
            var rightElbowPos: simd_float3
            var rightHandPos: simd_float3
            var swordSwingAngle: Float = rightArmSwing
            
            if isAttacking && hasSwordEquipped {
                // Attack animation based on swing type
                let windUpPhase = min(attackPhase / 0.25, 1.0)       // 0-1 during wind up (25%)
                let swingPhase = max(0, (attackPhase - 0.25) / 0.75) // 0-1 during swing (75%)
                
                switch swingType {
                case .oberhaw:
                    // Overhead descending cut - arm raises high then chops down
                    if attackPhase < 0.25 {
                        let t = windUpPhase
                        rightElbowPos = rightShoulderPos + simd_float3(0.1, -0.1 + t * 0.35, -0.1 - t * 0.1)
                        rightHandPos = rightElbowPos + simd_float3(0.05, 0.1 + t * 0.25, -0.1)
                        swordSwingAngle = t * 0.3
                    } else {
                        let t = swingPhase
                        let downSwing = sin(t * .pi * 0.5)
                        rightElbowPos = rightShoulderPos + simd_float3(0.1, 0.25 - downSwing * 0.55, -0.2 - t * 0.2)
                        rightHandPos = rightElbowPos + simd_float3(0.05, 0.35 - downSwing * 0.7, -0.15 - t * 0.25)
                        swordSwingAngle = 0.3 - t * 0.6
                    }
                    
                case .mittelhaw:
                    // Horizontal slash - arm sweeps from right to left
                    if attackPhase < 0.25 {
                        let t = windUpPhase
                        rightElbowPos = rightShoulderPos + simd_float3(0.15 + t * 0.1, -0.2, 0.2 + t * 0.15)
                        rightHandPos = rightElbowPos + simd_float3(0.1 + t * 0.05, -0.15, 0.2 + t * 0.1)
                        swordSwingAngle = t * 0.5
                    } else {
                        let t = swingPhase
                        let sweep = sin(t * .pi)
                        rightElbowPos = rightShoulderPos + simd_float3(0.25 - t * 0.4, -0.2 - sweep * 0.05, 0.35 - t * 0.5)
                        rightHandPos = rightElbowPos + simd_float3(0.15 - t * 0.25, -0.15, 0.3 - t * 0.55)
                        swordSwingAngle = 0.5 - t * 1.5
                    }
                    
                case .unterhaw:
                    // Upward cut - arm swings from low to high
                    if attackPhase < 0.25 {
                        let t = windUpPhase
                        rightElbowPos = rightShoulderPos + simd_float3(0.12, -0.35 - t * 0.1, 0.1 + t * 0.1)
                        rightHandPos = rightElbowPos + simd_float3(0.08, -0.3 - t * 0.05, 0.15)
                        swordSwingAngle = -0.3 - t * 0.2
                    } else {
                        let t = swingPhase
                        let upSwing = sin(t * .pi * 0.6)
                        rightElbowPos = rightShoulderPos + simd_float3(0.12 - t * 0.05, -0.45 + upSwing * 0.5, 0.2 - t * 0.35)
                        rightHandPos = rightElbowPos + simd_float3(0.08, -0.35 + upSwing * 0.55, 0.15 - t * 0.4)
                        swordSwingAngle = -0.5 + t * 1.2
                    }
                    
                case .zornhaw:
                    // Diagonal 45-degree cut - powerful angled slash
                    if attackPhase < 0.25 {
                        let t = windUpPhase
                        rightElbowPos = rightShoulderPos + simd_float3(0.2 + t * 0.1, -0.1 + t * 0.2, 0.15 + t * 0.15)
                        rightHandPos = rightElbowPos + simd_float3(0.12, 0.05 + t * 0.15, 0.2 + t * 0.1)
                        swordSwingAngle = t * 0.4
                    } else {
                        let t = swingPhase
                        let diagSwing = sin(t * .pi * 0.7)
                        rightElbowPos = rightShoulderPos + simd_float3(0.3 - t * 0.35, 0.1 - diagSwing * 0.4, 0.3 - t * 0.5)
                        rightHandPos = rightElbowPos + simd_float3(0.12 - t * 0.15, 0.2 - diagSwing * 0.5, 0.3 - t * 0.55)
                        swordSwingAngle = 0.4 - t * 1.3
                    }
                    
                case .thrust:
                    // Forward thrust/pierce - arm extends straight forward
                    if attackPhase < 0.25 {
                        let t = windUpPhase
                        rightElbowPos = rightShoulderPos + simd_float3(0.1, -0.25, 0.15 + t * 0.1)
                        rightHandPos = rightElbowPos + simd_float3(0.05, -0.2, 0.1 + t * 0.05)
                        swordSwingAngle = 0
                    } else {
                        let t = swingPhase
                        let thrustExtend = sin(t * .pi)
                        rightElbowPos = rightShoulderPos + simd_float3(0.08, -0.2 - t * 0.05, 0.25 - thrustExtend * 0.15)
                        rightHandPos = rightElbowPos + simd_float3(0.03, -0.15, 0.15 - thrustExtend * 0.45)
                        swordSwingAngle = 0
                    }
                }
            } else {
                // Normal walking animation
                rightElbowPos = simd_float3(shoulderWidth + 0.08, shoulderY - 0.35, rightArmSwing * 0.3)
                rightHandPos = simd_float3(shoulderWidth + 0.05, shoulderY - 0.65, rightArmSwing * 0.5)
            }
            
            addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Sword in right hand (if equipped)
            if hasSwordEquipped {
                addSword(at: rightHandPos, swingAngle: swordSwingAngle, isAttacking: isAttacking, attackPhase: attackPhase, swingType: swingType, vertices: &vertices)
            }
        }
        
        // LEGS
        let legSeparation: Float = 0.12
        let thighLength: Float = 0.40
        let shinLength: Float = 0.38
        
        if isJumping {
            // Jumping leg pose: knees tucked up toward chest
            // Hip flexion angle (thigh rotates up toward chest) - about 70-80 degrees
            let hipFlexion: Float = 1.2  // radians (~70 degrees)
            // Knee flexion angle (shin folds back) - about 90-100 degrees
            let kneeFlexion: Float = 1.7  // radians (~100 degrees)
            
            // Left leg - tucked
            let leftHipPos = simd_float3(-legSeparation, hipY, 0)
            // Thigh goes forward and up (hip flexion)
            let leftThighDir = simd_float3(0, -cos(hipFlexion), -sin(hipFlexion))
            let leftKneePos = leftHipPos + leftThighDir * thighLength
            // Shin goes down and back from knee (knee flexion)
            // The shin direction is relative to thigh - it bends back
            let shinAngle = hipFlexion - (.pi - kneeFlexion)  // Combined angle from vertical
            let leftShinDir = simd_float3(0, -cos(shinAngle), -sin(shinAngle))
            let leftAnklePos = leftKneePos + leftShinDir * shinLength
            
            addLimb(from: leftHipPos, to: leftKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: leftKneePos, to: leftAnklePos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            // Foot points down/back when tucked
            let leftFootCenter = leftAnklePos + simd_float3(0, -0.05, 0.02)
            addBox(center: leftFootCenter, size: simd_float3(0.1, 0.06, 0.16),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            
            // Right leg - tucked (same pose)
            let rightHipPos = simd_float3(legSeparation, hipY, 0)
            let rightThighDir = simd_float3(0, -cos(hipFlexion), -sin(hipFlexion))
            let rightKneePos = rightHipPos + rightThighDir * thighLength
            let rightShinDir = simd_float3(0, -cos(shinAngle), -sin(shinAngle))
            let rightAnklePos = rightKneePos + rightShinDir * shinLength
            
            addLimb(from: rightHipPos, to: rightKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: rightKneePos, to: rightAnklePos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            let rightFootCenter = rightAnklePos + simd_float3(0, -0.05, 0.02)
            addBox(center: rightFootCenter, size: simd_float3(0.1, 0.06, 0.16),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        } else {
            // Walking/attacking leg animation
            var leftLegSwing = -sin(walkPhase) * legSwingAmount
            var rightLegSwing = sin(walkPhase) * legSwingAmount
            
            // Attack stance modifiers
            var leftHipOffset = simd_float3(0, 0, 0)
            var rightHipOffset = simd_float3(0, 0, 0)
            var leftKneeAdjust: Float = 0
            var rightKneeAdjust: Float = 0
            var stanceWiden: Float = 0
            
            if isAttacking {
                // Widen stance during attack
                stanceWiden = 0.04
                
                // Weight shift affects legs
                leftHipOffset.x = hipShiftX * 0.3
                rightHipOffset.x = hipShiftX * 0.3
                leftHipOffset.z = hipShiftZ * 0.5
                rightHipOffset.z = hipShiftZ * 0.5
                
                // Dampen leg swing during attack (more stable stance)
                leftLegSwing *= 0.3
                rightLegSwing *= 0.3
                
                // Bend knees more for power stance
                leftKneeAdjust = -0.03
                rightKneeAdjust = -0.03
                
                // Specific swing type leg adjustments
                switch swingType {
                case .mittelhaw:
                    // Horizontal slash - pivot on back foot
                    let swingT = max(0, (attackPhase - 0.25) / 0.75)
                    leftHipOffset.z -= swingT * 0.08  // Left foot plants
                    rightHipOffset.z += swingT * 0.05 // Right foot pivots
                    rightKneeAdjust -= swingT * 0.04  // Deeper knee bend
                case .thrust:
                    // Lunge forward
                    let swingT = max(0, (attackPhase - 0.25) / 0.75)
                    let lungeT = sin(swingT * .pi)
                    rightHipOffset.z -= lungeT * 0.15 // Right foot forward (lunge)
                    leftHipOffset.z += lungeT * 0.05  // Back foot planted
                    rightKneeAdjust -= lungeT * 0.06
                case .oberhaw:
                    // Overhead - rise up then stomp down
                    let swingT = max(0, (attackPhase - 0.25) / 0.75)
                    rightHipOffset.z -= swingT * 0.08
                    rightKneeAdjust -= swingT * 0.05
                case .unterhaw:
                    // Upward cut - crouch then rise
                    let windUpT = min(attackPhase / 0.25, 1.0)
                    let swingT = max(0, (attackPhase - 0.25) / 0.75)
                    if attackPhase < 0.25 {
                        leftKneeAdjust -= windUpT * 0.06  // Crouch
                        rightKneeAdjust -= windUpT * 0.06
                    } else {
                        leftKneeAdjust = -0.06 + swingT * 0.08  // Rise
                        rightKneeAdjust = -0.06 + swingT * 0.08
                    }
                case .zornhaw:
                    // Diagonal - weight transfer
                    let swingT = max(0, (attackPhase - 0.25) / 0.75)
                    rightHipOffset.z -= swingT * 0.06
                    leftHipOffset.x -= swingT * 0.04
                    rightKneeAdjust -= swingT * 0.03
                }
            }
            
            // Left leg with attack adjustments
            let leftHipPos = simd_float3(-legSeparation - stanceWiden, hipY, 0) + leftHipOffset
            let leftLegForward = max(0, -leftLegSwing / legSwingAmount)
            let leftKneeHeight = 0.45 + leftLegForward * 0.08 + leftKneeAdjust
            let leftKneePos = simd_float3(-legSeparation - stanceWiden, leftKneeHeight, leftLegSwing * 0.4) + leftHipOffset * 0.5
            let leftFootHeight: Float = 0.08 + leftLegForward * 0.12
            let leftFootPos = simd_float3(-legSeparation - stanceWiden, leftFootHeight, leftLegSwing * 0.6) + leftHipOffset * 0.3
            
            addLimb(from: leftHipPos, to: leftKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: leftKneePos, to: leftFootPos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addBox(center: leftFootPos + simd_float3(0, -0.03, -0.05), size: simd_float3(0.1, 0.06, 0.18),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            
            // Right leg with attack adjustments
            let rightHipPos = simd_float3(legSeparation + stanceWiden, hipY, 0) + rightHipOffset
            let rightLegForward = max(0, -rightLegSwing / legSwingAmount)
            let rightKneeHeight = 0.45 + rightLegForward * 0.08 + rightKneeAdjust
            let rightKneePos = simd_float3(legSeparation + stanceWiden, rightKneeHeight, rightLegSwing * 0.4) + rightHipOffset * 0.5
            let rightFootHeight: Float = 0.08 + rightLegForward * 0.12
            let rightFootPos = simd_float3(legSeparation + stanceWiden, rightFootHeight, rightLegSwing * 0.6) + rightHipOffset * 0.3
            
            addLimb(from: rightHipPos, to: rightKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: rightKneePos, to: rightFootPos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addBox(center: rightFootPos + simd_float3(0, -0.03, -0.05), size: simd_float3(0.1, 0.06, 0.18),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        }
        
        // Copy to buffer
        vertexCount = vertices.count
        _ = vertices.withUnsafeBytes { ptr in
            memcpy(vertexBuffer.contents(), ptr.baseAddress!, ptr.count)
        }
    }
    
    // MARK: - Primitive Generation Helpers
    
    private func addLimb(from start: simd_float3, to end: simd_float3, radius: Float, segments: Int,
                         uvYStart: Float, uvYEnd: Float, material: UInt32, vertices: inout [TexturedVertex]) {
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0.001 else { return }
        
        let forward = simd_normalize(direction)
        
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
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: br, normal: n2, texCoord: simd_float2(u2, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, uvYStart), materialIndex: material))
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: tl, normal: n1, texCoord: simd_float2(u1, uvYStart), materialIndex: material))
        }
    }
    
    private func addSphere(center: simd_float3, radius: Float, latSegments: Int, lonSegments: Int,
                           uvYStart: Float, uvYEnd: Float, material: UInt32, vertices: inout [TexturedVertex]) {
        for lat in 0..<latSegments {
            let theta1 = Float(lat) / Float(latSegments) * .pi
            let theta2 = Float(lat + 1) / Float(latSegments) * .pi
            
            for lon in 0..<lonSegments {
                let phi1 = Float(lon) / Float(lonSegments) * 2 * .pi
                let phi2 = Float(lon + 1) / Float(lonSegments) * 2 * .pi
                
                let p1 = center + radius * simd_float3(sin(theta1) * cos(phi1), cos(theta1), sin(theta1) * sin(phi1))
                let p2 = center + radius * simd_float3(sin(theta1) * cos(phi2), cos(theta1), sin(theta1) * sin(phi2))
                let p3 = center + radius * simd_float3(sin(theta2) * cos(phi2), cos(theta2), sin(theta2) * sin(phi2))
                let p4 = center + radius * simd_float3(sin(theta2) * cos(phi1), cos(theta2), sin(theta2) * sin(phi1))
                
                let n1 = simd_normalize(p1 - center)
                let n2 = simd_normalize(p2 - center)
                let n3 = simd_normalize(p3 - center)
                let n4 = simd_normalize(p4 - center)
                
                let u1 = Float(lon) / Float(lonSegments)
                let u2 = Float(lon + 1) / Float(lonSegments)
                let v1 = uvYStart + (uvYEnd - uvYStart) * Float(lat) / Float(latSegments)
                let v2 = uvYStart + (uvYEnd - uvYStart) * Float(lat + 1) / Float(latSegments)
                
                vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: material))
                vertices.append(TexturedVertex(position: p2, normal: n2, texCoord: simd_float2(u2, v1), materialIndex: material))
                vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: material))
                
                vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: material))
                vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: material))
                vertices.append(TexturedVertex(position: p4, normal: n4, texCoord: simd_float2(u1, v2), materialIndex: material))
            }
        }
    }
    
    private func addBox(center: simd_float3, size: simd_float3, uvYStart: Float, uvYEnd: Float,
                        material: UInt32, vertices: inout [TexturedVertex]) {
        // Delegate to rotated version with no rotation
        addRotatedBox(center: center, size: size, yaw: 0, pitch: 0, roll: 0,
                      uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices)
    }
    
    /// Add a box with rotation (yaw = Y axis, pitch = X axis, roll = Z axis)
    private func addRotatedBox(center: simd_float3, size: simd_float3, yaw: Float, pitch: Float, roll: Float,
                               uvYStart: Float, uvYEnd: Float, material: UInt32, vertices: inout [TexturedVertex]) {
        let hw = size.x / 2
        let hh = size.y / 2
        let hd = size.z / 2
        
        // Helper to rotate a point around center
        func rotatePoint(_ p: simd_float3) -> simd_float3 {
            var result = p
            
            // Apply rotations: yaw (Y), pitch (X), roll (Z)
            // Yaw rotation (around Y axis)
            let cosY = cos(yaw)
            let sinY = sin(yaw)
            let x1 = result.x * cosY + result.z * sinY
            let z1 = -result.x * sinY + result.z * cosY
            result.x = x1
            result.z = z1
            
            // Pitch rotation (around X axis)
            let cosP = cos(pitch)
            let sinP = sin(pitch)
            let y2 = result.y * cosP - result.z * sinP
            let z2 = result.y * sinP + result.z * cosP
            result.y = y2
            result.z = z2
            
            // Roll rotation (around Z axis)
            let cosR = cos(roll)
            let sinR = sin(roll)
            let x3 = result.x * cosR - result.y * sinR
            let y3 = result.x * sinR + result.y * cosR
            result.x = x3
            result.y = y3
            
            return result
        }
        
        func rotateNormal(_ n: simd_float3) -> simd_float3 {
            return simd_normalize(rotatePoint(n))
        }
        
        // Define corners in local space
        let corners: [simd_float3] = [
            simd_float3(-hw, -hh, -hd),  // 0: back-bottom-left
            simd_float3(hw, -hh, -hd),   // 1: back-bottom-right
            simd_float3(hw, hh, -hd),    // 2: back-top-right
            simd_float3(-hw, hh, -hd),   // 3: back-top-left
            simd_float3(-hw, -hh, hd),   // 4: front-bottom-left
            simd_float3(hw, -hh, hd),    // 5: front-bottom-right
            simd_float3(hw, hh, hd),     // 6: front-top-right
            simd_float3(-hw, hh, hd),    // 7: front-top-left
        ]
        
        // Rotate and translate corners
        let rotatedCorners = corners.map { center + rotatePoint($0) }
        
        // Front face (Z+)
        addQuad(
            bl: rotatedCorners[4], br: rotatedCorners[5], tl: rotatedCorners[7], tr: rotatedCorners[6],
            normal: rotateNormal(simd_float3(0, 0, 1)),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Back face (Z-)
        addQuad(
            bl: rotatedCorners[1], br: rotatedCorners[0], tl: rotatedCorners[2], tr: rotatedCorners[3],
            normal: rotateNormal(simd_float3(0, 0, -1)),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Left face (X-)
        addQuad(
            bl: rotatedCorners[0], br: rotatedCorners[4], tl: rotatedCorners[3], tr: rotatedCorners[7],
            normal: rotateNormal(simd_float3(-1, 0, 0)),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Right face (X+)
        addQuad(
            bl: rotatedCorners[5], br: rotatedCorners[1], tl: rotatedCorners[6], tr: rotatedCorners[2],
            normal: rotateNormal(simd_float3(1, 0, 0)),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Top face (Y+)
        addQuad(
            bl: rotatedCorners[7], br: rotatedCorners[6], tl: rotatedCorners[3], tr: rotatedCorners[2],
            normal: rotateNormal(simd_float3(0, 1, 0)),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Bottom face (Y-)
        addQuad(
            bl: rotatedCorners[0], br: rotatedCorners[1], tl: rotatedCorners[4], tr: rotatedCorners[5],
            normal: rotateNormal(simd_float3(0, -1, 0)),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
    }
    
    private func addQuad(bl: simd_float3, br: simd_float3, tl: simd_float3, tr: simd_float3,
                         normal: simd_float3, uvYStart: Float, uvYEnd: Float, material: UInt32,
                         vertices: inout [TexturedVertex]) {
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
        vertices.append(TexturedVertex(position: br, normal: normal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
        vertices.append(TexturedVertex(position: tl, normal: normal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
    }
    
    /// Add a sword mesh at the given hand position
    private func addSword(at handPos: simd_float3, swingAngle: Float, 
                          isAttacking: Bool = false, attackPhase: Float = 0,
                          swingType: SwingType = .mittelhaw,
                          vertices: inout [TexturedVertex]) {
        // Sword dimensions
        let handleLength: Float = 0.12
        let handleRadius: Float = 0.025
        let bladeLength: Float = 0.55
        let bladeWidth: Float = 0.06
        let bladeThickness: Float = 0.015
        let guardWidth: Float = 0.15
        let guardHeight: Float = 0.03
        
        // Sword material (using pole material for metallic look)
        let matSword: UInt32 = MaterialIndex.pole.rawValue
        
        // Calculate sword direction based on attack state and swing type
        var swordDir: simd_float3
        
        if isAttacking {
            let windUpT = min(attackPhase / 0.25, 1.0)
            let swingT = max(0, (attackPhase - 0.25) / 0.75)
            
            switch swingType {
            case .oberhaw:
                // Overhead cut - sword points up then chops down
                if attackPhase < 0.25 {
                    swordDir = simd_normalize(simd_float3(0, 0.3 + windUpT * 0.7, -0.5 + windUpT * 0.3))
                } else {
                    let downAngle = swingT * 2.2
                    swordDir = simd_normalize(simd_float3(0, 1.0 - downAngle, -0.2 - swingT * 0.6))
                }
                
            case .mittelhaw:
                // Horizontal slash - sword sweeps left to right
                if attackPhase < 0.25 {
                    let yawBack = windUpT * 1.2
                    swordDir = simd_normalize(simd_float3(sin(yawBack), -0.1, -cos(yawBack)))
                } else {
                    let yawAngle = 1.2 - swingT * 2.4
                    swordDir = simd_normalize(simd_float3(sin(yawAngle), -0.15, -cos(yawAngle) * 0.8))
                }
                
            case .unterhaw:
                // Upward cut - sword points down then rises up
                if attackPhase < 0.25 {
                    swordDir = simd_normalize(simd_float3(0.2, -0.6 - windUpT * 0.3, -0.4))
                } else {
                    let upAngle = swingT * 1.8
                    swordDir = simd_normalize(simd_float3(0.1 - swingT * 0.2, -0.9 + upAngle, -0.3 - swingT * 0.3))
                }
                
            case .zornhaw:
                // Diagonal 45-degree cut
                if attackPhase < 0.25 {
                    let backUp = windUpT
                    swordDir = simd_normalize(simd_float3(0.5 * backUp, 0.3 + backUp * 0.4, -0.6))
                } else {
                    let diagSwing = swingT * 2.0
                    swordDir = simd_normalize(simd_float3(0.5 - diagSwing * 0.7, 0.7 - diagSwing * 1.0, -0.6 - swingT * 0.2))
                }
                
            case .thrust:
                // Forward thrust - sword points straight ahead
                if attackPhase < 0.25 {
                    swordDir = simd_normalize(simd_float3(0, -0.1, -0.8 + windUpT * 0.3))
                } else {
                    let thrustExtend = sin(swingT * .pi)
                    swordDir = simd_normalize(simd_float3(0, -0.1 - thrustExtend * 0.05, -0.5 - thrustExtend * 0.5))
                }
            }
        } else {
            // Normal stance - sword points forward with slight downward angle
            let forwardTilt: Float = 0.15
            let swingOffset = swingAngle * 0.3
            swordDir = simd_normalize(simd_float3(swingOffset * 0.2, -forwardTilt, -1.0))
        }
        
        // Calculate basis vectors for sword orientation
        var swordUp = simd_float3(0, 1, 0)
        if abs(simd_dot(swordDir, swordUp)) > 0.95 {
            swordUp = simd_float3(0, 0, 1)
        }
        let swordRight = simd_normalize(simd_cross(swordDir, swordUp))
        let swordForward = simd_normalize(simd_cross(swordRight, swordDir))
        
        // Handle extends back from hand (opposite of blade direction)
        let handleStart = handPos
        let handleEnd = handleStart - swordDir * handleLength
        addLimb(from: handleEnd, to: handleStart, radius: handleRadius, segments: 6,
                uvYStart: 0.0, uvYEnd: 0.2, material: matSword, vertices: &vertices)
        
        // Guard (cross-piece at the hand position)
        let guardCenter = handPos
        addBox(center: guardCenter,
               size: simd_float3(guardWidth, guardHeight, guardHeight),
               uvYStart: 0.2, uvYEnd: 0.4, material: matSword, vertices: &vertices)
        
        // Blade extends forward from guard
        let bladeStart = guardCenter + swordDir * (guardHeight / 2)
        let bladeCenter = bladeStart + swordDir * (bladeLength / 2)
        
        // Create blade as a flat box aligned with sword direction
        addSwordBlade(center: bladeCenter,
                      direction: swordDir,
                      right: swordRight,
                      forward: swordForward,
                      length: bladeLength,
                      width: bladeWidth,
                      thickness: bladeThickness,
                      material: matSword,
                      vertices: &vertices)
    }
    
    /// Add a sword blade oriented along a direction
    private func addSwordBlade(center: simd_float3, direction: simd_float3, right: simd_float3, forward: simd_float3,
                               length: Float, width: Float, thickness: Float, material: UInt32,
                               vertices: inout [TexturedVertex]) {
        let hl = length / 2   // half length (along sword direction)
        let hw = width / 2    // half width (perpendicular to flat side)
        let ht = thickness / 2 // half thickness (thin side)
        
        // Blade corners relative to center
        // The blade is flat (thin in 'forward' direction, wide in 'right' direction)
        // Break up into separate variables to help compiler
        let dirHL = direction * hl
        let rightHW = right * hw
        let forwardHT = forward * ht
        
        let c0 = center - dirHL - rightHW - forwardHT // back-left-bottom
        let c1 = center - dirHL + rightHW - forwardHT // back-right-bottom
        let c2 = center - dirHL + rightHW + forwardHT // back-right-top
        let c3 = center - dirHL - rightHW + forwardHT // back-left-top
        let c4 = center + dirHL - rightHW - forwardHT // front-left-bottom
        let c5 = center + dirHL + rightHW - forwardHT // front-right-bottom
        let c6 = center + dirHL + rightHW + forwardHT // front-right-top
        let c7 = center + dirHL - rightHW + forwardHT // front-left-top
        
        // Front face (tip)
        addQuadVerts(c4, c5, c7, c6, normal: direction, material: material, vertices: &vertices)
        // Back face (near guard)
        addQuadVerts(c1, c0, c2, c3, normal: -direction, material: material, vertices: &vertices)
        // Right face
        addQuadVerts(c5, c1, c6, c2, normal: right, material: material, vertices: &vertices)
        // Left face
        addQuadVerts(c0, c4, c3, c7, normal: -right, material: material, vertices: &vertices)
        // Top face
        addQuadVerts(c3, c2, c7, c6, normal: forward, material: material, vertices: &vertices)
        // Bottom face
        addQuadVerts(c4, c5, c0, c1, normal: -forward, material: material, vertices: &vertices)
    }
    
    /// Helper to add a quad with just corners and normal
    private func addQuadVerts(_ bl: simd_float3, _ br: simd_float3, _ tl: simd_float3, _ tr: simd_float3,
                              normal: simd_float3, material: UInt32, vertices: inout [TexturedVertex]) {
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: br, normal: normal, texCoord: simd_float2(1, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, 0), materialIndex: material))
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, 0), materialIndex: material))
        vertices.append(TexturedVertex(position: tl, normal: normal, texCoord: simd_float2(0, 0), materialIndex: material))
    }
    
    /// Add a shield mesh at the given hand position
    /// - Parameters:
    ///   - handPos: Position of the left hand
    ///   - facingAngle: Angle the shield faces (0 = forward)
    ///   - isBlocking: Whether in blocking/guard stance
    private func addShield(at handPos: simd_float3, facingAngle: Float, isBlocking: Bool,
                           vertices: inout [TexturedVertex]) {
        // Shield dimensions
        let shieldWidth: Float = 0.35      // Width of the shield
        let shieldHeight: Float = 0.45     // Height of the shield
        let shieldThickness: Float = 0.04  // Thickness of the shield
        let rimWidth: Float = 0.03         // Width of the metal rim
        let bossRadius: Float = 0.06       // Central boss (dome) radius
        
        // Materials
        let matWood: UInt32 = MaterialIndex.treeTrunk.rawValue   // Shield body (wood)
        let matMetal: UInt32 = MaterialIndex.pole.rawValue       // Metal parts
        
        // Shield is held slightly forward and to the side from the hand
        let shieldOffset = simd_float3(-0.05, 0.08, -0.15)  // Left, up, forward
        let shieldCenter = handPos + shieldOffset
        
        // Shield faces forward with slight angle based on arm position
        let shieldFacing = simd_float3(sin(facingAngle) * 0.3, 0, -1)
        let shieldNormal = simd_normalize(shieldFacing)
        let shieldUp = simd_float3(0, 1, 0)
        let shieldRight = simd_normalize(simd_cross(shieldUp, shieldNormal))
        
        // Adjust shield position when blocking (more forward and angled)
        var adjustedCenter = shieldCenter
        if isBlocking {
            adjustedCenter.z -= 0.08  // Move more forward
            adjustedCenter.y += 0.05  // Raise slightly
        }
        
        // Main shield body (slightly curved appearance via multiple panels)
        let hw = shieldWidth / 2
        let hh = shieldHeight / 2
        let ht = shieldThickness / 2
        
        // Front face of shield
        let frontBL = adjustedCenter + shieldRight * (-hw) + shieldUp * (-hh) + shieldNormal * ht
        let frontBR = adjustedCenter + shieldRight * hw + shieldUp * (-hh) + shieldNormal * ht
        let frontTL = adjustedCenter + shieldRight * (-hw) + shieldUp * hh + shieldNormal * ht
        let frontTR = adjustedCenter + shieldRight * hw + shieldUp * hh + shieldNormal * ht
        addQuadVerts(frontBL, frontBR, frontTL, frontTR, normal: shieldNormal, material: matWood, vertices: &vertices)
        
        // Back face of shield
        let backBL = adjustedCenter + shieldRight * (-hw) + shieldUp * (-hh) - shieldNormal * ht
        let backBR = adjustedCenter + shieldRight * hw + shieldUp * (-hh) - shieldNormal * ht
        let backTL = adjustedCenter + shieldRight * (-hw) + shieldUp * hh - shieldNormal * ht
        let backTR = adjustedCenter + shieldRight * hw + shieldUp * hh - shieldNormal * ht
        addQuadVerts(backBR, backBL, backTR, backTL, normal: -shieldNormal, material: matWood, vertices: &vertices)
        
        // Edges
        addQuadVerts(frontTL, frontTR, backTL, backTR, normal: shieldUp, material: matMetal, vertices: &vertices)      // Top
        addQuadVerts(frontBR, frontBL, backBR, backBL, normal: -shieldUp, material: matMetal, vertices: &vertices)     // Bottom
        addQuadVerts(frontBL, frontTL, backBL, backTL, normal: -shieldRight, material: matMetal, vertices: &vertices)  // Left
        addQuadVerts(frontTR, frontBR, backTR, backBR, normal: shieldRight, material: matMetal, vertices: &vertices)   // Right
        
        // Metal rim around the shield (as thin boxes on top of the main shield)
        // Top rim
        let rimTopCenter = adjustedCenter + shieldUp * (hh - rimWidth / 2) + shieldNormal * (ht + 0.005)
        addBox(center: rimTopCenter, size: simd_float3(shieldWidth, rimWidth, 0.01),
               uvYStart: 0.0, uvYEnd: 0.2, material: matMetal, vertices: &vertices)
        
        // Bottom rim
        let rimBottomCenter = adjustedCenter + shieldUp * (-hh + rimWidth / 2) + shieldNormal * (ht + 0.005)
        addBox(center: rimBottomCenter, size: simd_float3(shieldWidth, rimWidth, 0.01),
               uvYStart: 0.0, uvYEnd: 0.2, material: matMetal, vertices: &vertices)
        
        // Left rim
        let rimLeftCenter = adjustedCenter + shieldRight * (-hw + rimWidth / 2) + shieldNormal * (ht + 0.005)
        addBox(center: rimLeftCenter, size: simd_float3(rimWidth, shieldHeight - rimWidth * 2, 0.01),
               uvYStart: 0.0, uvYEnd: 0.2, material: matMetal, vertices: &vertices)
        
        // Right rim
        let rimRightCenter = adjustedCenter + shieldRight * (hw - rimWidth / 2) + shieldNormal * (ht + 0.005)
        addBox(center: rimRightCenter, size: simd_float3(rimWidth, shieldHeight - rimWidth * 2, 0.01),
               uvYStart: 0.0, uvYEnd: 0.2, material: matMetal, vertices: &vertices)
        
        // Central boss (dome) - approximated with a sphere
        let bossCenter = adjustedCenter + shieldNormal * (ht + bossRadius * 0.3)
        addSphere(center: bossCenter, radius: bossRadius, latSegments: 4, lonSegments: 8,
                  uvYStart: 0.0, uvYEnd: 0.3, material: matMetal, vertices: &vertices)
        
        // Cross-bar reinforcement (horizontal metal bar across center)
        let crossBarCenter = adjustedCenter + shieldNormal * (ht + 0.01)
        addBox(center: crossBarCenter, size: simd_float3(shieldWidth * 0.7, 0.025, 0.015),
               uvYStart: 0.0, uvYEnd: 0.2, material: matMetal, vertices: &vertices)
        
        // Vertical reinforcement bar
        addBox(center: crossBarCenter, size: simd_float3(0.025, shieldHeight * 0.6, 0.015),
               uvYStart: 0.0, uvYEnd: 0.2, material: matMetal, vertices: &vertices)
    }
}

