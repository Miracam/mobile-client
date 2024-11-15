//
//  ContentView.swift
//  Miracam
//
//  Created by Junyao Chan on 15/11/2024.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1
    @StateObject private var setupManager = SetupManager.shared
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    
    var body: some View {
        Group {
            if !hasCompletedInitialSetup {
                SetupView(isComplete: $hasCompletedInitialSetup)
            } else {
                TabView(selection: $selectedTab) {
                    AccountView()
                        .tabItem {
                            Image(systemName: "person.circle.fill")
                            Text("Account")
                        }
                        .tag(0)
                    
                    CameraView()
                        .tabItem {
                            Image(systemName: "camera.fill")
                            Text("Camera")
                        }
                        .tag(1)
                    
                    WorldView()
                        .tabItem {
                            Image(systemName: "globe")
                            Text("World")
                        }
                        .tag(2)
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
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
}

#Preview {
    ContentView()
}
