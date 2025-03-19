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
    @State private var currentCardIndex: Int = 0
    
    // For haptic feedback
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // For calculating centered card
    @State private var viewWidth: CGFloat = 0
    
    // For expanded card state
    @State private var expandedCardIndex: Int? = nil
    @State private var isExpanded = false
    
    // For scroll values
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    
    // Simple enum to track active control
    enum ControlType {
        case cards, physicsSlider, standardSlider
    }
    @State private var activeControl: ControlType = .cards
    
    // Slider values
    @State private var physicsSliderValue: Double = 0
    @State private var standardSliderValue: Double = 0
    
    // Physics properties
    @State private var velocity: Double = 0
    @State private var isDraggingPhysicsSlider = false
    @State private var isAnimatingPhysicsSlider = false
    @State private var lastDragLocation: CGPoint? = nil
    @State private var lastDragTime: Date? = nil
    
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
                
                // Main content with ScrollViewReader for programmatic scrolling
                ScrollViewReader { scrollViewReader in
                    VStack(spacing: 20) {
                        ZStack {
                            // Background
                            Color.white
                                .edgesIgnoringSafeArea(.all)
                            
                            // Dimmed background when expanded
                            if isExpanded {
                                Color.black
                                    .opacity(0.6)
                                    .ignoresSafeArea()
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            expandedCardIndex = nil
                                            isExpanded = false
                                        }
                                    }
                                    .zIndex(90)
                            }
                            
                            // Card scrollview
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(0..<totalCards, id: \.self) { index in
                                        cardView(for: index, isActive: index == currentCardIndex && !isExpanded)
                                            .frame(width: 100, height: 125)
                                            .id(index) // For scrollViewReader
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear
                                                        .onAppear {
                                                            viewWidth = geometry.size.width
                                                        }
                                                        .onChange(of: geo.frame(in: .named("scrollView"))) { _, frame in
                                                            if !isExpanded {
                                                                checkIfCardIsCentered(frame: frame, index: index)
                                                            }
                                                        }
                                                }
                                            )
                                    }
                                }
                                .padding(.horizontal, (geometry.size.width - 100) / 2)
                                .opacity(isExpanded ? 0.4 : (activeControl == .cards ? 1.0 : 0.7))
                                .saturation(activeControl == .cards ? 1.0 : 0.6)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 5)
                                    .onChanged { _ in
                                        activeControl = .cards
                                    }
                            )
                            .coordinateSpace(name: "scrollView")
                            .frame(height: geometry.size.height * 0.7)
                            .allowsHitTesting(!isExpanded)
                            .zIndex(1)
                            
                            // Expanded card overlay
                            if isExpanded, let expandedIndex = expandedCardIndex {
                                // Get position of the original card
                                GeometryReader { geo in
                                    // The expanded card
                                    cardView(for: expandedIndex, isActive: false)
                                        .frame(width: 300, height: 375) // 3x the original size
                                        .shadow(radius: 10)
                                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                expandedCardIndex = nil
                                                isExpanded = false
                                            }
                                        }
                                }
                                .zIndex(100)
                            }
                        }
                        
                        // Control section
                        VStack(spacing: 24) {
                            // Physics-based slider
                            sliderSection(
                                title: "Physics Slider",
                                value: $physicsSliderValue,
                                color: .blue,
                                isActive: activeControl == .physicsSlider,
                                onActivate: { activeControl = .physicsSlider },
                                onChange: { scrollToCard(index: Int($0.rounded()), proxy: scrollViewReader, useAnimation: true) },
                                geometry: geometry,
                                isDisabled: isExpanded
                            )
                            
                            // Standard slider 
                            sliderSection(
                                title: "Standard Slider",
                                value: $standardSliderValue,
                                color: .green,
                                isActive: activeControl == .standardSlider,
                                onActivate: { activeControl = .standardSlider },
                                onChange: { scrollToCard(index: Int($0.rounded()), proxy: scrollViewReader, useAnimation: false) },
                                geometry: geometry,
                                usesPhysics: false,
                                isDisabled: isExpanded
                            )
                        }
                        .padding(.horizontal)
                    }
                    .onAppear {
                        scrollViewProxy = scrollViewReader
                        impactFeedback.prepare()
                    }
                    .onChange(of: currentCardIndex) { _, newIndex in
                        // When the card changes, update the inactive sliders
                        if activeControl != .physicsSlider {
                            physicsSliderValue = Double(newIndex)
                        }
                        if activeControl != .standardSlider {
                            standardSliderValue = Double(newIndex)
                        }
                    }
                }
                .frame(height: geometry.size.height)
                .frame(maxHeight: .infinity)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
    
    // Reusable slider section
    func sliderSection(
        title: String,
        value: Binding<Double>,
        color: Color,
        isActive: Bool,
        onActivate: @escaping () -> Void,
        onChange: @escaping (Double) -> Void,
        geometry: GeometryProxy,
        usesPhysics: Bool = true,
        isDisabled: Bool = false
    ) -> some View {
        VStack(spacing: 4) {
            // Title
            Text(title)
                .font(.caption)
                .foregroundColor(isActive ? color : .gray.opacity(0.5))
                .fontWeight(isActive ? .bold : .regular)
            
            // Slider
            VStack {
                // When inactive, show a tap area to activate
                if !isActive {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(height: 44)
                        .onTapGesture {
                            onActivate()
                            value.wrappedValue = Double(currentCardIndex)
                        }
                }
                
                // The actual slider
                if usesPhysics {
                    // Physics-based slider
                    ZStack {
                        Slider(value: value, in: 0...Double(totalCards - 1))
                            .accentColor(color)
                            .opacity(isActive ? 1.0 : 0.5)
                            .onChange(of: value.wrappedValue) { _, newValue in
                                if isActive {
                                    onChange(newValue)
                                }
                            }
                        
                        // For physics slider, we need a custom drag gesture
                        if isActive {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .frame(height: 44)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { gesture in
                                            // Initialize on first touch
                                            if !isDraggingPhysicsSlider {
                                                value.wrappedValue = Double(currentCardIndex)
                                            }
                                            
                                            isDraggingPhysicsSlider = true
                                            isAnimatingPhysicsSlider = false
                                            
                                            // Calculate velocity
                                            let now = Date()
                                            let dragAmount = gesture.location.x
                                            let totalWidth = geometry.size.width - 40
                                            
                                            // If we're tracking the drag
                                            if let lastTime = lastDragTime {
                                                let dt = now.timeIntervalSince(lastTime)
                                                if dt > 0 {
                                                    let dx = dragAmount - lastDragLocation!.x
                                                    velocity = Double(dx) / dt
                                                }
                                            }
                                            
                                            // Store current position
                                            lastDragLocation = gesture.location
                                            lastDragTime = now
                                            
                                            // Update slider value based on drag
                                            let draggableRange = Double(totalCards - 1)
                                            let stepSize = draggableRange / Double(totalWidth)
                                            
                                            // Calculate change relative to drag start
                                            let deltaX = gesture.location.x - gesture.startLocation.x
                                            let newValue = Double(currentCardIndex) + (Double(deltaX) * stepSize)
                                            
                                            // Apply with bounds check
                                            value.wrappedValue = max(0, min(draggableRange, newValue))
                                        }
                                        .onEnded { _ in
                                            // Handle physics-based inertia
                                            isDraggingPhysicsSlider = false
                                            
                                            // Apply inertia if velocity is significant
                                            if abs(velocity) > 100 {
                                                isAnimatingPhysicsSlider = true
                                                
                                                // Physics animation
                                                var lastUpdateTime = Date()
                                                let friction = 0.94
                                                let minVelocity = 0.1
                                                
                                                // Create timer for physics simulation
                                                let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
                                                    let now = Date()
                                                    let dt = now.timeIntervalSince(lastUpdateTime)
                                                    lastUpdateTime = now
                                                    
                                                    // Apply friction
                                                    velocity *= pow(friction, dt * 60)
                                                    
                                                    // Stop when very slow
                                                    if abs(velocity) < minVelocity {
                                                        timer.invalidate()
                                                        isAnimatingPhysicsSlider = false
                                                        
                                                        // Snap to nearest card
                                                        let targetIndex = Int(value.wrappedValue.rounded())
                                                        value.wrappedValue = Double(targetIndex)
                                                        return
                                                    }
                                                    
                                                    // Apply velocity to position
                                                    let totalWidth = Double(geometry.size.width - 40)
                                                    let deltaX = velocity * dt
                                                    let normalizedDelta = deltaX / totalWidth
                                                    let valueChange = normalizedDelta * Double(totalCards - 1)
                                                    
                                                    // Update position with bounds check
                                                    let newValue = value.wrappedValue + valueChange
                                                    if newValue >= 0 && newValue <= Double(totalCards - 1) {
                                                        value.wrappedValue = newValue
                                                    } else {
                                                        // Hit boundary, stop animation
                                                        timer.invalidate()
                                                        isAnimatingPhysicsSlider = false
                                                    }
                                                }
                                                
                                                // Ensure timer stops if view disappears
                                                RunLoop.current.add(timer, forMode: .common)
                                            }
                                            
                                            // Reset tracking
                                            lastDragLocation = nil
                                            lastDragTime = nil
                                        }
                                )
                        }
                    }
                } else {
                    // Standard slider - use built-in drag handling
                    Slider(value: value, in: 0...Double(totalCards - 1))
                        .accentColor(color)
                        .opacity(isActive ? 1.0 : 0.5)
                        .onChange(of: value.wrappedValue) { _, newValue in
                            if isActive {
                                onChange(newValue)
                            }
                        }
                        .onTapGesture {
                            if !isActive {
                                onActivate()
                                value.wrappedValue = Double(currentCardIndex)
                            }
                        }
                        // Standard slider doesn't use the physics system
                        .disabled(!isActive)
                }
                
                // Position indicators
                HStack {
                    Text("1")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%d", Int(value.wrappedValue) + 1))
                        .font(.caption2)
                        .foregroundColor(color)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color.opacity(0.1))
                        )
                        .animation(.none, value: value.wrappedValue)
                    Spacer()
                    Text(String(totalCards))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 4)
            }
        }
        .disabled(isDisabled)
    }
    
    // Scroll to a specific card - with animation for physics slider, instant for standard slider
    func scrollToCard(index: Int, proxy: ScrollViewProxy, useAnimation: Bool = false) {
        if useAnimation {
            withAnimation(.linear(duration: 0.01)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            // No animation - instant jump
            proxy.scrollTo(index, anchor: .center)
        }
    }
    
    // Card view helper
    func cardView(for index: Int, isActive: Bool = false) -> some View {
        let color = isActive ? Color.black : cardColor(for: index)
        
        return RoundedRectangle(cornerRadius: 12)
            .fill(color)
            .shadow(radius: isActive ? 4 : 3)
            .overlay(
                Text("Card \(index + 1)")
                    .foregroundColor(.white)
                    .font(.headline)
            )
            .overlay(
                // Simple indicator for active card
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white, lineWidth: isActive ? 2 : 0)
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
            .disabled(isExpanded && expandedCardIndex != index)
    }
    
    // Helper for card colors
    func cardColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .pink]
        return colors[index % colors.count]
    }
    
    // Helper to detect centered cards
    func checkIfCardIsCentered(frame: CGRect, index: Int) {
        // Calculate center position of the view
        let viewCenter = viewWidth / 2
        
        // Calculate center of the card
        let cardCenter = frame.origin.x + (frame.width / 2)
        
        // Check if card is near center (within 20 points)
        let isCentered = abs(viewCenter - cardCenter) < 20
        
        // If card is centered, trigger haptic and update index
        if isCentered && currentCardIndex != index {
            // Update the current index without heavy animations
            currentCardIndex = index
            
            // Give haptic feedback
            impactFeedback.impactOccurred()
            
            // Ensure we only update active slider if cards are the active control
            if activeControl == .cards {
                physicsSliderValue = Double(index)
                standardSliderValue = Double(index)
            }
        }
    }
}

struct CardScrollView_Previews: PreviewProvider {
    static var previews: some View {
        CardScrollView(onDismiss: {})
    }
}