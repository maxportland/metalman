import Metal

/// Generates procedural textures for the game
class TextureGenerator {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }
    
    // MARK: - Public Texture Creation
    
    func createGroundTexture() -> MTLTexture {
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
    
    func createTrunkTexture() -> MTLTexture {
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
    
    func createFoliageTexture() -> MTLTexture {
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
    
    func createRockTexture() -> MTLTexture {
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
    
    func createPoleTexture() -> MTLTexture {
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
    
    func createCharacterTexture() -> MTLTexture {
        // Texture atlas for character: skin tones and clothes
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
                    // Face/head - warm skin tone
                    let faceShadow = Float(x) / Float(size) * 0.1
                    pixels[i] = UInt8(min(255, (0.95 - faceShadow + noise) * 255))
                    pixels[i + 1] = UInt8(min(255, (0.75 - faceShadow + noise) * 255))
                    pixels[i + 2] = UInt8(min(255, (0.6 - faceShadow * 0.5) * 255))
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
    
    func createShadowMap(size: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }
    
    // MARK: - Private Helpers
    
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
}

