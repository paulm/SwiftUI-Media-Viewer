//
//  MediaViewer.swift
//  SwiftUI Media Viewer
//
//  Created by Paul Mayne on 3/18/25.
//

import SwiftUI
import AVKit
import Combine

// MARK: - Models

struct MediaItem: Identifiable {
    let id = UUID()
    let url: URL
    let type: MediaType
    
    enum MediaType {
        case image
        case video
    }
}

// MARK: - View Models

@Observable
class MediaViewerModel {
    // Media collection data
    var mediaItems: [MediaItem] = []
    var currentIndex: Int = 0
    
    // UI State
    var isZoomed: Bool = false
    var showControls: Bool = true
    var isPlaying: Bool = false
    
    // Navigation State
    var dragDirection: DragDirection = .none
    var dragOffset: CGFloat = 0
    var verticalDragOffset: CGFloat = 0
    var dismissOpacity: CGFloat = 1.0
    var isDragging: Bool = false  // Track active dragging state
    
    // Zoom State
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero
    
    // Settings
    let dismissThreshold: CGFloat = 80
    let controlsAutoHideDelay: Double = 3.0
    let zoomRange: ClosedRange<CGFloat> = 1.0...4.0
    
    // Computed properties
    var currentItem: MediaItem? {
        guard !mediaItems.isEmpty, currentIndex >= 0, currentIndex < mediaItems.count else { 
            return nil 
        }
        return mediaItems[currentIndex]
    }
    
    var previousItem: MediaItem? {
        guard currentIndex > 0, !mediaItems.isEmpty else { return nil }
        return mediaItems[currentIndex - 1]
    }
    
    var nextItem: MediaItem? {
        guard currentIndex < mediaItems.count - 1, !mediaItems.isEmpty else { return nil }
        return mediaItems[currentIndex + 1]
    }
    
    // Behavior
    var onDismiss: () -> Void = {}
    
    enum DragDirection {
        case horizontal, vertical, none
    }
    
    // Actions
    func resetDragState() {
        dragOffset = 0
        verticalDragOffset = 0
        dismissOpacity = 1.0
        dragDirection = .none
    }
    
    func navigateToNextItem() {
        guard currentIndex < mediaItems.count - 1 else { return }
        currentIndex += 1
        resetDragState()
    }
    
    func navigateToPreviousItem() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        resetDragState()
    }
    
    func resetZoom() {
        scale = 1.0
        offset = .zero
        isZoomed = false
    }
    
    func autoHideControls() {
        guard showControls else { return }
        
        Task {
            try? await Task.sleep(for: .seconds(controlsAutoHideDelay))
            await MainActor.run {
                // Only hide if conditions are still right for hiding
                if !isZoomed && showControls && dragDirection == .none && !isDragging {
                    showControls = false
                }
            }
        }
    }
    
    func toggleControls() {
        showControls.toggle()
        if showControls {
            autoHideControls()
        }
    }
}

struct MediaViewer: View {
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // Model
    @State private var model: MediaViewerModel
    
    // Haptics
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    
    // Track gesture state for calculations
    @State private var lastDragValue: DragGesture.Value?
    @State private var dragVelocity: CGFloat = 0
    
    init(startIndex: Int = 0, mediaItems: [MediaItem] = [], onDismiss: @escaping () -> Void) {
        let model = MediaViewerModel()
        model.mediaItems = mediaItems
        model.currentIndex = startIndex
        model.onDismiss = onDismiss
        self._model = State(initialValue: model)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background for the entire view
                Color.black.ignoresSafeArea()
                
                if !model.mediaItems.isEmpty, let currentItem = model.currentItem {
                    // Media content with gesture handling
                    mediaContent(geometry: geometry)
                    
                    // Controls overlay with animation and opacity
                    controlsOverlay(geometry: geometry)
                        .opacity(model.showControls ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: model.showControls)
                        .opacity(1.0 - min(1.0, abs(model.verticalDragOffset / model.dismissThreshold) * 2.0))
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
                model.autoHideControls()
            }
            // Only toggle controls when not actively dragging to avoid conflicts
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        if !model.isDragging {
                            model.toggleControls()
                        }
                    }
            )
        }
    }
    
    // Main content container with all media items and gestures
    @ViewBuilder
    private func mediaContent(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            // Implementation with spacing between items but fixed size
            ZStack {
                // Current item is always at 1.0 scale - no scaling during regular dragging
                mediaItemView(for: model.currentItem, geometry: geometry)
                
                // Previous item (preloaded when dragging right) - with spacing only
                if model.dragOffset > 0, let previousItem = model.previousItem {
                    mediaItemView(for: previousItem, geometry: geometry)
                        .offset(x: -(geometry.size.width + 60)) // Add 60pt spacing
                }
                
                // Next item (preloaded when dragging left) - with spacing only
                if model.dragOffset < 0, let nextItem = model.nextItem {
                    mediaItemView(for: nextItem, geometry: geometry)
                        .offset(x: geometry.size.width + 60) // Add 60pt spacing
                }
            }
            .offset(x: model.dragOffset, y: model.verticalDragOffset) // Direct drag translation
            // Only apply opacity change during drag, maintain full size
            .opacity(model.dismissOpacity)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0.1) // Extremely low threshold for immediate response
                .onChanged { value in
                    // Immediately set isDragging state on first movement
                    model.isDragging = true
                    
                    // Direct assignment of translation with absolutely no filtering
                    // This ensures 1:1 movement with your finger
                    model.dragOffset = value.translation.width
                    model.verticalDragOffset = value.translation.height
                    
                    // Only adjust opacity during drag, no scale changes
                    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    model.dismissOpacity = max(0.7, 1.0 - dragDistance / 1000)
                    
                    // Hide controls immediately on drag
                    if model.showControls {
                        model.showControls = false
                    }
                    
                    // Track dominant direction for end handling but don't restrict movement
                    if abs(value.translation.width) > abs(value.translation.height) {
                        model.dragDirection = .horizontal
                    } else {
                        model.dragDirection = .vertical
                    }
                    
                    // Save for velocity calculation
                    lastDragValue = value
                }
                .onEnded { value in
                    handleDragEnded(value: value, geometry: geometry)
                }
        )
    }
    
    // Calculate velocity from last drag value
    private func calculateVelocity(from value: DragGesture.Value) -> CGFloat {
        guard let lastValue = lastDragValue else { return 0 }
        
        let timeDelta = value.time.timeIntervalSince(lastValue.time)
        if timeDelta <= 0 { return 0 }
        
        // Calculate overall velocity
        let xDelta = value.translation.width - lastValue.translation.width
        let yDelta = value.translation.height - lastValue.translation.height
        return sqrt(pow(xDelta, 2) + pow(yDelta, 2)) / CGFloat(timeDelta)
    }
    
    // Handle drag gesture ending
    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        // Calculate gestures metrics for animations
        let dragDistance = sqrt(pow(model.dragOffset, 2) + pow(model.verticalDragOffset, 2))
        let velocity = calculateVelocity(from: value)
        let predictiveDistance = value.predictedEndLocation.x - value.location.x
        let isPredictiveSwipe = abs(predictiveDistance) > geometry.size.width * 0.1
        
        // Thresholds - account for spacing and be more forgiving with higher velocity
        let velocityImpact = min(1.0, velocity / 500)
        let itemSpacing = 60.0 // Match spacing between items
        let horizontalThreshold = (geometry.size.width + itemSpacing) * 0.2 * (1.0 - velocityImpact*0.5)
        let verticalThreshold = model.dismissThreshold * (1.0 - velocityImpact*0.5)
        
        // CASE 1: Dismiss (vertical swipe)
        if (model.dragDirection == .vertical && model.verticalDragOffset > verticalThreshold) ||
           (model.verticalDragOffset > 120) {
            
            // Animation to dismiss - no scale change
            withAnimation(.easeOut(duration: 0.25)) {
                model.verticalDragOffset = geometry.size.height
                model.dismissOpacity = 0
            }
            
            hapticMedium.impactOccurred()
            
            // Dismiss after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                model.onDismiss()
            }
            
        // CASE 2: Next item (left swipe)
        } else if (model.dragOffset < -horizontalThreshold || 
                  (isPredictiveSwipe && predictiveDistance < 0)) && 
                  model.currentIndex < model.mediaItems.count - 1 {
            
            // Simple slide animation to next item
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                model.dragOffset = -(geometry.size.width + 60) // Match the spacing we added
                model.verticalDragOffset = 0
            }
            
            hapticLight.impactOccurred()
            
            // Navigate after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                model.navigateToNextItem()
            }
            
        // CASE 3: Previous item (right swipe)
        } else if (model.dragOffset > horizontalThreshold || 
                  (isPredictiveSwipe && predictiveDistance > 0)) && 
                  model.currentIndex > 0 {
            
            // Simple slide animation to previous item
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                model.dragOffset = geometry.size.width + 60 // Match the spacing we added
                model.verticalDragOffset = 0
            }
            
            hapticLight.impactOccurred()
            
            // Navigate after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                model.navigateToPreviousItem()
            }
            
        // CASE 4: Not enough movement - bounce back with physics-like animation
        } else {
            // Calculate bounce parameters based on speed & distance
            let speed = max(velocity / 800, dragDistance / 1000)
            let springResponse = 0.3 + min(0.15, speed)
            let springDampingFraction = 0.7 - min(0.25, speed) // Less damping = more bounce
            
            // Bounce-back animation - no scale change
            withAnimation(.spring(response: springResponse, 
                                 dampingFraction: springDampingFraction, 
                                 blendDuration: 0.2)) {
                model.dragOffset = 0
                model.verticalDragOffset = 0
                model.dismissOpacity = 1.0
            }
            
            // Restore controls with slight delay
            if !model.showControls {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        model.showControls = true
                    }
                }
            }
        }
        
        // Reset gesture tracking state
        lastDragValue = nil
        dragVelocity = 0
        model.dragDirection = .none
        model.isDragging = false
    }
    
    // Media item view builder - uses optional binding for safety
    @ViewBuilder
    private func mediaItemView(for item: MediaItem?, geometry: GeometryProxy) -> some View {
        if let item = item {
            // Disable gestures within the media item when parent is dragging
            MediaItemView(
                item: item, 
                model: model,
                geometry: geometry,
                allowGestures: !model.isDragging // Disable gestures when parent is dragging
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(!model.isDragging) // Critical for smooth parent dragging
        } else {
            // Fallback for no item
            Color.black
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    // Controls overlay view
    @ViewBuilder
    private func controlsOverlay(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top controls with gradient background
            VStack {
                HStack {
                    // Close button
                    Button(action: model.onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    // Page indicator
                    if model.mediaItems.count > 1 {
                        Text("\(model.currentIndex + 1) / \(model.mediaItems.count)")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    // Share button (placeholder)
                    Button {
                        // Share functionality
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
    
    // Prepare haptics for better performance
    private func prepareHaptics() {
        hapticLight.prepare()
        hapticMedium.prepare()
    }
}
    
// MARK: - Media Item View

struct MediaItemView: View {
    let item: MediaItem
    @Bindable var model: MediaViewerModel
    let geometry: GeometryProxy
    var allowGestures: Bool = true // New parameter to control gesture handling
    
    // Local state for zooming
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    // Haptic feedback
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        ZStack {
            // Content based on media type
            Group {
                if item.type == .image {
                    ImageView(url: item.url)
                        .scaleEffect(model.scale)
                        .offset(model.offset)
                        .gesture(allowGestures ? getZoomGesture() : nil)
                } else {
                    VideoView(item: item, showControls: $model.showControls)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            
            // Add pan gesture for zoomed state only when gestures are allowed
            if model.isZoomed && allowGestures {
                // Invisible overlay for gesture handling when zoomed
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(getPanGesture())
            }
        }
        .onTapGesture(count: 2) { location in
            if allowGestures {
                handleDoubleTap(location: location)
            }
        }
        .onAppear {
            haptic.prepare()
        }
    }
    
    // MARK: - Gestures
    
    // Zoom (pinch) gesture
    private func getZoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                
                // Apply zoom with bounce effect at extremes
                let newScale = model.scale * delta
                if newScale <= model.zoomRange.lowerBound {
                    model.scale = model.zoomRange.lowerBound + (newScale - model.zoomRange.lowerBound) * 0.2
                } else if newScale >= model.zoomRange.upperBound {
                    model.scale = model.zoomRange.upperBound + (newScale - model.zoomRange.upperBound) * 0.2
                } else {
                    model.scale = newScale
                }
                
                // Update zoom state
                model.isZoomed = model.scale > 1.05
                
                // Hide controls when zoomed
                if model.isZoomed && model.showControls {
                    withAnimation {
                        model.showControls = false
                    }
                }
            }
            .onEnded { _ in
                lastScale = 1.0
                
                // Snap back to bounds if needed
                if model.scale < model.zoomRange.lowerBound + 0.2 {
                    withAnimation(.spring()) {
                        model.resetZoom()
                    }
                } else if model.scale > model.zoomRange.upperBound - 0.2 {
                    withAnimation(.spring()) {
                        model.scale = model.zoomRange.upperBound
                    }
                }
                
                // Constrain the offset
                constrainOffset()
            }
    }
    
    // Pan gesture for moving image when zoomed
    private func getPanGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow panning when zoomed in
                if model.isZoomed {
                    model.offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                lastOffset = model.offset
                constrainOffset()
            }
    }
    
    // Double tap to zoom in/out
    private func handleDoubleTap(location: CGPoint) {
        haptic.impactOccurred()
        
        if model.isZoomed {
            // Zoom out
            withAnimation(.spring()) {
                model.resetZoom()
            }
        } else {
            // Zoom in centered on tap location
            withAnimation(.spring()) {
                model.scale = 2.5
                model.isZoomed = true
                
                // Center on tap location
                let tapPoint = CGPoint(
                    x: location.x - geometry.size.width/2,
                    y: location.y - geometry.size.height/2
                )
                
                model.offset = CGSize(
                    width: -tapPoint.x,
                    height: -tapPoint.y
                )
                lastOffset = model.offset
            }
        }
    }
    
    // Constrain offset to keep the image in view
    private func constrainOffset() {
        withAnimation(.spring()) {
            // Calculate max offset based on scaled size
            let maxOffsetWidth = max(0, (geometry.size.width * (model.scale - 1)) / 2)
            let maxOffsetHeight = max(0, (geometry.size.height * (model.scale - 1)) / 2)
            
            // Constrain offset to keep image visible
            model.offset.width = min(maxOffsetWidth, max(-maxOffsetWidth, model.offset.width))
            model.offset.height = min(maxOffsetHeight, max(-maxOffsetHeight, model.offset.height))
            lastOffset = model.offset
        }
    }
}

// MARK: - Image View

struct ImageView: View {
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

// MARK: - Video View

struct VideoView: View {
    let item: MediaItem
    @Binding var showControls: Bool
    
    // Video player state
    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var thumbnailImage: UIImage? = nil
    
    // Time observer token
    @State private var timeObserverToken: Any?
    
    init(item: MediaItem, showControls: Binding<Bool>) {
        self.item = item
        self._showControls = showControls
        self._player = State(initialValue: AVPlayer(url: item.url))
    }
    
    var body: some View {
        ZStack {
            // Video player
            VideoPlayer(player: player)
                .ignoresSafeArea()
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
            
            // Custom overlay controls when showing controls
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
                    
                    // Draggable thumb
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
        .ignoresSafeArea()
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
        
        // Auto-hide controls after delay
        if showControls {
            autoHideControls()
        }
    }
    
    // Auto-hide controls after delay
    private func autoHideControls() {
        guard showControls else { return }
        
        Task {
            try? await Task.sleep(for: .seconds(3.0))
            if !isScrubbing && showControls {
                await MainActor.run {
                    withAnimation {
                        showControls = false
                    }
                }
            }
        }
    }
    
    // Set up player and observers
    private func setupPlayer() {
        // Generate thumbnail for initial display
        generateThumbnail()
        
        // Add time observer for progress updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isScrubbing {
                currentTime = time.seconds
            }
        }
        
        // Get duration when available
        if let playerItem = player.currentItem {
            // Try to get duration directly if available
            duration = playerItem.duration.seconds
            
            // Listen for when playback completes
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
        autoHideControls()
    }
    
    // Clean up player resources
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
        NotificationCenter.default.removeObserver(self)
    }
    
    // Generate thumbnail for preview
    private func generateThumbnail() {
        let asset = AVURLAsset(url: item.url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 60), actualTime: nil)
            thumbnailImage = UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
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
