//
//  MiracamApp.swift
//  Miracam
//
//  Created by Junyao Chan on 15/11/2024.
//

import SwiftUI

@main
struct MiracamApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Force portrait orientation for all screens
        return .portrait
    }
}
