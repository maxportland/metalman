import Metal
import AppKit

/// Generates procedural textures for the game
class TextureGenerator {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
    }
    
    // MARK: - Texture Loading from Files
    
    /// Load a texture from the textures folder
    func loadTexture(named filename: String) -> MTLTexture? {
        // Try multiple locations to find the texture
        let possiblePaths = [
            // Absolute path for development (most reliable)
            "/Users/maxdavis/Projects/MetalMan/textures/" + filename,
            // From bundle going up to project root
            Bundle.main.bundlePath + "/../../../textures/" + filename,
            // From derived data build location
            Bundle.main.bundlePath + "/../../../../../../../../textures/" + filename,
            // From Resources in bundle
            Bundle.main.bundlePath + "/Contents/Resources/textures/" + filename
        ]
        
        var image: NSImage?
        
        for path in possiblePaths {
            if FileManager.default.isReadableFile(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                image = img
                break
            }
        }
        
        guard let loadedImage = image else {
            return nil
        }
        
        guard let cgImage = loadedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to get CGImage for: \(filename)")
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create texture descriptor
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("Failed to create texture for: \(filename)")
            return nil
        }
        
        // Convert image to RGBA data
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 255, count: width * height * bytesPerPixel) // Initialize with 255 for alpha
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Use noneSkipLast for JPEGs (no alpha) with proper byte order
        // This creates RGBX where X is ignored (we initialized to 255 for full alpha)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            print("Failed to create context for: \(filename)")
            // Try alternate bitmap info for images with alpha
            let altBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            guard let altContext = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: altBitmapInfo.rawValue
            ) else {
                print("Failed to create alternate context for: \(filename)")
                return nil
            }
            altContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: pixelData,
                bytesPerRow: bytesPerRow
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
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
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
    
    // MARK: - Public Texture Creation
    
    func createGroundTexture() -> MTLTexture {
        // Try to load grass texture from file
        if let texture = loadTexture(named: "grass_01_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
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
        // Try to load tree bark texture from file
        if let texture = loadTexture(named: "tree_01_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
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
        // Try to load foliage texture from file
        if let texture = loadTexture(named: "leaves_01_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
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
        // Try to load rock texture from file
        if let texture = loadTexture(named: "rock_01_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
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
        // Try to load wood texture from file
        if let texture = loadTexture(named: "wood_wall_01_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
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
    
    func createPathTexture() -> MTLTexture {
        // Try to load path texture from file
        if let texture = loadTexture(named: "path_01_diffuse.jpg") {
            return texture
        }
        // Also try dirt texture
        if let texture = loadTexture(named: "dirt_01_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                // Dirt path with pebbles
                let base: Float = 0.45
                let noise1 = Float((x * 17 + y * 11) % 23) / 23.0 * 0.12
                let noise2 = Float((x * 7 + y * 19) % 13) / 13.0 * 0.08
                let pebble: Float = Float((x * 31 + y * 37) % 47) < 5 ? 0.1 : 0.0
                
                let brown = base + noise1 - noise2 + pebble
                pixels[i] = UInt8(min(255, (brown + 0.08) * 255))      // R
                pixels[i + 1] = UInt8(min(255, (brown - 0.02) * 255))  // G
                pixels[i + 2] = UInt8(min(255, (brown - 0.12) * 255))  // B
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    func createStoneWallTexture() -> MTLTexture {
        // Try to load stone/concrete texture from file
        if let texture = loadTexture(named: "concrete_01_diffuse.jpg") {
            return texture
        }
        if let texture = loadTexture(named: "bricks_01_sm_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Create brick pattern
                let brickHeight = 16
                let brickWidth = 32
                let mortarWidth = 2
                
                let row = y / brickHeight
                let offset = (row % 2) * (brickWidth / 2)
                let brickX = (x + offset) % brickWidth
                let brickY = y % brickHeight
                
                let isMortar = brickX < mortarWidth || brickY < mortarWidth
                
                let noise = Float((x * 13 + y * 17) % 19) / 19.0 * 0.1
                
                if isMortar {
                    // Mortar - lighter gray
                    let gray: Float = 0.55 + noise
                    pixels[i] = UInt8(min(255, gray * 255))
                    pixels[i + 1] = UInt8(min(255, (gray - 0.02) * 255))
                    pixels[i + 2] = UInt8(min(255, (gray - 0.04) * 255))
                } else {
                    // Stone - varied gray/brown
                    let brickNoise = Float((brickX * 7 + brickY * 11) % 13) / 13.0 * 0.15
                    let base: Float = 0.4 + brickNoise + noise
                    pixels[i] = UInt8(min(255, (base + 0.02) * 255))
                    pixels[i + 1] = UInt8(min(255, base * 255))
                    pixels[i + 2] = UInt8(min(255, (base - 0.02) * 255))
                }
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    func createRoofTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Terracotta tile pattern
                let tileHeight = 8
                let row = y / tileHeight
                let tileY = y % tileHeight
                let rowShade = Float(tileY) / Float(tileHeight) * 0.15
                
                let noise = Float((x * 11 + y * 7 + row * 13) % 17) / 17.0 * 0.1
                let base: Float = 0.6 + rowShade + noise
                
                pixels[i] = UInt8(min(255, (base + 0.15) * 255))       // R - reddish
                pixels[i + 1] = UInt8(min(255, (base - 0.1) * 255))    // G
                pixels[i + 2] = UInt8(min(255, (base - 0.2) * 255))    // B
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    func createWoodPlankTexture() -> MTLTexture {
        // Try to load wood plank texture from file
        if let texture = loadTexture(named: "wood_wall_02_sm_diffuse.jpg") {
            return texture
        }
        
        // Fallback to procedural
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Wood grain
                let plankWidth = 16
                let plank = x / plankWidth
                let plankX = x % plankWidth
                let edge: Float = plankX < 1 ? 0.1 : 0.0
                
                let grain = sin(Float(y) * 0.3 + Float(plank) * 2.0) * 0.08
                let noise = Float((x * 7 + y * 11) % 13) / 13.0 * 0.06
                let base: Float = 0.5 + grain + noise - edge
                
                pixels[i] = UInt8(min(255, (base + 0.12) * 255))      // R
                pixels[i + 1] = UInt8(min(255, (base - 0.02) * 255))  // G
                pixels[i + 2] = UInt8(min(255, (base - 0.15) * 255))  // B
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    func createTreasureChestTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Rich brown wood base color
                var r: Float = 0.45
                var g: Float = 0.28
                var b: Float = 0.12
                
                // Wood grain pattern
                let grainX = Float(x) * 0.3
                let grainY = Float(y) * 0.1
                let grain = sin(grainX + sin(grainY * 2) * 3) * 0.5 + 0.5
                r += grain * 0.08
                g += grain * 0.04
                b += grain * 0.02
                
                // Darker edges for depth (wood plank look)
                let edgeX = min(Float(x), Float(size - 1 - x)) / Float(size / 4)
                let edgeY = min(Float(y), Float(size - 1 - y)) / Float(size / 4)
                let edgeFactor = min(1.0, min(edgeX, edgeY))
                r *= 0.7 + edgeFactor * 0.3
                g *= 0.7 + edgeFactor * 0.3
                b *= 0.7 + edgeFactor * 0.3
                
                // Golden/brass tint for treasure feel
                r += 0.05
                g += 0.03
                
                // Add some noise
                let noise = Float.random(in: -0.03...0.03)
                r += noise
                g += noise * 0.7
                b += noise * 0.5
                
                pixels[i] = UInt8(min(255, max(0, r * 255)))
                pixels[i + 1] = UInt8(min(255, max(0, g * 255)))
                pixels[i + 2] = UInt8(min(255, max(0, b * 255)))
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    /// Creates a red shirt texture for enemy bandits
    func createEnemyTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Deep red base color for bandit shirt
                var r: Float = 0.7
                var g: Float = 0.15
                var b: Float = 0.12
                
                // Fabric weave pattern
                let weaveX = sin(Float(x) * 0.8) * 0.5 + 0.5
                let weaveY = sin(Float(y) * 0.8) * 0.5 + 0.5
                let weave = (weaveX + weaveY) * 0.5
                r += weave * 0.08
                g += weave * 0.02
                b += weave * 0.02
                
                // Fold/crease shadows
                let foldPattern = sin(Float(x) * 0.2 + Float(y) * 0.1) * 0.5 + 0.5
                r *= 0.85 + foldPattern * 0.15
                g *= 0.85 + foldPattern * 0.15
                b *= 0.85 + foldPattern * 0.15
                
                // Slight dirt/wear at edges
                let edgeY = Float(y) / Float(size)
                if edgeY > 0.8 || edgeY < 0.2 {
                    let edgeDirt = abs(edgeY - 0.5) * 0.3
                    r -= edgeDirt * 0.15
                    g -= edgeDirt * 0.05
                    b -= edgeDirt * 0.05
                }
                
                // Add fabric noise
                let noise = Float.random(in: -0.04...0.04)
                r += noise
                g += noise * 0.3
                b += noise * 0.3
                
                pixels[i] = UInt8(min(255, max(0, r * 255)))
                pixels[i + 1] = UInt8(min(255, max(0, g * 255)))
                pixels[i + 2] = UInt8(min(255, max(0, b * 255)))
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    /// Creates a yellow shirt texture for vendor NPCs
    func createVendorTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Golden yellow base color for vendor shirt
                var r: Float = 0.85
                var g: Float = 0.72
                var b: Float = 0.15
                
                // Fabric weave pattern
                let weaveX = sin(Float(x) * 0.8) * 0.5 + 0.5
                let weaveY = sin(Float(y) * 0.8) * 0.5 + 0.5
                let weave = (weaveX + weaveY) * 0.5
                r += weave * 0.06
                g += weave * 0.05
                b += weave * 0.02
                
                // Fold/crease shadows
                let foldPattern = sin(Float(x) * 0.2 + Float(y) * 0.1) * 0.5 + 0.5
                r *= 0.85 + foldPattern * 0.15
                g *= 0.85 + foldPattern * 0.15
                b *= 0.85 + foldPattern * 0.15
                
                // Slight wear at edges
                let edgeY = Float(y) / Float(size)
                if edgeY > 0.8 || edgeY < 0.2 {
                    let edgeDirt = abs(edgeY - 0.5) * 0.3
                    r -= edgeDirt * 0.1
                    g -= edgeDirt * 0.08
                    b -= edgeDirt * 0.03
                }
                
                // Add fabric noise
                let noise = Float.random(in: -0.04...0.04)
                r += noise
                g += noise * 0.9
                b += noise * 0.3
                
                pixels[i] = UInt8(min(255, max(0, r * 255)))
                pixels[i + 1] = UInt8(min(255, max(0, g * 255)))
                pixels[i + 2] = UInt8(min(255, max(0, b * 255)))
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    /// Creates a fallback texture for cabin models (dark wood)
    func createCabinTexture() -> MTLTexture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Warm brown wood color - brighter for visibility
                var r: Float = 0.55
                var g: Float = 0.40
                var b: Float = 0.25
                
                // Wood grain horizontal lines
                let grainY = sin(Float(y) * 0.5 + Float(x) * 0.05) * 0.5 + 0.5
                r += grainY * 0.12
                g += grainY * 0.08
                b += grainY * 0.05
                
                // Vertical board divisions
                let boardWidth: Float = 16
                let boardX = Float(x).truncatingRemainder(dividingBy: boardWidth) / boardWidth
                if boardX < 0.05 || boardX > 0.95 {
                    r *= 0.8
                    g *= 0.8
                    b *= 0.8
                }
                
                // Add subtle noise
                let noise = Float.random(in: -0.03...0.03)
                r += noise
                g += noise
                b += noise
                
                pixels[i] = UInt8(min(255, max(0, r * 255)))
                pixels[i + 1] = UInt8(min(255, max(0, g * 255)))
                pixels[i + 2] = UInt8(min(255, max(0, b * 255)))
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    func createSkyTexture() -> MTLTexture {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                
                // Gradient from light blue at top to pale blue/white at horizon
                let t = Float(y) / Float(size)
                
                // Base sky color gradient
                let skyTopR: Float = 0.4
                let skyTopG: Float = 0.6
                let skyTopB: Float = 0.95
                
                let skyHorizonR: Float = 0.75
                let skyHorizonG: Float = 0.85
                let skyHorizonB: Float = 0.95
                
                var r = skyTopR + (skyHorizonR - skyTopR) * t
                var g = skyTopG + (skyHorizonG - skyTopG) * t
                var b = skyTopB + (skyHorizonB - skyTopB) * t
                
                // Add clouds using layered noise
                let cloudNoise1 = sin(Float(x) * 0.03 + 1.5) * cos(Float(y) * 0.02) * 0.5 + 0.5
                let cloudNoise2 = sin(Float(x) * 0.07 + Float(y) * 0.04) * 0.5 + 0.5
                let cloudNoise3 = sin(Float(x + y) * 0.05) * cos(Float(x - y) * 0.03) * 0.5 + 0.5
                
                var cloudDensity = cloudNoise1 * 0.5 + cloudNoise2 * 0.3 + cloudNoise3 * 0.2
                
                // Clouds are more visible in the upper-middle area
                let cloudBand = 1.0 - abs(t - 0.4) * 2.5
                cloudDensity *= max(0, cloudBand)
                
                // Threshold for cloud visibility
                if cloudDensity > 0.45 {
                    let cloudAmount = (cloudDensity - 0.45) * 3.0
                    r = r + (1.0 - r) * cloudAmount * 0.8
                    g = g + (1.0 - g) * cloudAmount * 0.8
                    b = b + (1.0 - b) * cloudAmount * 0.6
                }
                
                pixels[i] = UInt8(min(255, r * 255))
                pixels[i + 1] = UInt8(min(255, g * 255))
                pixels[i + 2] = UInt8(min(255, b * 255))
                pixels[i + 3] = 255
            }
        }
        
        return createTexture(from: pixels, size: size)
    }
    
    // MARK: - Normal Map Textures
    
    func createGroundNormalMap() -> MTLTexture {
        // Try to load normal map from file
        if let texture = loadTexture(named: "grass_01_normal.jpg") {
            return texture
        }
        // Fallback: flat normal map (pointing straight up)
        return createFlatNormalMap(size: 64)
    }
    
    func createTrunkNormalMap() -> MTLTexture {
        if let texture = loadTexture(named: "tree_01_normal.jpg") {
            return texture
        }
        return createFlatNormalMap(size: 64)
    }
    
    func createRockNormalMap() -> MTLTexture {
        if let texture = loadTexture(named: "rock_01_normal.jpg") {
            return texture
        }
        return createFlatNormalMap(size: 64)
    }
    
    func createPathNormalMap() -> MTLTexture {
        // Path doesn't have a normal map, use dirt if available
        if let texture = loadTexture(named: "dirt_01_normal.jpg") {
            return texture
        }
        return createFlatNormalMap(size: 64)
    }
    
    /// Create a flat normal map (all normals pointing straight up in tangent space)
    private func createFlatNormalMap(size: Int) -> MTLTexture {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            // Normal pointing up in tangent space: (0, 0, 1) encoded as (128, 128, 255)
            pixels[i] = 128     // R = X (0 -> 128)
            pixels[i + 1] = 128 // G = Y (0 -> 128)
            pixels[i + 2] = 255 // B = Z (1 -> 255)
            pixels[i + 3] = 255 // A
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

