import SwiftUI

struct SetupView: View {
    @StateObject private var setupManager = SetupManager.shared
    @Binding var isComplete: Bool
    @State private var currentPage = 0
    @State private var setupStarted = false
    
    let pages = [
        "Welcome to MIRAcam",
        "Secure Your Content",
        "Verify Your Device",
        "Setup Your Wallet"
    ]
    
    var body: some View {
        ZStack {
            // Slideshow content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    VStack {
                        Text(pages[index])
                            .font(.title)
                            .padding(.top, 100)
                        
                        // Placeholder for future graphics
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 200, height: 200)
                            .cornerRadius(12)
                            .padding(.top, 40)
                        
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)
            
            VStack {
                // Floating status bar
                if setupManager.isChecking {
                    HStack {
                        if let currentCheck = setupManager.currentCheck {
                            Text(currentCheck.description)
                                .font(.footnote)
                            
                            Spacer()
                            
                            Text(setupManager.formattedElapsedTime)
                                .font(.footnote)
                                .monospacedDigit()
                        }
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.top, 44)
                }
                
                Spacer()
                
                // Navigation buttons and page indicator
                VStack(spacing: 20) {
                    // Page indicator dots
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding()
                    
                    // Next/Enter button
                    Button(action: {
                        if currentPage < pages.count - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            isComplete = true
                        }
                    }) {
                        HStack {
                            Text(currentPage < pages.count - 1 ? "Next" : "Enter")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(currentPage == pages.count - 1 && !setupStarted ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(currentPage == pages.count - 1 && !setupStarted)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .edgesIgnoringSafeArea(.bottom)
                )
            }
            
            // Error overlay
            if setupManager.setupFailed {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack(spacing: 20) {
                            Text("Setup Failed")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            ForEach(setupManager.failedChecks, id: \.self) { check in
                                Text(check.description)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            
                            Button("Retry") {
                                Task {
                                    await runSetup()
                                }
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding()
                    )
            }
        }
        .task {
            // Start setup immediately when view appears
            await runSetup()
        }
    }
    
    private func runSetup() async {
        let success = await setupManager.runAllChecks()
        setupStarted = success
    }
}

#Preview {
    SetupView(isComplete: .constant(false))
} 