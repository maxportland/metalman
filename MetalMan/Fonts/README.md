# Font Awesome Setup

This folder should contain Font Awesome font files for custom icons in the game UI.

## How to Add Font Awesome

### Option 1: Font Awesome Free (Recommended for testing)

1. Go to https://fontawesome.com/download
2. Download "Font Awesome Free for Desktop" (`.otf` format)
3. Extract the zip file
4. From the `otfs` folder, copy these files to this `Fonts` folder:
   - `Font Awesome 6 Free-Solid-900.otf` (required - main icons)
   - `Font Awesome 6 Free-Regular-400.otf` (optional - outline icons)

### Option 2: Font Awesome Pro (For sword icon and more)

If you have a Font Awesome Pro license:

1. Download Font Awesome Pro for Desktop
2. From the `otfs` folder, copy these files to this `Fonts` folder:
   - `Font Awesome 6 Pro-Solid-900.otf`
   - `Font Awesome 6 Pro-Regular-400.otf`

The Pro version includes additional icons like:
- `\u{f71c}` - Sword
- `\u{f6cb}` - Dagger  
- `\u{f70e}` - Scroll
- And many more weapon/RPG icons

## After Adding Fonts

1. In Xcode, add the font files to the project:
   - Right-click on the `Fonts` folder in Xcode
   - Select "Add Files to MetalMan..."
   - Select the `.otf` files
   - Make sure "Copy items if needed" is checked
   - Make sure the target "MetalMan" is checked

2. The Info.plist is already configured with `ATSApplicationFontsPath` set to `Fonts`

3. Clean and rebuild the project (Cmd+Shift+K, then Cmd+B)

## Font Names Used in Code

The code will automatically detect available Font Awesome fonts. Common font names:
- `FontAwesome6Pro-Solid` (Pro version)
- `FontAwesome6Free-Solid` (Free version)
- `Font Awesome 6 Free Solid` (alternative naming)
- `Font Awesome 6 Pro Solid` (alternative naming)

The code checks for multiple possible font names, so it should work regardless of the exact naming.

## Fallback

If Font Awesome fonts are not available, the app will automatically fall back to SF Symbols, so the game will still work without the fonts installed.

## File Formats

- **Desktop apps (macOS/iOS)**: Use `.otf` files
- **Web**: Use `.woff2` files (not needed for this project)

