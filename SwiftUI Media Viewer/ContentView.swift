//
//  ContentView.swift
//  SwiftUI Media Viewer
//
//  Created by Paul Mayne on 3/18/25.
//

import SwiftUI

struct ContentView: View {
    @State private var showMediaViewer = false
    @State private var showCardViewer = false
    @State private var selectedMediaIndex = 0
    @State private var selectedThumbnailFrame: CGRect = .zero
    @State private var mediaItems: [MediaItem] = []
    
    let columns = [
        GridItem(.adaptive(minimum: 75, maximum: 80), spacing: 10)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Media Gallery")
                        .font(.largeTitle)
                        .bold()
                        .padding(.horizontal)
                    
                    if mediaItems.isEmpty {
                        // Loading or no media state
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading media...")
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        // Media grid
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                                MediaThumbnail(item: item) { frame in
                                    selectedMediaIndex = index
                                    selectedThumbnailFrame = frame
                                    showMediaViewer = true
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
                
                Button(action: {
                    showCardViewer = true
                }) {
                    Text("Viewer 02")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Media Viewer")
                        .font(.headline)
                }
            }
        }
        .onAppear {
            loadMediaItems()
        }
        
        // Media viewer with custom presentation style
        .fullScreenCover(isPresented: $showMediaViewer) {
            MediaViewer(
                startIndex: selectedMediaIndex,
                mediaItems: mediaItems,
                sourceFrame: selectedThumbnailFrame,
                onDismiss: {
                    showMediaViewer = false
                }
            )
            .transition(.opacity) // Use fade transition instead of slide
        }
        
        // Card viewer with fullscreen presentation
        .fullScreenCover(isPresented: $showCardViewer) {
            CardScrollView(onDismiss: {
                showCardViewer = false
            })
        }
    }
    
    // Load sample media items from Preview Content folder
    private func loadMediaItems() {
        let fileManager = FileManager.default
        var mediaItems: [MediaItem] = []
        
        // Search in Preview Content folder first
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("Preview Content") {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: bundleURL,
                    includingPropertiesForKeys: nil
                )
                
                for url in contents {
                    let pathExtension = url.pathExtension.lowercased()
                    
                    // Process individual files
                    if ["jpg", "jpeg", "png", "gif"].contains(pathExtension) {
                        mediaItems.append(MediaItem(url: url, type: .image))
                    } else if ["mp4", "mov"].contains(pathExtension) {
                        mediaItems.append(MediaItem(url: url, type: .video))
                    }
                }
            } catch {
                print("Error accessing Preview Content directory: \(error)")
            }
        }
        
        // If no media files found in Preview Content, try other locations
        if mediaItems.isEmpty {
            // Try different potential locations for the Media folder
            var searchLocations: [URL] = []
            
            // 1. Check the app bundle
            if let bundleURL = Bundle.main.resourceURL {
                searchLocations.append(bundleURL)
                searchLocations.append(bundleURL.appendingPathComponent("Media"))
            }
            
            // 2. Check the Documents directory
            if let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                searchLocations.append(docURL.appendingPathComponent("Media"))
            }
            
            // Look for media in all search locations
            for location in searchLocations {
                do {
                    let contents = try fileManager.contentsOfDirectory(
                        at: location,
                        includingPropertiesForKeys: nil
                    )
                    
                    for url in contents {
                        let pathExtension = url.pathExtension.lowercased()
                        
                        // Check if it's a directory (might be the Media folder)
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
                            if url.lastPathComponent == "Media" {
                                do {
                                    let mediaFiles = try fileManager.contentsOfDirectory(
                                        at: url,
                                        includingPropertiesForKeys: nil
                                    )
                                    for mediaFile in mediaFiles {
                                        let mediaExt = mediaFile.pathExtension.lowercased()
                                        if ["jpg", "jpeg", "png", "gif"].contains(mediaExt) {
                                            mediaItems.append(MediaItem(url: mediaFile, type: .image))
                                        } else if ["mp4", "mov"].contains(mediaExt) {
                                            mediaItems.append(MediaItem(url: mediaFile, type: .video))
                                        }
                                    }
                                } catch {
                                    print("Error reading Media directory: \(error)")
                                }
                            }
                            continue
                        }
                        
                        // Process individual files
                        if ["jpg", "jpeg", "png", "gif"].contains(pathExtension) {
                            mediaItems.append(MediaItem(url: url, type: .image))
                        } else if ["mp4", "mov"].contains(pathExtension) {
                            mediaItems.append(MediaItem(url: url, type: .video))
                        }
                    }
                } catch {
                    print("Error accessing directory \(location.path): \(error)")
                }
            }
        }
        
        // Sort by filename
        self.mediaItems = mediaItems.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        
        // If no media was found, add some mock data for testing in preview
        #if DEBUG
        if mediaItems.isEmpty && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // Add mock data for previews
            let mockImageURL = URL(fileURLWithPath: "/mockImage.jpg")
            let mockVideoURL = URL(fileURLWithPath: "/mockVideo.mp4")
            mediaItems = [
                MediaItem(url: mockImageURL, type: .image),
                MediaItem(url: mockVideoURL, type: .video)
            ]
            self.mediaItems = mediaItems
        }
        #endif
    }
}

// Thumbnail for a media item in the grid
struct MediaThumbnail: View {
    let item: MediaItem
    let onTap: (CGRect) -> Void
    
    var body: some View {
        GeometryReader { geo in
            Button(action: {
                // Pass the global frame of this thumbnail to the parent
                let frame = geo.frame(in: .global)
                onTap(frame)
            }) {
                ZStack(alignment: .bottomTrailing) {
                    // Media thumbnail
                    Group {
                        if item.type == .image {
                            AsyncImage(url: item.url) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(ProgressView().scaleEffect(0.5))
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                        )
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            // Video thumbnail with icon
                            ZStack {
                                Rectangle()
                                    .fill(Color(UIColor.systemGray5))
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: 60, height: 60) // Square aspect ratio
                    .clipped()
                    .cornerRadius(4)
                    
                    // Video indicator badge
                    if item.type == .video {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                            .padding(3)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .padding(3)
                    }
                }
                .padding(3) // Add padding around each thumbnail
            }
            .buttonStyle(PlainButtonStyle())
            .id(item.id) // Ensure unique identification
        }
        .frame(width: 60, height: 60) // Match the inner image size
    }
}

#Preview {
    ContentView()
}