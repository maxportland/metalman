import simd

// MARK: - Matrix Helpers

/// Creates a right-handed perspective projection matrix
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

/// Creates a look-at view matrix
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

/// Creates a rotation matrix around the Y axis
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

/// Creates a rotation matrix around the X axis
func rotationX(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4(1, 0, 0, 0),
        simd_float4(0, c, -s, 0),
        simd_float4(0, s, c, 0),
        simd_float4(0, 0, 0, 1)
    )
}

/// Creates a rotation matrix around the Z axis
func rotationZ(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return simd_float4x4(
        simd_float4(c, -s, 0, 0),
        simd_float4(s, c, 0, 0),
        simd_float4(0, 0, 1, 0),
        simd_float4(0, 0, 0, 1)
    )
}

/// Creates a translation matrix
func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        simd_float4(1, 0, 0, 0),
        simd_float4(0, 1, 0, 0),
        simd_float4(0, 0, 1, 0),
        simd_float4(x, y, z, 1)
    )
}

/// Creates a scaling matrix
func scaling(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        simd_float4(x, 0, 0, 0),
        simd_float4(0, y, 0, 0),
        simd_float4(0, 0, z, 0),
        simd_float4(0, 0, 0, 1)
    )
}

/// Creates a right-handed orthographic projection matrix
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

// MARK: - Utility Functions

/// Seeded random number generator for reproducible placement
func seededRandom(_ seed: Int) -> Float {
    let x = sin(Float(seed) * 12.9898 + Float(seed) * 78.233) * 43758.5453
    return x - floor(x)
}

