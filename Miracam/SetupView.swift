import SwiftUI

struct SetupView: View {
    @Binding var isSetupComplete: Bool
    @State private var isChecking = true
    @State private var checkSteps = [
        "Checking camera permissions...",
        "Verifying network connection...",
        "Loading user data..."
    ]
    @State private var currentStep = 0
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            if isChecking {
                ProgressView()
                    .padding()
                
                Text(checkSteps[currentStep])
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
            } else {
                Text("System Check Complete")
                    .font(.title)
                    .bold()
                
                Text("Everything is ready to go!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if !isChecking {
                Button(action: {
                    withAnimation {
                        isSetupComplete = true
                    }
                }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .onAppear {
            runChecks()
        }
    }
    
    private func runChecks() {
        // Simulate system checks
        isChecking = true
        currentStep = 0
        
        // Run through each check with a delay
        for step in 0..<checkSteps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 1.0) {
                currentStep = step
            }
        }
        
        // Complete the checks
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(checkSteps.count) * 1.0) {
            isChecking = false
        }
    }
} 