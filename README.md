# SwiftUI Media Viewer

A polished, SwiftUI-based media viewer for iOS that supports both images and videos with a native feel.
This viewer provides a user experience similar to Apple's Photos app with smooth transitions, responsive
gestures, and intuitive controls.

\![Platform](https://img.shields.io/badge/Platform-iOS%2016.0+-blue.svg)
\![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)

## Features

- **Native iOS Feel**: Mimics Apple's Photos app experience with smooth transitions and intuitive controls
- **Multi-Media Support**: Handles both images and videos in a unified interface
- **Advanced Gesture System**:
  - Swipe horizontally to navigate between media items
  - Pinch to zoom with proper centering
  - Pull down to dismiss with proportional scaling
  - Double-tap to zoom in/out
- **Video Playback**:
  - Custom video controls with scrubber
  - Auto-hiding overlay
  - Play/pause functionality
  - Video looping
  - Preview thumbnails
- **Thumbnail Grid View**:
  - LazyVGrid implementation for performance
  - Supports large collections
  - Visual indicators for media type
- **Responsive Design**:
  - Content follows user's touch for immediate feedback
  - Physics-based animations with velocity detection
  - Haptic feedback at key interaction points
- **iOS 18 Compatible**: Updated for modern API usage

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Manual Installation

1. Clone the repository:
```bash
git clone https://github.com/paulm/SwiftUI-Media-Viewer.git
```

2. Open the project in Xcode:
```bash
open "SwiftUI Media Viewer.xcodeproj"
```

3. Build and run the project on your device or simulator.

## Usage

### Basic Implementation

To use the media viewer in your own project, you'll need to:

1. Copy the key components:
   - `MediaViewer.swift` (contains all viewer components)
   - Add any required assets

2. Implement a simple viewer:

```swift
import SwiftUI

struct ContentView: View {
    @State private var showMediaViewer = false
    @State private var selectedIndex = 0
    
    let mediaItems = [
        MediaItem(url: yourImageURL, type: .image),
        MediaItem(url: yourVideoURL, type: .video)
    ]
    
    var body: some View {
        Button("Show Media") {
            selectedIndex = 0
            showMediaViewer = true
        }
        .fullScreenCover(isPresented: $showMediaViewer) {
            MediaViewer(
                startIndex: selectedIndex,
                mediaItems: mediaItems,
                onDismiss: {
                    showMediaViewer = false
                }
            )
        }
    }
}
```

### Grid Implementation

The included sample app demonstrates a grid-based implementation using LazyVGrid:

```swift
struct ContentView: View {
    @State private var showMediaViewer = false
    @State private var selectedMediaIndex = 0
    @State private var mediaItems: [MediaItem] = []
    
    let columns = [
        GridItem(.adaptive(minimum: 50, maximum: 75), spacing: 12)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                        MediaThumbnail(item: item) {
                            selectedMediaIndex = index
                            showMediaViewer = true
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .fullScreenCover(isPresented: $showMediaViewer) {
            MediaViewer(
                startIndex: selectedMediaIndex,
                mediaItems: mediaItems,
                onDismiss: {
                    showMediaViewer = false
                }
            )
        }
    }
}
```

## Component Architecture

The viewer is built with a clean component-based architecture:

- **MediaViewer**: Main container with gesture handling for navigation
- **ZoomableMediaView**: Component for handling zoom and pan gestures
- **ImageViewer**: Component for displaying and loading images
- **VideoPlayerView**: Component for video playback with custom controls
- **MediaThumbnail**: Used for grid display in ContentView

## Customization

Several aspects of the viewer can be customized:

### Appearance
- Modify control overlay styles in the `controlsOverlay` function
- Customize the background color in the `body` property
- Adjust loading and error placeholders in the respective view components

### Gestures
- Modify gesture sensitivity by adjusting threshold values
- Change animation timings and spring parameters for different feels
- Add or modify haptic feedback points

### Controls Behavior
- Adjust auto-hide delay timing in the `controlsAutoHideDelay` property
- Modify video controls appearance and layout

## Future Enhancements

Planned features for future releases:

- Sharing functionality for media items
- Network-based image/video loading with caching
- Enhanced error handling for network failures
- Support for additional media formats
- Loading indicators for high-resolution content
- Performance optimizations for very large collections
- Accessibility features for VoiceOver compatibility
- User preferences for gesture sensitivity

## License

This project is available under the MIT License. See the LICENSE file for more info.

## Author

Paul Mayne

## Acknowledgements

This project was inspired by Apple's Photos app and built using SwiftUI best practices.
