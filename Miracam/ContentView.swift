//
//  ContentView.swift
//  MIRAcam
//
//  Created by Junyao Chan on 16/11/2024.
//

import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var setupManager = SetupManager.shared
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    
    var body: some View {
        ZStack {
            // Hidden WebView layer
            if let webView = ContentKeyManager.shared.getWebView() {
                WebViewWrapper(webView: webView)
                    .frame(maxWidth: 1, maxHeight: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibility(hidden: true)
            }
            
            // Main content layer
            Group {
                if !hasCompletedInitialSetup {
                    SetupView(isComplete: $hasCompletedInitialSetup)
                } else {
                    TabView {
                        CameraView()
                        
                        WorldView()
                            .background(Color.green)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(alignment: .top) {
                        if setupManager.isChecking {
                            HStack {
                                if let currentCheck = setupManager.currentCheck {
                                    Text(currentCheck.description)
                                        .font(.footnote)
                                        .padding(8)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(8)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top, 44)
                        }
                    }
                    .disabled(setupManager.isChecking)
                    .opacity(setupManager.isChecking ? 0.5 : 1)
                    .task {
                        // Just verify without blocking since we're already set up
                        Task {
                            _ = await setupManager.runAllChecks()
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()  // Make the entire view fullscreen
        .statusBar(hidden: true)  // Hide the status bar
    }
}

struct WebViewWrapper: UIViewRepresentable {
    let webView: WKWebView
    
    func makeUIView(context: Context) -> WKWebView {
        print("🔵 WebViewWrapper: Creating WebView")
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        print("🔵 WebViewWrapper: Updating WebView")
    }
}

#Preview {
    ContentView()
}
