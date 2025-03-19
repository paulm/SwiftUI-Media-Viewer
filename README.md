# SwiftUI Media Viewer

A polished, SwiftUI-based media viewer for iOS that supports both images and videos with a native feel.
This viewer provides a user experience similar to Apple's Photos app with smooth transitions, responsive
gestures, and intuitive controls.

![Platform](https://img.shields.io/badge/Platform-iOS%2016.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)

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

## Implementation Details

### Media Item Structure

The `MediaItem` struct encapsulates both images and videos:

```swift
struct MediaItem: Identifiable {
    let id = UUID()
    let url: URL
    let type: MediaType
    var thumbnailImage: UIImage?
    
    enum MediaType {
        case image
        case video
    }
}
```

### Gesture Handling

The viewer uses a sophisticated gesture system:

```swift
// Horizontal swipe for navigation
var dragGesture: some Gesture {
    DragGesture()
        .onChanged { value in
            withAnimation(.interactiveSpring()) {
                offsetX = value.translation.width
            }
        }
        .onEnded { value in
            let threshold = screenWidth * 0.25
            let velocity = value.predictedEndLocation.x - value.location.x
            
            if offsetX > threshold || velocity > 500 {
                if currentIndex > 0 {
                    withAnimation(.spring()) {
                        currentIndex -= 1
                        offsetX = 0
                    }
                    hapticFeedback(.medium)
                } else {
                    withAnimation(.spring()) { offsetX = 0 }
                }
            } else if offsetX < -threshold || velocity < -500 {
                if currentIndex < mediaItems.count - 1 {
                    withAnimation(.spring()) {
                        currentIndex += 1
                        offsetX = 0
                    }
                    hapticFeedback(.medium)
                } else {
                    withAnimation(.spring()) { offsetX = 0 }
                }
            } else {
                withAnimation(.spring()) { offsetX = 0 }
            }
        }
}
```

### ZoomableMediaView

The `ZoomableMediaView` handles zooming and panning:

```swift
struct ZoomableMediaView<Content: View>: View {
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var isInteracting: Bool = false
    
    let content: Content
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    
    init(@ViewBuilder content: () -> Content, 
         onTap: @escaping () -> Void,
         onDoubleTap: @escaping () -> Void) {
        self.content = content()
        self.onTap = onTap
        self.onDoubleTap = onDoubleTap
    }
    
    var body: some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .gesture(panGesture)
            .gesture(zoomGesture)
            .gesture(tapGesture)
            .gesture(doubleTapGesture)
            .animation(isInteracting ? .interactiveSpring() : .spring(), value: scale)
            .animation(isInteracting ? .interactiveSpring() : .spring(), value: offset)
    }
    
    // Gesture implementations...
}
```

### VideoPlayerView

The `VideoPlayerView` handles video playback with custom controls:

```swift
struct VideoPlayerView: View {
    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var seekPosition: Double = 0
    @State private var duration: Double = 0
    
    let url: URL
    
    init(url: URL) {
        self.url = url
        let player = AVPlayer(url: url)
        self._player = State(initialValue: player)
    }
    
    var body: some View {
        ZStack {
            VideoPlayer(player: player)
                .aspectRatio(contentMode: .fit)
                .onAppear {
                    setupPlayer()
                }
                .onDisappear {
                    player.pause()
                }
            
            if showControls {
                controlsOverlay
            }
        }
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
    }
    
    // Video player setup and control methods...
}
```

### Performance Optimizations

The viewer uses several techniques to maintain smooth performance:

1. **Lazy Loading**: Media items are loaded only when needed
2. **Prefetching**: Adjacent items are prefetched to ensure smooth navigation
3. **Memory Management**: Resources are released when no longer needed
4. **Async Image Loading**: Images are loaded asynchronously to prevent UI blocking
5. **Hardware Acceleration**: Uses Metal for image rendering when available

### Accessibility

The viewer includes accessibility features:

```swift
.accessibilityLabel("Image \(currentIndex + 1) of \(mediaItems.count)")
.accessibilityAddTraits(.isImage)
.accessibilityAction(named: "Next Image") {
    if currentIndex < mediaItems.count - 1 {
        withAnimation { currentIndex += 1 }
    }
}
.accessibilityAction(named: "Previous Image") {
    if currentIndex > 0 {
        withAnimation { currentIndex -= 1 }
    }
}
.accessibilityAction(named: "Close Viewer") {
    onDismiss()
}
```

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