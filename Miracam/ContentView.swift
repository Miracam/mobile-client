//
//  ContentView.swift
//  MIRAcam
//
//  Created by Junyao Chan on 16/11/2024.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView(isComplete: .init(
                get: { hasCompletedOnboarding },
                set: { hasCompletedOnboarding = $0 }
            ))
        } else {
            MainCameraView()
        }
    }
}

struct MainCameraView: View {
    var body: some View {
        // Your main camera app implementation
        Text("Camera View")
            .font(.largeTitle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .foregroundColor(.white)
    }
}

#Preview {
    ContentView()
}
