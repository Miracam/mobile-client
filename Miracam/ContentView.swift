//
//  ContentView.swift
//  Miracam
//
//  Created by Junyao Chan on 15/11/2024.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1
    @State private var isSetupComplete = false
    
    var body: some View {
        if !isSetupComplete {
            SetupView(isSetupComplete: $isSetupComplete)
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
        }
    }
}

#Preview {
    ContentView()
}
