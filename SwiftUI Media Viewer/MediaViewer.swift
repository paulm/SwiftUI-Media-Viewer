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

// MARK: - MediaViewer

struct MediaViewer: View {
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // Model
    @State private var model: MediaViewerModel
    
    // UI State
    @State private var isDismissing = false
    @State private var verticalDragOffset: CGFloat = 0
    @State private var animationProgress: CGFloat = 0
    
    // Hero animation
    let sourceFrame: CGRect
    @State private var isAnimatingEntry = true
    
    // Haptics
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    
    init(startIndex: Int = 0, mediaItems: [MediaItem] = [], sourceFrame: CGRect = .zero, onDismiss: @escaping () -> Void) {
        self.sourceFrame = sourceFrame
        let model = MediaViewerModel()
        model.mediaItems = mediaItems
        model.currentIndex = startIndex
        model.onDismiss = onDismiss
        self._model = State(initialValue: model)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Clear background for the hero animation
                Color.clear
                    .ignoresSafeArea()
                
                // Black background that fades in
                Color.black.opacity(animationProgress)
                    .ignoresSafeArea()
                
                if !model.mediaItems.isEmpty, let currentItem = model.currentItem {
                    // Hero animation for entry
                    if isAnimatingEntry, model.currentIndex < model.mediaItems.count {
                        let item = model.mediaItems[model.currentIndex]
                        heroAnimationView(for: item, in: geometry)
                    }
                    // Main carousel with UIPageViewController for stable behavior
                    carouselView(geometry: geometry)
                        .offset(y: verticalDragOffset)
                        .opacity(animationProgress) // Simple fade in/out with animationProgress
                        // Apply a scale effect during vertical drag to provide visual feedback
                        .scaleEffect(
                            verticalDragOffset != 0 ? 
                                max(0.8, 1.0 - (abs(verticalDragOffset) / (geometry.size.height * 2.5))) : 1.0
                        )
                    
                    // Controls overlay with animation and opacity
                    controlsOverlay(geometry: geometry)
                        .opacity(model.showControls ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: model.showControls)
                        .opacity(1.0 - min(1.0, abs(verticalDragOffset / model.dismissThreshold) * 2.0))
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
                
                // Add notification observers for UIKit interaction
                setupNotificationObservers()
                
                // Initialize animation progress
                animationProgress = 0
                
                // Start the hero animation
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    animationProgress = 1.0
                }
                
                // Hide hero animation view after it completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation {
                        isAnimatingEntry = false
                    }
                    model.autoHideControls()
                }
            }
            .onDisappear {
                // Remove notification observers
                NotificationCenter.default.removeObserver(self, name: Notification.Name("MediaViewerToggleControls"), object: nil)
                NotificationCenter.default.removeObserver(self, name: Notification.Name("MediaViewerZoomChanged"), object: nil)
            }
            // Only toggle controls when not actively being dragged
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        if !model.isDragging && !model.isZoomed {
                            model.toggleControls()
                        }
                    }
            )
            // Add vertical dismiss gesture that works alongside UIPageViewController
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only apply vertical drags when not zoomed (horizontal handled by PageViewController)
                        if !model.isZoomed && abs(value.translation.height) > abs(value.translation.width) * 1.5 {
                            // Require a significantly more vertical gesture to avoid conflicts with horizontal swiping
                            model.isDragging = true
                            
                            // Apply resistance to make the drag feel natural
                            let amount = value.translation.height
                            let resistance: CGFloat = 0.75 // More resistance = less movement
                            verticalDragOffset = amount * resistance
                            
                            // Calculate opacity based on drag percentage
                            let dragPercentage = min(1.0, abs(verticalDragOffset) / model.dismissThreshold)
                            let newOpacity = 1.0 - (dragPercentage * 0.5) // Dim slightly while dragging
                            
                            // Hide controls during drag
                            if model.showControls {
                                model.showControls = false
                            }
                            
                            // Light haptic feedback when drag reaches threshold
                            if abs(verticalDragOffset) > model.dismissThreshold && 
                                abs(verticalDragOffset - model.dismissThreshold) < 10 {
                                hapticLight.impactOccurred()
                            }
                        }
                    }
                    .onEnded { value in
                        // If not dragging vertically, exit early
                        if !model.isDragging {
                            return
                        }
                        
                        // Calculate final velocity for natural feeling
                        let velocity = value.predictedEndLocation.y - value.location.y
                        
                        // Handle vertical dismissal - dismiss on drag beyond threshold or on fast flick
                        let shouldDismiss = verticalDragOffset > model.dismissThreshold || 
                                           (verticalDragOffset > 50 && velocity > 500)
                        
                        if shouldDismiss {
                            // Use a fade-out animation to dismiss
                            hapticMedium.impactOccurred()
                            isDismissing = true
                            
                            // Animate the opacity to fade out
                            withAnimation(.easeOut(duration: 0.2)) {
                                animationProgress = 0
                            }
                            
                            // Dismiss after animation completes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                model.onDismiss()
                            }
                        } else {
                            // Bounce back with spring physics
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0.2)) {
                                verticalDragOffset = 0
                            }
                            
                            // Restore controls with slight delay
                            if !model.showControls {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation {
                                        model.showControls = true
                                        model.autoHideControls()
                                    }
                                }
                            }
                        }
                        
                        model.isDragging = false
                    }
            )
        }
    }
    
    // Native iOS paged controller using UIPageViewController
    @ViewBuilder
    private func carouselView(geometry: GeometryProxy) -> some View {
        PageViewController(
            mediaItems: model.mediaItems,
            currentIndex: $model.currentIndex,
            showControls: $model.showControls,
            onPageChanged: { newIndex in
                // Reset zoom when changing items
                if model.isZoomed {
                    model.resetZoom()
                }
                
                // Generate haptic feedback
                hapticLight.impactOccurred()
                
                // Show controls briefly after changing
                model.showControls = true
                model.autoHideControls()
            }
        )
        .ignoresSafeArea()
        .onAppear {
            // Debug the current model state
            print("PageViewController onAppear - currentIndex: \(model.currentIndex), items count: \(model.mediaItems.count)")
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
    
    // Setup notification observers for UIKit interaction
    private func setupNotificationObservers() {
        // Observer for toggling controls from UIKit views
        NotificationCenter.default.addObserver(
            forName: Notification.Name("MediaViewerToggleControls"),
            object: nil,
            queue: .main
        ) { [self] _ in
            handleToggleControls()
        }
        
        // Observer for zoom state changes
        NotificationCenter.default.addObserver(
            forName: Notification.Name("MediaViewerZoomChanged"),
            object: nil,
            queue: .main
        ) { [self] notification in
            handleZoomChanged(notification)
        }
    }
    
    private func handleToggleControls() {
        withAnimation {
            model.showControls.toggle()
            
            // Auto-hide controls after delay if showing
            if model.showControls {
                model.autoHideControls()
            }
        }
    }
    
    private func handleZoomChanged(_ notification: Notification) {
        if let isZoomed = notification.userInfo?["isZoomed"] as? Bool {
            model.isZoomed = isZoomed
            
            // Hide controls when zoomed
            if isZoomed && model.showControls {
                withAnimation {
                    model.showControls = false
                }
            }
        }
    }
    
    // Hero animation view for smooth entry transition
    @ViewBuilder
    private func heroAnimationView(for item: MediaItem, in geometry: GeometryProxy) -> some View {
        // Only show if we have a valid source frame
        if sourceFrame.width > 0 {
            if item.type == .image {
                AsyncImage(url: item.url) { phase in
                    switch phase {
                    case .empty:
                        Color.gray.opacity(0.3)
                            .frame(width: 60, height: 60) // Initial thumbnail size
                            .cornerRadius(4)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60) // Initial thumbnail size
                            .cornerRadius(4)
                    case .failure:
                        Color.gray.opacity(0.3)
                            .frame(width: 60, height: 60) // Initial thumbnail size
                            .cornerRadius(4)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 60, height: 60) // Initial thumbnail size
                .scaleEffect(animationProgress * ((geometry.size.width / 60) * 0.9)) // Scale up to full screen
                .position(
                    x: sourceFrame.midX + (geometry.size.width/2 - sourceFrame.midX) * animationProgress,
                    y: sourceFrame.midY + (geometry.size.height/2 - sourceFrame.midY) * animationProgress
                )
                .zIndex(10) // Ensure it appears above other elements
            } else {
                // For videos, use a simpler placeholder
                ZStack {
                    Color(UIColor.systemGray5)
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60) // Initial thumbnail size
                .cornerRadius(4)
                .scaleEffect(animationProgress * ((geometry.size.width / 60) * 0.9)) // Scale up to full screen
                .position(
                    x: sourceFrame.midX + (geometry.size.width/2 - sourceFrame.midX) * animationProgress,
                    y: sourceFrame.midY + (geometry.size.height/2 - sourceFrame.midY) * animationProgress
                )
                .zIndex(10) // Ensure it appears above other elements
            }
        }
    }
}

// MARK: - MediaItemViewController

// Single media item view controller (used by PageViewController)
class MediaItemViewController: UIViewController, UIScrollViewDelegate {
    let mediaItem: MediaItem
    var imageView: UIImageView?
    var videoPlayerViewController: AVPlayerViewController?
    var isZoomed = false
    var zoomScale: CGFloat = 1.0
    var loadingIndicator: UIActivityIndicatorView?
    
    // For implementing zoom/pan in UIKit
    var scrollView: UIScrollView?
    var doubleTapGesture: UITapGestureRecognizer?
    var singleTapGesture: UITapGestureRecognizer?
    
    // For preventing redundant image loading
    private var isImageLoading = false
    
    init(mediaItem: MediaItem) {
        self.mediaItem = mediaItem
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        if mediaItem.type == .image {
            setupImageView()
            setupGestures()
        }
        // Video is setup separately via setupVideoWithControls
    }
    
    private func setupImageView() {
        // Create scroll view for zooming
        let scrollView = UIScrollView(frame: view.bounds)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.decelerationRate = .fast
        view.addSubview(scrollView)
        self.scrollView = scrollView
        
        // Create image view inside scroll view
        let imageView = UIImageView(frame: scrollView.bounds)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        self.imageView = imageView
        
        // Add loading indicator
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.center = view.center
        indicator.hidesWhenStopped = true
        indicator.startAnimating()
        view.addSubview(indicator)
        self.loadingIndicator = indicator
        
        // Load image (preferably from cache)
        loadImage()
    }
    
    private func setupGestures() {
        // Double tap to zoom
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delaysTouchesBegan = false
        doubleTapGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(doubleTapGesture)
        self.doubleTapGesture = doubleTapGesture
        
        // Single tap to toggle controls
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        singleTapGesture.delaysTouchesBegan = false
        singleTapGesture.delaysTouchesEnded = false
        singleTapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(singleTapGesture)
        self.singleTapGesture = singleTapGesture
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scrollView = scrollView else { return }
        
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            // Zoom out - animate to 1.0 scale
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            isZoomed = false
        } else {
            // Zoom in to tap location
            let location = gesture.location(in: imageView)
            
            // Calculate zoom rect around tap point
            let zoomFactor = scrollView.maximumZoomScale / scrollView.zoomScale
            let width = scrollView.bounds.width / zoomFactor
            let height = scrollView.bounds.height / zoomFactor
            let x = location.x - width / 2
            let y = location.y - height / 2
            
            let zoomRect = CGRect(x: x, y: y, width: width, height: height)
            scrollView.zoom(to: zoomRect, animated: true)
            isZoomed = true
        }
        
        // Provide haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        // This will be used to toggle controls from SwiftUI parent
        NotificationCenter.default.post(name: Notification.Name("MediaViewerToggleControls"), object: nil)
    }
    
    private func loadImage() {
        guard !isImageLoading else { return }
        isImageLoading = true
        
        // Show loading indicator
        loadingIndicator?.startAnimating()
        
        // Use the improved ImageCache to load the image
        ImageCache.shared.loadImage(url: mediaItem.url) { [weak self] image in
            guard let self = self else { return }
            
            if let image = image {
                self.imageView?.image = image
                self.updateScrollViewContentSize()
            } else {
                self.handleImageLoadError()
            }
            
            self.loadingIndicator?.stopAnimating()
            self.isImageLoading = false
        }
    }
    
    // Cancel any pending image loading when view is removed
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Cancel image loading if in progress
        if isImageLoading {
            ImageCache.shared.cancelLoading(for: mediaItem.url)
            isImageLoading = false
        }
        
        // For video, stop playback
        if mediaItem.type == .video {
            videoPlayerViewController?.player?.pause()
        }
    }
    
    private func handleImageLoadError() {
        // Create error image
        let errorLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        errorLabel.text = "Image could not be loaded"
        errorLabel.textAlignment = .center
        errorLabel.textColor = .white
        errorLabel.numberOfLines = 0
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 200, height: 200), false, 0)
        if let context = UIGraphicsGetCurrentContext() {
            errorLabel.layer.render(in: context)
            let errorImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            imageView?.image = errorImage
            updateScrollViewContentSize()
        }
    }
    
    // Update scroll view content size based on image size
    private func updateScrollViewContentSize() {
        guard let scrollView = scrollView, let imageView = imageView, let image = imageView.image else { return }
        
        let viewSize = scrollView.bounds.size
        let imageSize = image.size
        
        // Calculate aspect-fit dimensions
        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        // Set content size based on scaled image
        scrollView.contentSize = CGSize(width: scaledWidth, height: scaledHeight)
        
        // Center image
        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2
        
        // Set image view frame
        imageView.frame = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update activity indicator position
        loadingIndicator?.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        
        // Update scroll view content layout
        updateScrollViewContentSize()
    }
    
    // MARK: - UIScrollViewDelegate
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        // Before zoom starts, set proper content size
        if scrollView.contentSize.width < scrollView.bounds.width ||
           scrollView.contentSize.height < scrollView.bounds.height {
            scrollView.contentSize = scrollView.bounds.size
        }
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        isZoomed = scrollView.zoomScale > 1.0
        zoomScale = scrollView.zoomScale
        
        // Center the image view as it zooms
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        
        imageView?.frame = CGRect(
            x: offsetX,
            y: offsetY,
            width: scrollView.contentSize.width,
            height: scrollView.contentSize.height
        )
        
        // Notify when zoom state changes
        NotificationCenter.default.post(
            name: Notification.Name("MediaViewerZoomChanged"), 
            object: nil,
            userInfo: ["isZoomed": isZoomed]
        )
    }
    
    // Handle memory warnings
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
        // Clear the image cache if needed
        if !isZoomed && imageView?.image != nil {
            // Keep only the current image in memory
            let currentURL = mediaItem.url
            let currentImage = imageView?.image
            
            ImageCache.shared.clearCache()
            
            if let image = currentImage {
                ImageCache.shared.setImage(image, for: currentURL)
            }
        }
    }
}

// MARK: - PageViewController

struct PageViewController: UIViewControllerRepresentable {
    var mediaItems: [MediaItem]
    @Binding var currentIndex: Int
    @Binding var showControls: Bool
    var onPageChanged: (Int) -> Void
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        print("PageViewController - makeUIViewController, currentIndex: \(currentIndex)")
        
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [UIPageViewController.OptionsKey.interPageSpacing: 20]
        )
        
        pageViewController.delegate = context.coordinator
        pageViewController.dataSource = context.coordinator
        
        // Configure page view controller appearance
        pageViewController.view.backgroundColor = .black
        
        // Enable better scrolling physics
        for subview in pageViewController.view.subviews {
            if let scrollView = subview as? UIScrollView {
                scrollView.decelerationRate = .fast
                scrollView.clipsToBounds = false
                
                // Improve scroll view behavior to prevent accidental dismissal
                scrollView.bounces = true
                scrollView.alwaysBounceHorizontal = true
                scrollView.alwaysBounceVertical = false
                
                // Set content inset to reduce chance of dismissal gesture conflict
                scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
                
                // Make sure we can still detect taps for controls
                scrollView.delaysContentTouches = false
                scrollView.canCancelContentTouches = true
                
                break
            }
        }
        
        // Set initial view controller
        if !mediaItems.isEmpty {
            // Make sure index is within bounds
            let safeIndex = min(max(0, currentIndex), mediaItems.count - 1)
            let initialVC = MediaItemViewController(mediaItem: mediaItems[safeIndex])
            
            // Configure for video if needed
            if mediaItems[safeIndex].type == .video {
                initialVC.setupVideoWithControls(showControlsBinding: $showControls)
            }
            
            // Store in cache
            let cacheKey = NSString(string: mediaItems[safeIndex].id.uuidString)
            context.coordinator.viewControllerCache.setObject(initialVC, forKey: cacheKey)
            
            pageViewController.setViewControllers(
                [initialVC],
                direction: .forward,
                animated: false
            )
        }
        
        return pageViewController
    }
    
    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        // Handle updates from SwiftUI
        if let currentVC = pageViewController.viewControllers?.first as? MediaItemViewController,
           let currentIndex = mediaItems.firstIndex(where: { $0.id == currentVC.mediaItem.id }),
           currentIndex != self.currentIndex {
            
            // Try to get view controller from cache, or create a new one
            let cacheKey = NSString(string: mediaItems[self.currentIndex].id.uuidString)
            let newVC: MediaItemViewController
            
            if let cachedVC = context.coordinator.viewControllerCache.object(forKey: cacheKey) {
                newVC = cachedVC
            } else {
                // Create and cache a new view controller
                newVC = MediaItemViewController(mediaItem: mediaItems[self.currentIndex])
                
                // Configure for video if needed
                if mediaItems[self.currentIndex].type == .video {
                    newVC.setupVideoWithControls(showControlsBinding: $showControls)
                }
                
                // Add to cache
                context.coordinator.viewControllerCache.setObject(newVC, forKey: cacheKey)
            }
            
            let direction: UIPageViewController.NavigationDirection = 
                currentIndex < self.currentIndex ? .forward : .reverse
            
            // Use a smooth animation for programmatic navigation
            UIView.animate(withDuration: 0.2) {
                pageViewController.setViewControllers(
                    [newVC],
                    direction: direction,
                    animated: true
                )
            }
            
            // Clean up cached controllers that aren't needed immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                context.coordinator.clearCacheExcept(currentIndex: self.currentIndex)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
        var parent: PageViewController
        private var isTransitioning = false
        
        // Cache controllers to improve performance
        var viewControllerCache = NSCache<NSString, MediaItemViewController>()
        
        init(_ pageViewController: PageViewController) {
            self.parent = pageViewController
            super.init()
            
            // Configure cache limits
            viewControllerCache.countLimit = 5 // Max 5 view controllers in memory
        }
        
        // MARK: - UIPageViewControllerDataSource
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let viewController = viewController as? MediaItemViewController,
                  let index = parent.mediaItems.firstIndex(where: { $0.id == viewController.mediaItem.id }),
                  index > 0 else { return nil }
            
            let previousIndex = index - 1
            
            // Try to get from cache first
            let cacheKey = NSString(string: parent.mediaItems[previousIndex].id.uuidString)
            if let cachedVC = viewControllerCache.object(forKey: cacheKey) {
                return cachedVC
            }
            
            // Create new view controller
            let previousVC = MediaItemViewController(mediaItem: parent.mediaItems[previousIndex])
            
            // Configure for video if needed
            if parent.mediaItems[previousIndex].type == .video {
                previousVC.setupVideoWithControls(showControlsBinding: parent.$showControls)
            }
            
            // Cache the view controller
            viewControllerCache.setObject(previousVC, forKey: cacheKey)
            
            return previousVC
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let viewController = viewController as? MediaItemViewController,
                  let index = parent.mediaItems.firstIndex(where: { $0.id == viewController.mediaItem.id }),
                  index < parent.mediaItems.count - 1 else { return nil }
            
            let nextIndex = index + 1
            
            // Try to get from cache first
            let cacheKey = NSString(string: parent.mediaItems[nextIndex].id.uuidString)
            if let cachedVC = viewControllerCache.object(forKey: cacheKey) {
                return cachedVC
            }
            
            // Create new view controller
            let nextVC = MediaItemViewController(mediaItem: parent.mediaItems[nextIndex])
            
            // Configure for video if needed
            if parent.mediaItems[nextIndex].type == .video {
                nextVC.setupVideoWithControls(showControlsBinding: parent.$showControls)
            }
            
            // Cache the view controller
            viewControllerCache.setObject(nextVC, forKey: cacheKey)
            
            return nextVC
        }
        
        // MARK: - UIPageViewControllerDelegate
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            // Guard against incomplete or invalid transitions
            guard finished else { return }
            
            if completed, 
               let currentVC = pageViewController.viewControllers?.first as? MediaItemViewController,
               let index = parent.mediaItems.firstIndex(where: { $0.id == currentVC.mediaItem.id }) {
                
                // Update the current index in SwiftUI
                DispatchQueue.main.async {
                    // Only update if the index has actually changed
                    if self.parent.currentIndex != index {
                        self.parent.currentIndex = index
                        self.parent.onPageChanged(index)
                        
                        // Preload adjacent images for smoother browsing
                        self.preloadAdjacentImages(currentIndex: index)
                    }
                }
            }
            
            isTransitioning = false
        }
        
        // Preload adjacent images to improve browsing experience
        private func preloadAdjacentImages(currentIndex: Int) {
            var urlsToPreload: [URL] = []
            
            // Add next 2 images
            if currentIndex + 1 < parent.mediaItems.count {
                urlsToPreload.append(parent.mediaItems[currentIndex + 1].url)
            }
            
            if currentIndex + 2 < parent.mediaItems.count {
                urlsToPreload.append(parent.mediaItems[currentIndex + 2].url)
            }
            
            // Add previous image
            if currentIndex - 1 >= 0 {
                urlsToPreload.append(parent.mediaItems[currentIndex - 1].url)
            }
            
            // Filter to only include image URLs
            let imageURLs = urlsToPreload.filter { url in
                let index = parent.mediaItems.firstIndex { $0.url == url }
                if let index = index, parent.mediaItems[index].type == .image {
                    return true
                }
                return false
            }
            
            // Preload in background
            DispatchQueue.global(qos: .utility).async {
                ImageCache.shared.preloadImages(imageURLs)
            }
        }
        
        // Prepare for transition between pages
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
            
            // Ensure any current video player pauses during transition
            if let currentVC = pageViewController.viewControllers?.first as? MediaItemViewController, 
               currentVC.mediaItem.type == .video,
               let playerVC = currentVC.videoPlayerViewController {
                playerVC.player?.pause()
            }
            
            // Prepare upcoming controllers
            for pendingVC in pendingViewControllers {
                if let mediaVC = pendingVC as? MediaItemViewController {
                    // Ensure proper setup based on media type
                    if mediaVC.mediaItem.type == .image {
                        // Preload image if not already loaded
                        if mediaVC.imageView?.image == nil {
                            mediaVC.viewDidLoad() // Force load content
                        }
                    }
                }
            }
        }
        
        // Custom implementation for scroll interactivity
        func pageViewController(_ pageViewController: UIPageViewController, 
                                spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            return .min // Single page display
        }
        
        // Memory management
        func clearCacheExcept(currentIndex: Int) {
            let keysToKeep: [String] = [
                parent.mediaItems[currentIndex].id.uuidString, // Current
                currentIndex > 0 ? parent.mediaItems[currentIndex - 1].id.uuidString : "", // Previous
                currentIndex < parent.mediaItems.count - 1 ? parent.mediaItems[currentIndex + 1].id.uuidString : "" // Next
            ]
            
            // Create array of all media IDs
            let allMediaKeys = parent.mediaItems.map { $0.id.uuidString }
            
            // Remove all except the keys we want to keep
            for key in allMediaKeys {
                let nsKey = key as NSString
                if !keysToKeep.contains(key) {
                    viewControllerCache.removeObject(forKey: nsKey)
                }
            }
        }
    }
}

// MARK: - Video Controls Extension for MediaItemViewController

extension MediaItemViewController {
    // Setup video player with controls
    func setupVideoWithControls(showControlsBinding: Binding<Bool>) {
        let player = AVPlayer(url: mediaItem.url)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        playerViewController.videoGravity = .resizeAspect
        
        // Toggle controls based on binding
        playerViewController.showsPlaybackControls = showControlsBinding.wrappedValue
        
        // Listen for control changes
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            playerViewController.showsPlaybackControls = showControlsBinding.wrappedValue
        }
        
        // Add single tap gesture to toggle controls
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        playerViewController.view.addGestureRecognizer(singleTapGesture)
        
        // Add as child view controller
        addChild(playerViewController)
        playerViewController.view.frame = view.bounds
        view.addSubview(playerViewController.view)
        playerViewController.didMove(toParent: self)
        
        self.videoPlayerViewController = playerViewController
        
        // Auto-play video
        player.play()
        
        // Generate thumbnail for initial display
        generateThumbnail()
        
        // Auto-toggle controls after delay
        autoHideControls(showControlsBinding: showControlsBinding)
        
        // Configure video player observers
        setupVideoObservers(player)
    }
    
    // Generate thumbnail for video preview
    private func generateThumbnail() {
        let asset = AVURLAsset(url: mediaItem.url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Use async thumbnail generation to avoid deprecation warning
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        imageGenerator.generateCGImageAsynchronously(for: time) { [weak self] cgImage, actualTime, error in
            guard let self = self, let cgImage = cgImage else { return }
            
            let thumbnailImage = UIImage(cgImage: cgImage)
            
            DispatchQueue.main.async {
                // Create thumbnail image view
                let thumbnailImageView = UIImageView(image: thumbnailImage)
                thumbnailImageView.contentMode = .scaleAspectFit
                thumbnailImageView.frame = self.view.bounds
                thumbnailImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                
                // Add to view temporarily
                self.view.addSubview(thumbnailImageView)
                
                // Remove after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    UIView.animate(withDuration: 0.3) {
                        thumbnailImageView.alpha = 0
                    } completion: { _ in
                        thumbnailImageView.removeFromSuperview()
                    }
                }
            }
        }
    }
    
    // Auto-hide controls after delay
    private func autoHideControls(showControlsBinding: Binding<Bool>) {
        guard showControlsBinding.wrappedValue else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if showControlsBinding.wrappedValue {
                withAnimation {
                    showControlsBinding.wrappedValue = false
                    self.videoPlayerViewController?.showsPlaybackControls = false
                }
            }
        }
    }
    
    // Setup observers for video player
    private func setupVideoObservers(_ player: AVPlayer) {
        // Listen for play/pause notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        // Add periodic time observer to update UI for video progress, if needed
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            // Video is playing - could update progress indicators here if needed
        }
    }
    
    // Respond to video ending
    @objc private func playerItemDidPlayToEndTime(notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem,
           let currentPlayer = videoPlayerViewController?.player,
           playerItem == currentPlayer.currentItem {
            // Automatically loop video
            currentPlayer.seek(to: .zero)
            currentPlayer.play()
        }
    }
}

// MARK: - Image Cache

// Global image cache to prevent reloading and flickering
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSURL, UIImage>()
    private var loadingOperations: [URL: URLSessionDataTask] = [:]
    
    init() {
        // Set reasonable limits to prevent memory issues
        cache.countLimit = 50 // Max number of images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB max
        
        // Register for memory warning notifications
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(handleMemoryWarning), 
                                              name: UIApplication.didReceiveMemoryWarningNotification, 
                                              object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func image(for url: URL) -> UIImage? {
        return cache.object(forKey: url as NSURL)
    }
    
    func setImage(_ image: UIImage, for url: URL) {
        // Calculate approximate memory cost (width * height * 4 bytes for RGBA)
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
    
    func cancelLoading(for url: URL) {
        loadingOperations[url]?.cancel()
        loadingOperations.removeValue(forKey: url)
    }
    
    // Preload images into the cache
    func preloadImages(_ urls: [URL]) {
        for url in urls {
            // Skip if already in cache
            if cache.object(forKey: url as NSURL) != nil {
                continue
            }
            
            // Skip remote URLs for preloading to avoid unnecessary network traffic
            guard url.isFileURL else { continue }
            
            // Load on background thread
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                
                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.setImage(image, for: url)
                    }
                }
            }
        }
    }
    
    // Handle memory pressure
    @objc private func handleMemoryWarning() {
        // On memory warning, we'll keep only recently used images
        cache.removeAllObjects()
    }
    
    // Load image asynchronously with completion
    func loadImage(url: URL, completion: @escaping (UIImage?) -> Void) {
        // Check cache first
        if let cachedImage = image(for: url) {
            completion(cachedImage)
            return
        }
        
        // Cancel any existing loading operation for this URL
        cancelLoading(for: url)
        
        // Handle local files
        if url.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    self.setImage(image, for: url)
                    DispatchQueue.main.async {
                        completion(image)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
            return
        }
        
        // Load from network
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Remove this operation
            self.loadingOperations.removeValue(forKey: url)
            
            if let data = data, let image = UIImage(data: data) {
                self.setImage(image, for: url)
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        // Store and start the task
        loadingOperations[url] = task
        task.resume()
    }
}

// MARK: - VideoView

struct VideoView: View {
    let item: MediaItem
    @Binding var showControls: Bool
    
    var body: some View {
        // Using AVPlayerViewController through UIViewControllerRepresentable
        AVPlayerControllerRepresentable(videoURL: item.url, showControls: $showControls)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                withAnimation {
                    showControls.toggle()
                }
            }
    }
}

// AVPlayerViewController wrapper
struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let videoURL: URL
    @Binding var showControls: Bool
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: videoURL)
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = showControls
        
        // Auto-play
        player.play()
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.showsPlaybackControls = showControls
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