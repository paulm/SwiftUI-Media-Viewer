//
//  MediaViewer.swift
//  SwiftUI Media Viewer
//
//  Created by Paul Mayne on 3/18/25.
//

import SwiftUI
import AVKit

struct MediaItem: Identifiable {
    let id = UUID()
    let url: URL
    let type: MediaType
    
    enum MediaType {
        case image
        case video
    }
}

struct MediaViewer: View {
    let startIndex: Int
    let mediaItems: [MediaItem]
    let onDismiss: () -> Void
    
    // Main state
    @State private var currentIndex: Int
    @State private var targetIndex: Int? = nil
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var verticalDragOffset: CGFloat = 0
    @State private var dismissScale: CGFloat = 1.0
    @State private var dismissOpacity: CGFloat = 1.0
    
    // UI state
    @State private var showControls = true
    @State private var isZoomed = false
    
    // Animation state
    @State private var lastDragValue: DragGesture.Value?
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // Haptics
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    
    // Settings
    private let dismissThreshold: CGFloat = 80
    private let controlsAutoHideDelay: Double = 3.0
    
    init(startIndex: Int = 0, mediaItems: [MediaItem] = [], onDismiss: @escaping () -> Void) {
        self.startIndex = startIndex
        self.mediaItems = mediaItems
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: startIndex)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background for the entire view
                Color.black.ignoresSafeArea()
                
                if !mediaItems.isEmpty {
                    // Media content with drag gesture
                    mediaViewContent(geometry: geometry)
                    
                    // Controls overlay - only shown when not dragging
                    controlsOverlay(geometry: geometry)
                        .opacity(showControls ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: showControls)
                        .opacity(1.0 - min(1.0, abs(verticalDragOffset / dismissThreshold) * 2.0))
                } else {
                    // Empty state or loading
                    ProgressView()
                        .scaleEffect(1.5)
                        .foregroundColor(.white)
                }
            }
            .preferredColorScheme(.dark)
            .statusBar(hidden: true)
            .onAppear {
                prepareHaptics()
                autoHideControls()
            }
            .onTapGesture {
                toggleControls()
            }
        }
    }
    
    // Main content view with all gestures
    private func mediaViewContent(geometry: GeometryProxy) -> some View {
        ZStack {
            // Current item
            mediaItemView(for: currentIndex, geometry: geometry)
                .offset(x: dragOffset, y: verticalDragOffset)
                .scaleEffect(dismissScale)
                .opacity(dismissOpacity)
            
            // Preview previous item if dragging right
            if dragOffset > 0 && currentIndex > 0 {
                mediaItemView(for: currentIndex - 1, geometry: geometry)
                    .offset(x: -geometry.size.width + dragOffset, y: 0)
            }
            
            // Preview next item if dragging left
            if dragOffset < 0 && currentIndex < mediaItems.count - 1 {
                mediaItemView(for: currentIndex + 1, geometry: geometry)
                    .offset(x: geometry.size.width + dragOffset, y: 0)
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture()
                .onChanged { value in
                    handleDragChanged(value: value, geometry: geometry)
                }
                .onEnded { value in
                    handleDragEnded(value: value, geometry: geometry)
                }
        )
        .onTapGesture {
            // Handle tap gestures separately to avoid conflicts
            toggleControls()
        }
    }
    
    // Process drag gesture changes
    private func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy) {
        if isZoomed { return } // Don't handle parent drags when zoomed
        
        // First movement - determine direction
        if lastDragValue == nil {
            if abs(value.translation.width) > abs(value.translation.height) {
                // Horizontal drag for paging
                isDragging = true
            } else {
                // Vertical drag for dismissal
                isDragging = false
            }
        }
        
        if isDragging {
            // Horizontal drag - update with resistance at boundaries
            if (currentIndex == 0 && value.translation.width > 0) ||
                (currentIndex == mediaItems.count - 1 && value.translation.width < 0) {
                // Apply resistance at boundaries
                dragOffset = value.translation.width * 0.4
            } else {
                dragOffset = value.translation.width
            }
        } else {
            // Vertical drag - handle dismissal gesture
            verticalDragOffset = value.translation.height
            
            // Update scale and opacity for dismiss animation
            if verticalDragOffset > 0 {
                // Only add effects when dragging downward
                dismissScale = max(0.85, 1.0 - verticalDragOffset / 1000)
                dismissOpacity = max(0.5, 1.0 - verticalDragOffset / 500)
                
                // Hide controls during dismiss gesture
                if verticalDragOffset > 50 && showControls {
                    showControls = false
                }
            }
        }
        
        lastDragValue = value
    }
    
    // Process drag gesture ending
    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        if isDragging {
            // Handle horizontal drag (navigation between items)
            let velocity = calculateVelocity(value: value)
            let swipeThreshold = geometry.size.width * 0.3
            let significantSwipe = abs(dragOffset) > swipeThreshold || abs(velocity) > 0.5
            
            if dragOffset < 0 && significantSwipe && currentIndex < mediaItems.count - 1 {
                // Next item
                navigateToNextItem(geometry: geometry)
            } else if dragOffset > 0 && significantSwipe && currentIndex > 0 {
                // Previous item
                navigateToPreviousItem(geometry: geometry)
            } else {
                // Not enough to change - snap back
                cancelNavigation()
            }
        } else {
            // Handle vertical drag (dismiss gesture)
            if verticalDragOffset > dismissThreshold || value.velocity.height > 300 {
                // Dismiss the viewer
                withAnimation(.easeOut(duration: 0.2)) {
                    verticalDragOffset = geometry.size.height
                    dismissScale = 0.5
                    dismissOpacity = 0
                }
                
                // Haptic feedback
                hapticMedium.impactOccurred()
                
                // Dismiss after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onDismiss()
                }
            } else {
                // Not enough to dismiss - snap back
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    verticalDragOffset = 0
                    dismissScale = 1.0
                    dismissOpacity = 1.0
                }
                
                // Show controls again if they were hidden
                if !showControls {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            showControls = true
                        }
                    }
                }
            }
        }
        
        lastDragValue = nil
    }
    
    // Navigate to next item with animation
    private func navigateToNextItem(geometry: GeometryProxy) {
        targetIndex = currentIndex + 1
        hapticLight.impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dragOffset = -geometry.size.width
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            currentIndex = targetIndex!
            dragOffset = 0
            targetIndex = nil
            isDragging = false
        }
    }
    
    // Navigate to previous item with animation
    private func navigateToPreviousItem(geometry: GeometryProxy) {
        targetIndex = currentIndex - 1
        hapticLight.impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dragOffset = geometry.size.width
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            currentIndex = targetIndex!
            dragOffset = 0
            targetIndex = nil
            isDragging = false
        }
    }
    
    // Cancel navigation and reset position
    private func cancelNavigation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
        }
        isDragging = false
    }
    
    // Media item view builder
    @ViewBuilder
    private func mediaItemView(for index: Int, geometry: GeometryProxy) -> some View {
        let item = mediaItems[index]
        
        ZoomableMediaView(
            item: item,
            onZoomChanged: { isZoomed in
                self.isZoomed = isZoomed
                
                // Hide controls when zoomed
                if isZoomed && showControls {
                    withAnimation {
                        showControls = false
                    }
                }
            }
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    // Controls overlay view
    @ViewBuilder
    private func controlsOverlay(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top controls bar with gradient background
            VStack {
                HStack {
                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    // Page indicator
                    if mediaItems.count > 1 {
                        Text("\(currentIndex + 1) / \(mediaItems.count)")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    // Share button (placeholder)
                    Button {
                        // Share functionality would go here
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding(.top, geometry.safeAreaInsets.top)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.black.opacity(0.7), .black.opacity(0.0)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            Spacer()
            
            // Bottom controls (only for video) - handled in VideoPlayerView
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    // Calculate velocity for swipe gestures
    private func calculateVelocity(value: DragGesture.Value) -> CGFloat {
        guard let lastValue = lastDragValue else { return 0 }
        
        let timeDifference = value.time.timeIntervalSince(lastValue.time)
        if timeDifference > 0 {
            let distance = value.translation.width - lastValue.translation.width
            return distance / CGFloat(timeDifference)
        }
        
        return 0
    }
    
    // Prepare haptics for better performance
    private func prepareHaptics() {
        hapticLight.prepare()
        hapticMedium.prepare()
    }
    
    // Auto-hide controls after delay
    private func autoHideControls() {
        DispatchQueue.main.asyncAfter(deadline: .now() + controlsAutoHideDelay) {
            if !isDragging && !isZoomed && showControls {
                withAnimation {
                    showControls = false
                }
            }
        }
    }
    
    // Toggle controls visibility with timers
    private func toggleControls() {
        withAnimation {
            showControls.toggle()
        }
        
        // Auto-hide again after delay
        if showControls {
            autoHideControls()
        }
    }
}

// MARK: - Zoomable Media View

struct ZoomableMediaView: View {
    let item: MediaItem
    let onZoomChanged: (Bool) -> Void
    
    // Zoom state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var pinchStartLocation: CGPoint?
    
    // Settings
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    private let zoomAnimationDuration: Double = 0.3
    
    // Haptics
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Media content based on type
                Group {
                    if item.type == .image {
                        ImageViewer(url: item.url)
                            .scaleEffect(scale)
                            .offset(offset)
                    } else {
                        VideoPlayerView(item: item)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                
                // Only add gesture overlay when zoomed, to avoid interfering with parent gestures
                if scale > 1.05 {
                    // Invisible overlay for gestures when zoomed
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    handleDragChanged(value: value)
                                }
                                .onEnded { value in
                                    handleDragEnded(value: value, geometry: geometry)
                                }
                        )
                }
            }
            // These gestures apply regardless of zoom state
            .gesture(
                // Magnification (pinch) gesture for zooming
                MagnificationGesture()
                    .onChanged { value in
                        handlePinchChanged(value: value)
                    }
                    .onEnded { _ in
                        handlePinchEnded(geometry: geometry)
                    }
            )
            .onTapGesture(count: 2) { location in
                handleDoubleTap(location: location, geometry: geometry)
            }
        }
        .onAppear {
            haptic.prepare()
        }
    }
    
    // Handle pinch gesture changes
    private func handlePinchChanged(value: MagnificationGesture.Value) {
        let delta = value / lastScale
        lastScale = value
        
        // Apply zoom with spring-like resistance at extremes
        let newScale = scale * delta
        if newScale <= minScale {
            scale = minScale + (newScale - minScale) * 0.2
        } else if newScale >= maxScale {
            scale = maxScale + (newScale - maxScale) * 0.2
        } else {
            scale = newScale
        }
        
        // Notify parent about zoom state
        onZoomChanged(scale > 1.05)
    }
    
    // Handle pinch gesture ending
    private func handlePinchEnded(geometry: GeometryProxy) {
        lastScale = 1.0
        
        // Snap back if out of bounds or almost back to minimum
        if scale < minScale + 0.2 {
            withAnimation(.spring(response: zoomAnimationDuration, dampingFraction: 0.7)) {
                scale = minScale
                offset = .zero
                lastOffset = .zero
            }
            onZoomChanged(false)
        } else if scale > maxScale - 0.2 {
            withAnimation(.spring(response: zoomAnimationDuration, dampingFraction: 0.7)) {
                scale = maxScale
            }
        }
        
        // Constrain offset after scale change
        constrainOffset(geometry: geometry)
    }
    
    // Handle drag gesture changes
    private func handleDragChanged(value: DragGesture.Value) {
        // Only allow panning when zoomed in
        if scale > 1.05 {
            offset = CGSize(
                width: lastOffset.width + value.translation.width,
                height: lastOffset.height + value.translation.height
            )
        }
    }
    
    // Handle drag gesture ending
    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        // Only handle for zoomed state
        if scale > 1.05 {
            lastOffset = offset
            constrainOffset(geometry: geometry)
        }
    }
    
    // Handle double tap to zoom
    private func handleDoubleTap(location: CGPoint, geometry: GeometryProxy) {
        // Double tap to zoom in/out with haptic feedback
        haptic.impactOccurred()
        
        if scale > 1.05 {
            // Zoom out
            withAnimation(.spring(response: zoomAnimationDuration, dampingFraction: 0.7)) {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            }
            onZoomChanged(false)
        } else {
            // Zoom in centered on tap location
            withAnimation(.spring(response: zoomAnimationDuration, dampingFraction: 0.7)) {
                scale = 2.5
                
                // Center on tap location
                let tapPoint = CGPoint(
                    x: location.x - geometry.size.width/2,
                    y: location.y - geometry.size.height/2
                )
                
                offset = CGSize(
                    width: -tapPoint.x,
                    height: -tapPoint.y
                )
                lastOffset = offset
            }
            onZoomChanged(true)
        }
    }
    
    // Constrain offset after zoom changes to keep content visible
    private func constrainOffset(geometry: GeometryProxy) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            // Calculate max offset based on scaled size
            let maxOffsetWidth = max(0, (geometry.size.width * (scale - 1)) / 2)
            let maxOffsetHeight = max(0, (geometry.size.height * (scale - 1)) / 2)
            
            // Constrain offset to keep image visible
            offset.width = min(maxOffsetWidth, max(-maxOffsetWidth, offset.width))
            offset.height = min(maxOffsetHeight, max(-maxOffsetHeight, offset.height))
            lastOffset = offset
        }
    }
}

// MARK: - Image Viewer

struct ImageViewer: View {
    let url: URL
    
    // Loading state
    @State private var isLoaded = false
    @State private var loadingError = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black
            
            // Optimized image loading
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    loadingPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                        .onAppear {
                            withAnimation(.easeIn(duration: 0.2)) {
                                isLoaded = true
                            }
                        }
                case .failure:
                    errorPlaceholder
                @unknown default:
                    EmptyView()
                }
            }
        }
        .ignoresSafeArea(.all)
    }
    
    // Loading placeholder
    var loadingPlaceholder: some View {
        VStack(spacing: 15) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Loading image...")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    // Error placeholder
    var errorPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 70))
                .foregroundColor(.white)
            Text("Image failed to load")
                .foregroundColor(.white)
            
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 8)
        }
    }
}

// MARK: - Video Player View

struct VideoPlayerView: View {
    let item: MediaItem
    
    // Player state
    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var thumbnailImage: UIImage? = nil
    
    // Time observer token
    @State private var timeObserverToken: Any?
    
    init(item: MediaItem) {
        self.item = item
        _player = State(initialValue: AVPlayer(url: item.url))
    }
    
    var body: some View {
        ZStack {
            // Video player
            VideoPlayer(player: player)
                .ignoresSafeArea(.all)
                .disabled(showControls) // Prevent default tap handler
                .onAppear {
                    setupPlayer()
                }
                .onDisappear {
                    cleanup()
                }
            
            // Thumbnail overlay (shown before video loads)
            if thumbnailImage != nil && !isPlaying {
                Image(uiImage: thumbnailImage!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            
            // Custom overlay controls
            if showControls {
                videoControlsOverlay
                    .transition(.opacity)
            }
        }
        .onTapGesture {
            toggleControls()
        }
    }
    
    // Video controls overlay
    var videoControlsOverlay: some View {
        VStack {
            Spacer()
            
            // Video controls
            VStack(spacing: 12) {
                // Progress bar
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)
                    
                    // Progress track
                    Capsule()
                        .fill(Color.white)
                        .frame(width: (currentTime / max(duration, 1)) * UIScreen.main.bounds.width - 32, height: 4)
                    
                    // Thumb for scrubbing
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .offset(x: (currentTime / max(duration, 1)) * (UIScreen.main.bounds.width - 44) - 6)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isScrubbing = true
                                    player.pause()
                                    
                                    // Calculate new time position
                                    let dragPosition = value.location.x
                                    let screenWidth = UIScreen.main.bounds.width - 32
                                    let percentage = dragPosition / screenWidth
                                    currentTime = min(max(0, percentage * duration), duration)
                                }
                                .onEnded { _ in
                                    // Seek to the new position
                                    player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                                    
                                    // Resume playback if it was playing before
                                    if isPlaying {
                                        player.play()
                                    }
                                    
                                    isScrubbing = false
                                }
                        )
                }
                .padding(.horizontal, 16)
                
                // Time display and controls
                HStack {
                    // Current time
                    Text(formatTime(seconds: currentTime))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    // Play/Pause button
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    // Total duration
                    Text(formatTime(seconds: duration))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea(.all)
    }
    
    // Toggle play/pause
    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    // Toggle controls visibility
    private func toggleControls() {
        withAnimation {
            showControls.toggle()
        }
        
        // Auto-hide after delay
        if showControls {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !isScrubbing {
                    withAnimation {
                        showControls = false
                    }
                }
            }
        }
    }
    
    // Set up the player and observers
    private func setupPlayer() {
        // Generate thumbnail for initial display
        generateThumbnail()
        
        // Add time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isScrubbing {
                currentTime = time.seconds
            }
        }
        
        // Get duration
        if let playerItem = player.currentItem {
            // Try to get duration directly if available
            duration = playerItem.duration.seconds
            
            // Listen for when duration becomes available
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
            
            // Listen for status changes to get duration when ready
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name.AVPlayerItemNewAccessLogEntry,
                object: nil,
                queue: .main
            ) { _ in
                if duration <= 0 {
                    duration = playerItem.duration.seconds
                }
            }
        }
        
        // Start playing
        player.play()
        isPlaying = true
        
        // Auto-hide controls after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showControls = false
            }
        }
    }
    
    // Clean up resources
    private func cleanup() {
        // Remove time observer
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        // Stop and clean up player
        player.pause()
        player.replaceCurrentItem(with: nil)
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.AVPlayerItemNewAccessLogEntry,
            object: nil
        )
    }
    
    // Generate thumbnail for video preview
    private func generateThumbnail() {
        // Use AVURLAsset instead of AVAsset(url:) for iOS 18 compatibility
        let asset = AVURLAsset(url: item.url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Use the new async method for iOS 18 compatibility
        if #available(iOS 18.0, *) {
            // Use the new asynchronous API
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            // No need for a variable capture as Swift structs don't need weak references
            
            imageGenerator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                if let cgImage = cgImage {
                    DispatchQueue.main.async {
                        // Update the property on the main thread
                        self.thumbnailImage = UIImage(cgImage: cgImage)
                    }
                }
            }
        } else {
            // Use the deprecated synchronous API for older iOS versions
            do {
                #if compiler(>=5.9)
                @preconcurrency let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60), actualTime: nil)
                #else
                let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60), actualTime: nil)
                #endif
                thumbnailImage = UIImage(cgImage: cgImage)
            } catch {
                print("Error generating thumbnail: \(error)")
            }
        }
    }
    
    // Format time for display
    private func formatTime(seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Preview

#Preview {
    MediaViewer(
        startIndex: 0,
        mediaItems: [
            MediaItem(url: URL(string: "file:///example.jpg")!, type: .image),
            MediaItem(url: URL(string: "file:///example.mp4")!, type: .video)
        ],
        onDismiss: {}
    )
}