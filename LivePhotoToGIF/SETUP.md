# Live Photo → GIF — Multiplatform App Setup

A single-codebase SwiftUI app that runs on **both iOS and macOS**.
Convert Live Photos to animated GIFs — pick from Photos, drag-and-drop (Mac), or open a file.

## Requirements

- **Xcode 15+** (free from the Mac App Store)
- **iOS 16+** device or simulator (Live Photos need a real device to test properly)
- **macOS 13 Ventura** or later

## Quick Setup (5 minutes)

### 1. Create the Xcode project

1. Open **Xcode**
2. **File → New → Project**
3. Choose **Multiplatform → App**, click Next
4. Fill in:
   - **Product Name:** `LivePhotoToGIF`
   - **Interface:** SwiftUI
   - **Language:** Swift
5. Choose a save location, click **Create**

### 2. Replace the template files

1. In the Project Navigator (left sidebar), **delete** the template `ContentView.swift`
   (right-click → Delete → Move to Trash)
2. Also delete `LivePhotoToGIFApp.swift` if present
3. Drag **all 4 Swift files** from this directory into the Project Navigator:
   - `LivePhotoToGIFApp.swift`
   - `ContentView.swift`
   - `Converter.swift`
   - `PlatformViews.swift`
4. When prompted, check **"Copy items if needed"** and ensure **both targets** (iOS and macOS) are checked, then click **Add**

### 3. Add Privacy Descriptions

1. Click the **project** (blue icon) in the Project Navigator
2. Select the **LivePhotoToGIF** target
3. Go to the **Info** tab
4. Under **Custom Target Properties**, click **+** and add:

| Key | Value |
|-----|-------|
| `Privacy - Photo Library Usage Description` | `This app needs access to your Photos to read Live Photos and convert them to GIFs.` |

> For iOS, also add if you want "Save to Photos" to work:
>
> | Key | Value |
> |-----|-------|
> | `Privacy - Photo Library Additions Usage Description` | `This app saves converted GIFs to your Photos library.` |

**Repeat** for the macOS target if the project has separate targets per platform.

### 4. Enable App Sandbox Permissions (macOS)

Since the macOS app is sandboxed:

1. Select the **macOS target** (if separate) or the main target
2. Go to the **Signing & Capabilities** tab
3. Under **App Sandbox**, enable:
   - **File Access → User Selected File** → Read Only
   - **Photos** (check the box)

If App Sandbox is not present, click **+ Capability** → App Sandbox.

### 5. Set Deployment Targets

1. Select the **project** (blue icon) → **General** tab
2. Under **Minimum Deployments**, set:
   - **iOS:** 16.0
   - **macOS:** 13.0

### 6. Build & Run

- **iOS:** Select your iPhone (or simulator) and press **Cmd+R**
- **macOS:** Select **My Mac** and press **Cmd+R**

## Project Structure

```
LivePhotoToGIF/
├── LivePhotoToGIFApp.swift   # App entry point (shared)
├── ContentView.swift          # Main UI with #if os() for platform differences
├── Converter.swift            # GIF conversion engine (fully cross-platform)
├── PlatformViews.swift        # Photo picker, GIF viewer, share sheet (#if os())
└── SETUP.md                   # This file
```

All 4 Swift files compile for both iOS and macOS. Platform-specific code uses
`#if os(iOS)` and `#if os(macOS)` conditional compilation.

## Usage

### iOS
- Tap **"Choose Live Photo"** to open the Photos picker (filtered for Live Photos)
- Trim, adjust FPS and width, then tap **Convert to GIF**
- **Share** or **Save to Photos**

### macOS
- **Drag & drop** a .MOV file onto the app window (AirDrop a Live Photo → drop the .MOV)
- Or click **"Open File..."** for the standard file dialog
- Or click **"Pick from Photos"** to browse your Mac's Photos library
- Trim, adjust settings, convert, then **Save As...**, **Reveal in Finder**, or **Share...**

## Testing on a Real Device (iOS)

Live Photos only exist on real iPhones/iPads. The Simulator has no Live Photos to pick from.

1. Plug in your iPhone via USB
2. Select it as the run destination in Xcode
3. You may need to trust the developer certificate:
   **Settings → General → VPN & Device Management** on the iPhone
4. Build & run — the app installs and launches

**Free Apple ID works** — you don't need a paid developer account to test on your own device.

## How It Works

1. **Pick:** PHPickerViewController filtered for Live Photos gives us the asset identifier
2. **Extract:** `PHAssetResource` finds the paired `.MOV` video and exports it to a temp file
3. **Frames:** `AVAssetImageGenerator` steps through the video at the chosen FPS
4. **Encode:** `CGImageDestination` (ImageIO) writes a GIF89a with proper frame delays
5. **Export:** iOS uses share sheet / save to Photos; macOS uses NSSavePanel / Finder

## Troubleshooting

**"Photo Access Required" alert:**
Grant photo library access in Settings (iOS) or System Settings → Privacy & Security → Photos (macOS).

**Picker shows no photos:**
If you granted "Limited Access" on iOS, tap "Select More Photos" in the picker.

**Dragged file doesn't work (macOS):**
Make sure you're dropping the .MOV file, not the .HEIC. The .HEIC is just the still image.

**Build error about deployment target:**
Set iOS to 16.0 and macOS to 13.0 under Project → General → Minimum Deployments.

**Sandbox error reading files (macOS):**
Enable "User Selected File → Read Only" in Signing & Capabilities → App Sandbox.

**GIF is too large:**
Lower the Max Width slider (try 320px) and reduce FPS to 10. Live Photo GIFs are typically 1–4 MB.
