# Live Photo → GIF — iOS App Setup

A native iOS app that converts Live Photos to animated GIFs.
Pick any Live Photo, trim it, adjust FPS/quality, and export — no server, no upload.

## Requirements

- **Xcode 15+** (free from the Mac App Store)
- **iOS 16+** device or simulator (Live Photos need a real device to test properly)
- A Mac running macOS 14 Sonoma or later

## Quick Setup (5 minutes)

### 1. Create the Xcode project

1. Open **Xcode**
2. **File → New → Project**
3. Choose **iOS → App**, click Next
4. Fill in:
   - **Product Name:** `LivePhotoToGIF`
   - **Interface:** SwiftUI
   - **Language:** Swift
5. Choose a save location, click **Create**

### 2. Replace the template files

Xcode creates template files (`ContentView.swift`, `LivePhotoToGIFApp.swift`, etc.).
Replace them with the files from this directory:

1. In Xcode's Project Navigator (left sidebar), **delete** the template `ContentView.swift`
   (right-click → Delete → Move to Trash)
2. Drag **all 4 Swift files** from this directory into the Project Navigator:
   - `LivePhotoToGIFApp.swift`
   - `ContentView.swift`
   - `LivePhotoPicker.swift`
   - `Converter.swift`
3. When prompted, check **"Copy items if needed"** and click **Add**

### 3. Add Privacy Descriptions

The app needs permission to access the Photos library.

1. Click the **project** (blue icon) in the Project Navigator
2. Select the **LivePhotoToGIF** target
3. Go to the **Info** tab
4. Under **Custom iOS Target Properties**, click **+** and add:

| Key | Value |
|-----|-------|
| `Privacy - Photo Library Usage Description` | `This app needs access to your Photos to read Live Photos and convert them to GIFs.` |

> If you also want "Save to Photos" to work, add:
>
> | Key | Value |
> |-----|-------|
> | `Privacy - Photo Library Additions Usage Description` | `This app saves converted GIFs to your Photos library.` |

### 4. Build & Run

1. Select your **iPhone** (or a simulator) as the run destination
2. Press **Cmd+R** or click the Play button
3. The app builds and launches

## Testing on a Real Device

Live Photos only exist on real iPhones/iPads. The Simulator has no Live Photos to pick from.

**To test on your iPhone:**
1. Plug in your iPhone via USB
2. Select it as the run destination in Xcode
3. You may need to trust the developer certificate:
   **Settings → General → VPN & Device Management** on the iPhone
4. Build & run — the app installs and launches

**Free Apple ID works** — you don't need a paid developer account to test on your own device.
Just sign in with your Apple ID in Xcode → Settings → Accounts.

## How It Works

1. **Pick:** PHPickerViewController filtered for Live Photos gives us the asset identifier
2. **Extract:** `PHAssetResource` finds the paired `.MOV` video and exports it to a temp file
3. **Frames:** `AVAssetImageGenerator` steps through the video at the chosen FPS
4. **Encode:** `CGImageDestination` (ImageIO) writes a GIF89a with proper frame delays
5. **Share:** Standard iOS share sheet or save directly to Photos

## Troubleshooting

**"Photo Access Required" alert:**
The app needs at least Limited photo library access. Go to Settings → LivePhotoToGIF → Photos and choose "Limited Access" or "Full Access".

**Picker shows no photos:**
If you granted "Limited Access", tap "Select More Photos" in the picker to add Live Photos to the selection.

**Build error about deployment target:**
Make sure the deployment target is iOS 16.0 or later:
Project → Target → General → Minimum Deployments → iOS 16.0

**GIF is too large:**
Lower the Max Width slider (try 320px) and reduce FPS to 10. Live Photo GIFs are typically 1–4 MB.
