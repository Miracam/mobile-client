//
//  ContentView.swift
//  MIRAcam
//
//  Created by Junyao Chan on 16/11/2024.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1 // Set the initial tab to CameraView

    var body: some View {
        TabView(selection: $selectedTab) {
            AccountView()
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen height
                .tabItem {
                    Image(systemName: "person.circle.fill")
                    Text("Account")
                }
                .tag(0) // Tag for AccountView
            
            CameraView()
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen height
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text("Camera")
                }
                .tag(1) // Tag for CameraView
            
            WorldView()
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen height
                .tabItem {
                    Image(systemName: "globe")
                    Text("World")
                }
                .tag(2) // Tag for WorldView
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Use page style for swiping
        .edgesIgnoringSafeArea(.all) // Ensure it fills the screen
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
