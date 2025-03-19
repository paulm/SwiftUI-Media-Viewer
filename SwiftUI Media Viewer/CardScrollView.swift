//
//  CardScrollView.swift
//  SwiftUI Media Viewer
//
//  Created by Paul Mayne on 3/19/25.
//

import SwiftUI

struct CardScrollView: View {
    var onDismiss: () -> Void
    
    // For tracking which card is centered
    @State private var lastCenteredIndex: Int = -1
    
    // For haptic feedback
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // For calculating centered card
    @State private var viewWidth: CGFloat = 0
    
    // For expanded card state
    @State private var expandedCardIndex: Int? = nil
    @State private var isExpanded = false
    
    // For natural card scrolling
    @State private var targetCardIndex: Int = 0
    @State private var displayCardIndex: Int = 0
    @State private var animationActive = false
    
    // For slider control
    @State private var sliderValue: Double = 0
    @State private var initialSliderTouch: Double? = nil // Store initial touch position
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    @State private var isUserDraggingCards = false // Track when user is directly dragging cards
    
    // For slider physics
    @State private var sliderDragVelocity: Double = 0
    @State private var lastDragLocation: CGPoint? = nil
    @State private var lastDragTime: Date? = nil
    @State private var isDraggingSlider = false
    @State private var isAnimatingSlider = false
    
    // Total number of cards
    private let totalCards = 100
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background
                Color.white.ignoresSafeArea()
                
                // Dim background when card is expanded
                if isExpanded {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .zIndex(99)
                        .onTapGesture {
                            // Collapse the expanded card when tapping background
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                expandedCardIndex = nil
                                isExpanded = false
                            }
                        }
                }
                
                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding()
                }
                .zIndex(101) // Keep dismiss button on top
                
                // Cards with ScrollViewReader for programmatic scrolling
                ScrollViewReader { scrollViewReader in
                    VStack(spacing: 20) {
                        ZStack {
                            // Regular card scrollview
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(0..<totalCards, id: \.self) { index in
                                        cardView(for: index)
                                            .frame(width: 100, height: 125) // 1/2 the original size
                                            .id(index) // For scrollViewReader
                                            .background(GeometryReader { geo in
                                                Color.clear.onAppear {
                                                    viewWidth = geometry.size.width
                                                }
                                                .onChange(of: geo.frame(in: .named("scrollView"))) { frame in
                                                    if !isExpanded {
                                                        checkIfCardIsCentered(frame: frame, index: index)
                                                    }
                                                }
                                            })
                                    }
                                }
                                .padding(.horizontal, (geometry.size.width - 100) / 2) // Adjusted for new width
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 5)
                                        .onChanged { _ in
                                            // User is directly interacting with cards
                                            isUserDraggingCards = true
                                            
                                            // Ensure slider animation doesn't interfere
                                            animationActive = false
                                        }
                                        .onEnded { _ in
                                            // Reset after a delay
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                isUserDraggingCards = false
                                            }
                                        }
                                )
                            }
                            .coordinateSpace(name: "scrollView")
                            .frame(height: geometry.size.height * 0.7) // Leave room for slider
                            .allowsHitTesting(!isExpanded) // Disable scrolling when a card is expanded
                            
                            // Expanded card overlay - shown above everything when a card is expanded
                            if isExpanded, let expandedIndex = expandedCardIndex {
                                cardView(for: expandedIndex)
                                    .frame(width: 100, height: 125)
                                    .scaleEffect(3.5)
                                    .zIndex(500) // Ensure it's above everything
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            expandedCardIndex = nil
                                            isExpanded = false
                                        }
                                    }
                            }
                        }
                        
                        // Slider control with custom styling
                        VStack(spacing: 4) {
                            ZStack(alignment: .leading) {
                                // Base slider
                                Slider(value: $sliderValue, in: 0...Double(totalCards - 1))
                                    .padding(.horizontal, 20)
                                    .accentColor(.blue)
                                    .onChange(of: sliderValue) { value in
                                        // Update target index when slider changes
                                        targetCardIndex = Int(value.rounded())
                                        
                                        // Only animate cards when slider is being directly manipulated
                                        // This prevents interfering with normal scroll behavior
                                        if !animationActive && (isDraggingSlider || isAnimatingSlider) {
                                            animationActive = true
                                            
                                            // Begin natural animation timer
                                            let startTime = Date()
                                            let animationDuration = 0.35 // seconds
                                            
                                            // Create timer for smooth scrolling
                                            let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
                                                let now = Date()
                                                let elapsed = now.timeIntervalSince(startTime)
                                                let progress = min(1.0, elapsed / animationDuration)
                                                
                                                // Apply easing curve (ease-out cubic)
                                                let easedProgress = 1.0 - pow(1.0 - progress, 3)
                                                
                                                // Update scroll position with easing
                                                withAnimation(.linear(duration: 0.01)) {
                                                    scrollViewReader.scrollTo(targetCardIndex, anchor: .center)
                                                }
                                                
                                                // End timer when animation completes
                                                if progress >= 1.0 {
                                                    timer.invalidate()
                                                    animationActive = false
                                                }
                                            }
                                            
                                            RunLoop.current.add(timer, forMode: .common)
                                        }
                                    }
                                    .disabled(isExpanded || isAnimatingSlider) // Disable slider during animations
                                
                                // Custom drag gesture overlay for physics
                                Color.clear
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, 20)
                                    .frame(height: 44) // Make touch target larger
                                    .gesture(
                                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                            .onChanged { gesture in
                                                // Store initial touch position to prevent jumps
                                                if !isDraggingSlider {
                                                    initialSliderTouch = sliderValue
                                                }
                                                
                                                isDraggingSlider = true
                                                isAnimatingSlider = false
                                                
                                                // Calculate drag distance from initial position
                                                let dragAmount = gesture.location.x
                                                let totalWidth = geometry.size.width - 40 // Adjust for padding
                                                
                                                if let initialValue = initialSliderTouch {
                                                    // Calculate the delta movement
                                                    let draggableRange = Double(totalCards - 1)
                                                    let stepSize = draggableRange / Double(totalWidth)
                                                    let dragDelta = Double(dragAmount - gesture.startLocation.x) * stepSize
                                                    
                                                    // Apply the delta to the initial value
                                                    let newValue = initialValue + dragDelta
                                                    sliderValue = max(0, min(draggableRange, newValue))
                                                }
                                                
                                                // Calculate velocity for inertia
                                                let now = Date()
                                                if let lastLocation = lastDragLocation, let lastTime = lastDragTime {
                                                    let dx = gesture.location.x - lastLocation.x
                                                    let dt = now.timeIntervalSince(lastTime)
                                                    if dt > 0 {
                                                        sliderDragVelocity = Double(dx) / dt
                                                    }
                                                }
                                                
                                                lastDragLocation = gesture.location
                                                lastDragTime = now
                                            }
                                            .onEnded { gesture in
                                                isDraggingSlider = false
                                                initialSliderTouch = nil
                                                
                                                // Apply inertia if velocity is significant
                                                if abs(sliderDragVelocity) > 100 {
                                                    isAnimatingSlider = true
                                                    
                                                    // Start a timer to animate the sliding effect
                                                    let baseVelocity = sliderDragVelocity / 1000 // Scale down
                                                    var lastUpdateTime = Date()
                                                    
                                                    // Define physics constants
                                                    let friction = 0.94 // Higher values = less friction (0.94 feels more iOS-like)
                                                    let minVelocity = 0.1
                                                    
                                                    // Apply initial velocity impact for better feel
                                                    sliderDragVelocity *= 1.2 // Slightly amplify initial velocity for better effect
                                                    
                                                    // Create timer for physics animation
                                                    let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
                                                        let now = Date()
                                                        let dt = now.timeIntervalSince(lastUpdateTime)
                                                        lastUpdateTime = now
                                                        
                                                        // Apply friction
                                                        sliderDragVelocity *= pow(friction, dt * 60)
                                                        
                                                        // Stop when velocity is very low
                                                        if abs(sliderDragVelocity) < minVelocity {
                                                            timer.invalidate()
                                                            isAnimatingSlider = false
                                                            
                                                            // When animation ends, apply a final settling animation
                                                            let targetIndex = Int(sliderValue.rounded())
                                                            
                                                            // Start natural settling animation
                                                            targetCardIndex = targetIndex
                                                            animationActive = true
                                                            
                                                            // Update slider to match final position
                                                            sliderValue = Double(targetIndex)
                                                            
                                                            // Use a timer for smooth animation with custom easing
                                                            let startTime = Date()
                                                            let animationDuration = 0.5 // seconds
                                                            
                                                            let settlingTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
                                                                let now = Date()
                                                                let elapsed = now.timeIntervalSince(startTime)
                                                                let progress = min(1.0, elapsed / animationDuration)
                                                                
                                                                // Apply spring-like easing curve
                                                                // This simulates a spring-like motion
                                                                let t = progress
                                                                let easedProgress = 1 - cos(t * .pi / 2)
                                                                
                                                                // Update scroll position with easing
                                                                withAnimation(.linear(duration: 0.01)) {
                                                                    scrollViewReader.scrollTo(targetIndex, anchor: .center)
                                                                }
                                                                
                                                                // End timer when animation completes
                                                                if progress >= 1.0 {
                                                                    timer.invalidate()
                                                                    animationActive = false
                                                                }
                                                            }
                                                            
                                                            RunLoop.current.add(settlingTimer, forMode: .common)
                                                            return
                                                        }
                                                        
                                                        // Update position based on velocity
                                                        let totalWidth = Double(geometry.size.width - 40)
                                                        let dragAmount = sliderDragVelocity * dt
                                                        let dragNormalized = dragAmount / totalWidth
                                                        
                                                        // Calculate new position
                                                        var newValue = sliderValue + (dragNormalized * Double(totalCards - 1))
                                                        newValue = max(0, min(Double(totalCards - 1), newValue))
                                                        
                                                        // Only update if in bounds
                                                        if newValue >= 0 && newValue <= Double(totalCards - 1) {
                                                            sliderValue = newValue
                                                        } else {
                                                            // Hit boundary, stop animating
                                                            timer.invalidate()
                                                            isAnimatingSlider = false
                                                        }
                                                    }
                                                    
                                                    // Ensure timer stops if view disappears
                                                    RunLoop.current.add(timer, forMode: .common)
                                                }
                                                
                                                // Clear state
                                                lastDragLocation = nil
                                                lastDragTime = nil
                                            }
                                    )
                            }
                            .disabled(isExpanded) // Disable slider when a card is expanded
                            
                            // Card position indicators 
                            HStack {
                                Text("1")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "%d", Int(sliderValue) + 1))
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                    .padding(4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                    .animation(.none, value: sliderValue)
                                Spacer()
                                Text(String(totalCards))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .onAppear {
                        scrollViewProxy = scrollViewReader
                        impactFeedback.prepare()
                    }
                }
                .frame(height: geometry.size.height) // Fill the height
                .frame(maxHeight: .infinity)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Center in the view
                .allowsHitTesting(!isExpanded || expandedCardIndex == nil) // Prevent scrolling when a card is expanded
            }
        }
    }
    
    private func cardView(for index: Int) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(cardColor(for: index))
            .shadow(radius: 3)
            .overlay(
                Text("Card \(index + 1)")
                    .foregroundColor(.white)
                    .font(.headline)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if expandedCardIndex == index {
                        // Collapse the card if it's already expanded
                        expandedCardIndex = nil
                        isExpanded = false
                    } else {
                        // Expand this card
                        expandedCardIndex = index
                        isExpanded = true
                    }
                }
            }
            // These are now handled in the ZStack overlay for expanded cards
            .zIndex(1)
            .disabled(isExpanded && expandedCardIndex != index) // Disable other cards when one is expanded
    }
    
    private func cardColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .pink]
        return colors[index % colors.count]
    }
    
    private func checkIfCardIsCentered(frame: CGRect, index: Int) {
        // Calculate center position of the view
        let viewCenter = viewWidth / 2
        
        // Calculate center of the card
        let cardCenter = frame.origin.x + (frame.width / 2)
        
        // Check if card is near center (within 20 points)
        let isCentered = abs(viewCenter - cardCenter) < 20
        
        // If card is centered and it's a different card than before, trigger haptic and update slider
        if isCentered && lastCenteredIndex != index {
            lastCenteredIndex = index
            impactFeedback.impactOccurred()
            
            // Always update the slider position when scrolling the cards,
            // but only if the slider is not actively controlling the cards
            if !isDraggingSlider && !isAnimatingSlider {
                DispatchQueue.main.async {
                    // Update slider position without triggering animations
                    sliderValue = Double(index)
                }
            }
            
            // Update display index for current position
            displayCardIndex = index
        }
    }
}

#Preview {
    CardScrollView(onDismiss: {})
}