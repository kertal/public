# Live Photo → GIF — macOS App Setup

A native macOS app for converting Live Photos to animated GIFs.
Drag-and-drop from Finder, pick from Photos, or use File → Open.

## Requirements

- **Xcode 15+** (free from the Mac App Store)
- **macOS 13 Ventura** or later (for PHPickerViewController on macOS)

## Quick Setup (5 minutes)

### 1. Create the Xcode project

1. Open **Xcode**
2. **File → New → Project**
3. Choose **macOS → App**, click Next
4. Fill in:
   - **Product Name:** `LivePhotoToGIF`
   - **Interface:** SwiftUI
   - **Language:** Swift
5. Choose a save location, click **Create**

### 2. Replace the template files

1. In the Project Navigator (left sidebar), **delete** the template `ContentView.swift`
   (right-click → Delete → Move to Trash)
2. Also delete `LivePhotoToGIFApp.swift` if present
3. Drag **all 5 Swift files** from this directory into the Project Navigator:
   - `LivePhotoToGIFApp.swift`
   - `ContentView.swift`
   - `Converter.swift`
   - `MacViews.swift`
4. When prompted, check **"Copy items if needed"** and click **Add**

### 3. Add Privacy Descriptions

1. Click the **project** (blue icon) in the Project Navigator
2. Select the **LivePhotoToGIF** target
3. Go to the **Info** tab
4. Under **Custom macOS Target Properties**, click **+** and add:

| Key | Value |
|-----|-------|
| `Privacy - Photo Library Usage Description` | `This app needs access to your Photos to read Live Photos and convert them to GIFs.` |

### 4. Enable App Sandbox Permissions

Since this is a sandboxed macOS app, you need to allow file reads:

1. Select the **LivePhotoToGIF** target
2. Go to the **Signing & Capabilities** tab
3. Under **App Sandbox**, enable:
   - **File Access → User Selected File** → Read Only
   - **Photos** (check the box)

If App Sandbox is not present, click **+ Capability** → App Sandbox.

### 5. Build & Run

Press **Cmd+R**. The app builds and runs on your Mac.

## Usage

### Drag & Drop (primary method)
- AirDrop a Live Photo from iPhone → two files arrive (.HEIC + .MOV)
- Drag the **.MOV** file onto the app window

### Pick from Photos
- Click **"Pick from Photos"** to browse your Mac's Photos library
- Only Live Photos are shown
- The app extracts the video automatically

### File → Open
- Click **"Open File..."** to use the standard macOS file dialog
- Select any .MOV or .MP4 file

### Conversion
1. Trim the clip using the Start/End sliders
2. Adjust FPS (10–30) and max width (200–1080px)
3. Click **Convert to GIF**
4. Use **Save As...**, **Reveal in Finder**, or **Share...**

## Troubleshooting

**"Pick from Photos" shows no photos:**
Grant photo library access in System Settings → Privacy & Security → Photos.

**Dragged file doesn't work:**
Make sure you're dropping the .MOV file, not the .HEIC. The .HEIC is just the still image.

**Build error about deployment target:**
Set the deployment target to macOS 13.0:
Project → Target → General → Minimum Deployments → macOS 13.0

**Sandbox error reading files:**
Make sure "User Selected File → Read Only" is enabled in Signing & Capabilities → App Sandbox.
