import SwiftUI
import CoreText

// Disable verbose logging
private let fontDebugLogging = false
private func debugLog(_ message: @autoclosure () -> String) {
    if fontDebugLogging {
        print(message())
    }
}

/// Font Awesome icon helper for SwiftUI
/// 
/// Usage:
///   FontAwesomeIconView(.sword, size: 32, color: .white)
///   
/// Or use the Text extension:
///   Text(fontAwesome: .sword)
///       .font(.custom("FontAwesome6Free-Solid", size: 32))

/// Registers Font Awesome font from the app bundle
class FontAwesomeLoader {
    static let shared = FontAwesomeLoader()
    private var isLoaded = false
    private var loadedFontName: String?
    
    /// Font file names to try loading (without extension)
    private let fontFileNames = [
        "Font Awesome 7 Free-Solid-900",
        "Font Awesome 6 Free-Solid-900",
        "FontAwesome",
        "fa-solid-900"
    ]
    
    func loadFontIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        
        for fileName in fontFileNames {
            if loadFont(named: fileName, withExtension: "otf") {
                return
            }
            if loadFont(named: fileName, withExtension: "ttf") {
                return
            }
        }
        
        debugLog("[FontAwesome] ❌ Could not find Font Awesome font file in bundle")
        debugLog("[FontAwesome] Searched for: \(fontFileNames)")
        
        // List what's actually in the bundle for debugging
        if let resourcePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            do {
                let files = try fileManager.contentsOfDirectory(atPath: resourcePath)
                let fontFiles = files.filter { $0.hasSuffix(".otf") || $0.hasSuffix(".ttf") }
                if fontFiles.isEmpty {
                    debugLog("[FontAwesome] No .otf or .ttf files found in bundle")
                } else {
                    debugLog("[FontAwesome] Font files in bundle: \(fontFiles)")
                }
            } catch {
                debugLog("[FontAwesome] Could not list bundle contents: \(error)")
            }
        }
    }
    
    private func loadFont(named name: String, withExtension ext: String) -> Bool {
        guard let fontURL = Bundle.main.url(forResource: name, withExtension: ext) else {
            return false
        }
        
        debugLog("[FontAwesome] Found font file: \(fontURL.lastPathComponent)")
        
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        
        if success {
            // Get the actual PostScript name from the font file
            if let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
               let cgFont = CGFont(fontDataProvider),
               let postScriptName = cgFont.postScriptName as String? {
                loadedFontName = postScriptName
                debugLog("[FontAwesome] ✅ Registered font with PostScript name: \(postScriptName)")
            } else {
                debugLog("[FontAwesome] ✅ Registered font (could not determine PostScript name)")
            }
            return true
        } else {
            if let cfError = error?.takeRetainedValue() {
                let errorDesc = CFErrorCopyDescription(cfError) as String
                // Error code 105 means font is already registered
                if CFErrorGetCode(cfError) == 105 {
                    debugLog("[FontAwesome] Font already registered")
                    // Try to get the PostScript name anyway
                    if let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
                       let cgFont = CGFont(fontDataProvider),
                       let postScriptName = cgFont.postScriptName as String? {
                        loadedFontName = postScriptName
                        debugLog("[FontAwesome] ✅ Using already registered font: \(postScriptName)")
                    }
                    return true
                }
                debugLog("[FontAwesome] ❌ Failed to register font: \(errorDesc)")
            }
            return false
        }
    }
    
    var fontName: String? {
        loadFontIfNeeded()
        return loadedFontName
    }
}

enum FAIcon: String {
    // Weapons & Combat
    case sword = "\u{f71c}"           // Pro only - fallback to dagger
    case dagger = "\u{f6cb}"          // Pro only
    case axe = "\u{f6b2}"             // Pro only
    case shield = "\u{f3ed}"          // Free - shield
    case bolt = "\u{f0e7}"            // Free - lightning bolt (good sword alternative)
    case fire = "\u{f06d}"            // Free - fire
    case skull = "\u{f54c}"           // Free - skull
    case crosshairs = "\u{f05b}"      // Free - crosshairs
    
    // Items & Objects
    case flask = "\u{f0c3}"           // Free - flask/potion
    case gem = "\u{f3a5}"             // Free - gem
    case crown = "\u{f521}"           // Free - crown
    case ring = "\u{f70b}"            // Pro only
    case scroll = "\u{f70e}"          // Pro only
    case coins = "\u{f51e}"           // Free - coins
    case box = "\u{f466}"             // Free - box
    case archive = "\u{f187}"         // Free - archive box
    case cube = "\u{f1b2}"            // Free - cube
    case heart = "\u{f004}"           // Free - heart
    case star = "\u{f005}"            // Free - star
    case magic = "\u{f0d0}"           // Free - magic wand
    
    // Character & Equipment
    case user = "\u{f007}"            // Free - user
    case hatWizard = "\u{f6e8}"       // Free - wizard hat
    case personRunning = "\u{f70c}"   // Free - running
    case handFist = "\u{f6de}"        // Free - fist
    
    // UI & Misc
    case check = "\u{f00c}"           // Free - checkmark
    case question = "\u{f128}"        // Free - question
    case exclamation = "\u{f12a}"     // Free - exclamation
    case plus = "\u{f067}"            // Free - plus
    case minus = "\u{f068}"           // Free - minus
    
    /// The unicode character for this icon
    var unicode: String { rawValue }
}

/// A view that displays a Font Awesome icon
struct FontAwesomeIconView: View {
    let icon: FAIcon
    let size: CGFloat
    let color: Color
    
    init(_ icon: FAIcon, size: CGFloat = 24, color: Color = .white) {
        self.icon = icon
        self.size = size
        self.color = color
    }
    
    var body: some View {
        if let fontName = FontAwesomeLoader.shared.fontName {
            Text(icon.unicode)
                .font(.custom(fontName, size: size))
                .foregroundColor(color)
        } else {
            // Fallback to SF Symbol
            Image(systemName: sfSymbolFallback)
                .font(.system(size: size))
                .foregroundColor(color)
        }
    }
    
    /// SF Symbol fallback for when Font Awesome is unavailable
    private var sfSymbolFallback: String {
        switch icon {
        case .sword, .dagger, .axe, .bolt: return "bolt.fill"
        case .shield: return "shield.fill"
        case .fire: return "flame.fill"
        case .skull: return "person.fill.xmark"
        case .crosshairs: return "scope"
        case .flask: return "drop.fill"
        case .gem: return "diamond.fill"
        case .crown: return "crown.fill"
        case .ring: return "circle.circle.fill"
        case .scroll: return "scroll.fill"
        case .coins: return "dollarsign.circle.fill"
        case .box, .archive, .cube: return "cube.fill"
        case .heart: return "heart.fill"
        case .star: return "star.fill"
        case .magic: return "wand.and.stars"
        case .user: return "person.fill"
        case .hatWizard: return "graduationcap.fill"
        case .personRunning: return "figure.walk"
        case .handFist: return "hand.raised.fill"
        case .check: return "checkmark"
        case .question: return "questionmark"
        case .exclamation: return "exclamationmark"
        case .plus: return "plus"
        case .minus: return "minus"
        }
    }
}

/// Extension to easily create Font Awesome text
extension Text {
    init(fontAwesome icon: FAIcon) {
        self.init(icon.unicode)
    }
}

/// Checks if Font Awesome fonts are available
struct FontAwesomeChecker {
    static var isFontAwesomeAvailable: Bool {
        FontAwesomeLoader.shared.fontName != nil
    }
    
    static func printAvailableFonts() {
        debugLog("[FontAwesome] Loading Font Awesome from bundle...")
        
        // Trigger the font loading
        if let fontName = FontAwesomeLoader.shared.fontName {
            debugLog("[FontAwesome] ✅ Ready to use: \(fontName)")
        } else {
            debugLog("[FontAwesome] ❌ Font Awesome not available, will use SF Symbols fallback")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FontAwesome_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FontAwesomeIconView(.bolt, size: 48, color: .yellow)
            FontAwesomeIconView(.shield, size: 48, color: .blue)
            FontAwesomeIconView(.flask, size: 48, color: .green)
            FontAwesomeIconView(.heart, size: 48, color: .red)
        }
        .padding()
        .background(Color.black)
    }
}
#endif
