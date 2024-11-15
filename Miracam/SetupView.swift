import SwiftUI
import UIKit

struct SetupView: View {
    @StateObject private var setupManager = SetupManager.shared
    @Binding var isComplete: Bool
    @State private var currentPage = 0
    @State private var setupStarted = false
    @State private var username = ""
    @State private var promoCode = ""
    
    @FocusState private var isUsernameFocused: Bool
    
    @State private var showSkipAlert = false
    @State private var showFinalSkipAlert = false
    @State private var showPromoSheet = false
    @State private var showPurchaseAlert = false
    
    @State private var skipAction: SkipAction = .none
    
    @State private var testTokenBalance: String = "Loading..."
    @State private var isRefreshing = false
    
    @GestureState private var dragOffset = CGSize.zero
    
    @State private var isLoading = false
    
    private enum SkipAction {
        case none
        case firstAlert
        case finalAlert
    }
    
    let pages = [
        "Welcome to MIRAcam",
        "Secure Your Content",
        "Create Your Identity",
        "Setup Your Wallet"
    ]
    
    private var fullUsername: String {
        if username.isEmpty {
            return "___"
        }
        return username
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                ForEach(0..<2) { index in
                    VStack {
                        Text(pages[index])
                            .font(.title)
                            .padding(.top, 100)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 200, height: 200)
                            .cornerRadius(12)
                            .padding(.top, 40)
                        
                        Spacer()
                    }
                    .tag(index)
                }
                
                VStack {
                    Text(pages[2])
                        .font(.title)
                        .padding(.top, 100)
                    
                    VStack(spacing: 4) {
                        HStack(spacing: 0) {
                            TextField("username", text: $username)
                                .focused($isUsernameFocused)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.trailing)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            Text(".miracam.com")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    
                    Text("This will be your public identity")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                    
                    Spacer()
                }
                .tag(2)
                
                VStack {
                    Text("Insert Film")
                        .font(.title)
                        .padding(.top, 100)
                    
                    VStack(spacing: 20) {
                        // Ethereum Address Section
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Ethereum Address")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            HStack {
                                if let address = EthereumManager.shared.getWalletAddress() {
                                    Text(address)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = address
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                    }
                                } else {
                                    Text("Setting up wallet...")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            // Add Film Balance Section
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Your Film Balance")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                    
                                    Button {
                                        Task {
                                            await refreshBalance()
                                        }
                                    } label: {
                                        Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                            .foregroundColor(.blue)
                                            .rotationEffect(isRefreshing ? .degrees(360) : .degrees(0))
                                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                                    }
                                    .disabled(isRefreshing)
                                }
                                
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(testTokenBalance)
                                        .font(.system(.title2, design: .monospaced))
                                        .fontWeight(.medium)
                                    
                                    Text("FILM")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.top, 12)
                            
                            // Username and FILM token info
                            if !username.isEmpty {
                                Text("You can also send FILM token to")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .padding(.top, 8)
                                
                                Text("\(username).miracam.com")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                        
                        
                    }
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)
            .simultaneousGesture(
                DragGesture()
                    .onEnded { value in
                        let threshold: CGFloat = 50
                        if value.translation.width < -threshold && currentPage < pages.count - 1 {
                            if canAdvance {
                                withAnimation {
                                    currentPage += 1
                                }
                            }
                        } else if value.translation.width > threshold && currentPage > 0 {
                            withAnimation {
                                currentPage -= 1
                            }
                        }
                    }
            )
            .highPriorityGesture(
                DragGesture()
                    .onChanged { _ in
                        if currentPage == 2 && username.isEmpty {
                            // Cancel the gesture by doing nothing
                            return
                        }
                    }
            )
            
            VStack {
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
                
                VStack(spacing: 20) {
                    // Page indicator dots
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(currentPage == index ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top)
                    
                    // Footer buttons only on last slide
                    if currentPage == 3 {
                        VStack(spacing: 16) {
                            // Promo Code Button
                            Button {
                                print("DEBUG: Promo button tapped")
                                showPromoSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "ticket")
                                    Text("Use Promo Code")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                            }
                            
                            // Buy Button
                            Button {
                                print("DEBUG: Buy button tapped")
                                showPurchaseAlert = true
                            } label: {
                                HStack {
                                    Text("Buy Film")
                                        .fontWeight(.semibold)
                                    Text("$4.99")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            
                            // Primary Action Button - Skip/Enter
                            Button(action: {
                                if setupManager.isChecking {
                                    isLoading = true
                                } else if hasFilmBalance {
                                    isComplete = true
                                } else {
                                    showSkipAlert = true
                                }
                            }) {
                                Text(hasFilmBalance ? "Enter" : "Skip")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.bottom, 30)
                            .alert("Skip Purchase?", isPresented: $showSkipAlert) {
                                Button("Cancel", role: .cancel) {
                                    print("DEBUG: Skip cancelled")
                                }
                                Button("Yes, Skip", role: .destructive) {
                                    print("DEBUG: Skip confirmed, showing final alert")
                                    showFinalSkipAlert = true
                                }
                            } message: {
                                Text("You won't be able to take pictures without film")
                            }
                            .alert("Enter Without Film", isPresented: $showFinalSkipAlert) {
                                Button("Continue", role: .destructive) {
                                    print("DEBUG: Final skip confirmed, completing setup")
                                    isComplete = true
                                }
                            } message: {
                                Text("You can always buy film later in the shop")
                            }
                            .alert("Waiting for Access NFT", isPresented: $isLoading) {
                                ProgressView()
                            } message: {
                                Text("Please wait while your access NFT is being minted.")
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // Primary Action Button - Next
                        Button(action: {
                            if currentPage < pages.count - 1 {
                                if currentPage == 2 && username.isEmpty {
                                    return
                                }
                                withAnimation {
                                    currentPage += 1
                                }
                                if currentPage == 3 {
                                    isUsernameFocused = false // Hide keyboard when reaching last slide
                                }
                            }
                        }) {
                            Text("Next")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(shouldDisableNextButton ? Color.gray : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(shouldDisableNextButton)
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                }
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .edgesIgnoringSafeArea(.bottom)
                )
            }
            
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
            await runSetup()
            await refreshBalance() // Initial balance check
            isLoading = false // Ensure loading is false after setup
        }
        .onTapGesture {
            isUsernameFocused = false
        }
        .sheet(isPresented: $showPromoSheet) {
            NavigationView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        TextField("Enter promo code", text: $promoCode)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button {
                            print("DEBUG: Promo submit tapped")
                            showPromoSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                showPurchaseAlert = true
                            }
                        } label: {
                            Text("Submit")
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Enter Promo Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            print("DEBUG: Promo cancel tapped")
                            showPromoSheet = false
                        }
                    }
                }
            }
        }
        .alert("Work in Progress", isPresented: $showPurchaseAlert) {
            Button("OK", role: .cancel) {
                print("DEBUG: WIP alert dismissed")
            }
        } message: {
            Text("Purchase functionality coming soon!")
        }
    }
    
    private var shouldDisableNextButton: Bool {
        if currentPage == 2 {
            return username.isEmpty
        }
        return false
    }
    
    private func runSetup() async {
        // Start setup in background
        Task {
            let success = await setupManager.runAllChecks()
            await MainActor.run {
                setupStarted = success
                if success {
                    // Force view update if needed
                    self.currentPage = self.currentPage
                }
            }
        }
    }
    
    private var hasFilmBalance: Bool {
        if let balance = Double(testTokenBalance), balance > 0 {
            return true
        }
        return false
    }
    
    private func refreshBalance() async {
        guard !isRefreshing else { return }
        
        await MainActor.run {
            isRefreshing = true
        }
        
        do {
            let balances = try await EthereumManager.shared.getBalances()
            await MainActor.run {
                testTokenBalance = balances.test
                isRefreshing = false
            }
        } catch {
            await MainActor.run {
                testTokenBalance = "0"
                isRefreshing = false
            }
        }
    }
    
    private var canAdvance: Bool {
        if currentPage == 2 {
            return !username.isEmpty
        }
        return true
    }
}

#Preview {
    SetupView(isComplete: .constant(false))
} 