import SwiftUI
import UIKit

struct OnboardingView: View {
    @StateObject private var setupManager = SetupManager.shared
    @Binding var isComplete: Bool
    
    // Visual states
    @State private var isExpanded = false
    @State private var isFullScreen = false
    @State private var isNameMoved = false
    @State private var name: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    
    // Typing animation states
    @State private var typingText: String = ""
    @State private var startTyping = false
    @State private var mainTypingDone = false
    @State private var finalTypingDone = false
    @State private var slideUpOffset: CGFloat = 0
    @State private var currentSlide: Int = 1
    
    // Setup states
    @State private var showPromoSheet = false
    @State private var showPurchaseAlert = false
    @State private var promoCode = ""
    @State private var isLoading = false
    @State private var testTokenBalance: String = "Loading..."
    @State private var isRefreshing = false

    // let customFont = UIFont(name: "CSDovie-RegularDemo", size: 16.0)
    
    // Content strings
    private let mainText: String = """
    Congratulations on getting yourself a Miracam.

    Every moment is real & unique, but fake image is destroying trust.

    Miracam solves this by making all shots verifiable and on-chain INSTANTLY (using science).

    Without further ado.
    """
    
    private let finalLine: String = "Let's Make Image Real Again."
    
    private let slide2Content: String = """
    All your shots are NFT. It is stored forever, along with details that make it real & original.

    Like the real camera, your Miracam runs on $FILM. One $FILM = One shot.

    You can either shot in PUBLIC or PRIVATE. Private shots is only visible and available to you (it is protected & locked).
    """
    
    @State private var slide2Text: String = ""
    @State private var slide2TypeDone = false
    
    // Add this state variable at the top with other states
    @State private var currentImageIndex = 1
    @State private var slideShowTimer: Timer?
    
    // Add these states
    @State private var finalTypingText: String = ""
    @State private var isLaunching = false
    @State private var showLoadingScreen = false
    @State private var showFinalMessage = false
    @State private var tapAnimation = false
    @State private var showReward = false
    @State private var showNerdTalkSheet = false
    
    private let finalMessageText = """
    Free 999 $FILM for you...because you're awesome.
    """
    
    private let rewardText = """
    You've got 999 $FILM!
    You can take 999 photos
    """
    
    // Add this enum at the top of the file
    private var setupIcon: String {
        setupManager.setupProgress.icon
    }
    
    private var setupDescription: String {
        setupManager.setupProgress.description
    }
    
    // Add state for setup progress
    @State private var isRotating = false
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let buttonHeight: CGFloat = 60
                let cardSize: CGFloat = 300
                
                ZStack {
                    // Background with slideshow
                    if !isFullScreen {
                        ZStack {
                            Image("photo_\(currentImageIndex)")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .edgesIgnoringSafeArea(.all)
                                .position(x: geometry.size.width/2, y: geometry.size.height/2)
                            
                            // Black overlay
                            Color.black.opacity(0.5)
                                .edgesIgnoringSafeArea(.all)
                        }
                        .onAppear {
                            // Start slideshow timer
                            slideShowTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentImageIndex = currentImageIndex % 3 + 1
                                }
                            }
                        }
                        .onDisappear {
                            // Clean up timer when view disappears
                            slideShowTimer?.invalidate()
                            slideShowTimer = nil
                        }
                    }
                    
                    // Add title and subtitle here (moved inside GeometryReader)
                    if !isExpanded {
                        VStack(spacing: 8) {
                            Text("Miracam")
                                .font(.custom("CSDovie-RegularDemo",size: 48))
                                .foregroundColor(.white)
                            
                            Text("Make Image Real Again")
                                .font(.custom("CSDovie-RegularDemo",size: 20))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(x: geometry.size.width/2, y: geometry.size.height/2)
                    }
                    
                    // Background overlay for handling taps
                    if isExpanded && !isFullScreen {
                        Color.black.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                            .onTapGesture {
                                if !isFullScreen {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isExpanded = false
                                    }
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                }
                            }
                    }
                    
                    // Main content
                    VStack {
                        if isExpanded {
                            VStack(spacing: 0) {
                                if isFullScreen {
                                    ZStack {
                                        // Slide 1
                                        VStack(alignment: .leading, spacing: 0) {
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text("Hello, \(name)")
                                                    .font(.custom("ComicSansMS", size: 32))
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.black)
                                                    .frame(maxWidth: .infinity, alignment: isNameMoved ? .leading : .center)
                                                    .padding(.leading, isNameMoved ? 32 : 0)
                                                    .padding(.top, isNameMoved ? 100 : 0)
                                                
                                                if startTyping {
                                                    Text(typingText)
                                                        .font(.custom("ComicSansMS", size: 20))
                                                        .foregroundColor(.black)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .padding(.horizontal, 32)
                                                        .padding(.top, 32)
                                                        .lineSpacing(8)
                                                    
                                                    if mainTypingDone {
                                                        Text(finalTypingText)
                                                            .font(.custom("ComicSansMS", size: 28))
                                                            .fontWeight(.heavy)
                                                            .foregroundColor(.black)
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                            .padding(.horizontal, 32)
                                                            .padding(.top, 32)
                                                    }
                                                }
                                            }
                                            .frame(maxHeight: .infinity, alignment: isNameMoved ? .top : .center)
                                            
                                            if finalTypingDone {
                                                Button(action: {
                                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                                        slideUpOffset = -UIScreen.main.bounds.height
                                                        currentSlide = 2
                                                    }
                                                    let impact = UIImpactFeedbackGenerator(style: .heavy)
                                                    impact.impactOccurred()
                                                    
                                                    // Start typing after slide animation
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                                        typeWriterSlide2()
                                                    }
                                                }) {
                                                    Text("What???")
                                                        .font(.custom("ComicSansMS", size: 18))
                                                        .foregroundColor(.white)
                                                        .frame(maxWidth: .infinity)
                                                        .frame(height: 60)
                                                        .background(Color.black)
                                                        .cornerRadius(15)
                                                }
                                                .padding(.horizontal, 32)
                                                .padding(.bottom, 40)
                                                .transition(.opacity)
                                            }
                                        }
                                        .offset(y: slideUpOffset)
                                        
                                        // Slide 2
                                        VStack(alignment: .leading, spacing: 20) {
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(slide2Text)
                                                    .font(.custom("ComicSansMS", size: 20))
                                                    .foregroundColor(.black)
                                                    .padding(.top, 100)
                                                    .padding(.horizontal, 32)
                                                    .lineSpacing(8)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .opacity(isLaunching ? 0 : 1)
                                                
                                                if slide2TypeDone {
                                                    Button(action: {
                                                        showNerdTalkSheet = true
                                                    }) {
                                                        Text("NERD TALK")
                                                            .font(.custom("ComicSansMS", size: 16))
                                                            .foregroundColor(.blue)
                                                            .overlay(
                                                                Rectangle()
                                                                    .frame(height: 1)
                                                                    .offset(y: 8)
                                                                    .foregroundColor(.blue),
                                                                alignment: .bottom
                                                            )
                                                    }
                                                    .padding(.top, 32)
                                                    .padding(.leading, 32)
                                                    .transition(.opacity)
                                                    .sheet(isPresented: $showNerdTalkSheet) {
                                                        NerdTalkSheet()
                                                    }
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if slide2TypeDone {
                                                Button(action: {
                                                    // Launch button action
                                                    let impactMed = UIImpactFeedbackGenerator(style: .rigid)
                                                    impactMed.impactOccurred(intensity: 1.0)
                                                    
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        isLaunching = true
                                                    }
                                                    
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                                                        impactHeavy.impactOccurred(intensity: 1.0)
                                                        
                                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                                            showLoadingScreen = true
                                                        }
                                                    }
                                                }) {
                                                    HStack {
                                                        if isLaunching && !showLoadingScreen {
                                                            ProgressView()
                                                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                                .scaleEffect(1.2)
                                                        } else if !isLaunching {
                                                            Text("Launch Miracam")
                                                                .font(.custom("ComicSansMS", size: 18))
                                                        }
                                                    }
                                                    .foregroundColor(.black)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 60)
                                                    .background(Color(hex: "FFD551"))
                                                    .cornerRadius(15)
                                                }
                                                .padding(.horizontal, 32)
                                                .padding(.bottom, 40)
                                                .transition(.opacity)
                                                .opacity(showLoadingScreen ? 0 : 1)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                        .background(Color.white)
                                        .offset(y: slideUpOffset + UIScreen.main.bounds.height)
                                        
                                        // Yellow loading screen
                                        if showLoadingScreen {
                                            ZStack {
                                                Color(hex: "FFD551")
                                                    .edgesIgnoringSafeArea(.all)
                                                
                                                // Content with slight bounce effect
                                                VStack(alignment: .leading, spacing: 20) {
                                                    // Top message
                                                    Text(finalMessageText)
                                                        .font(.custom("ComicSansMS", size: 24))
                                                        .foregroundColor(.black)
                                                        .padding(.top, 100)
                                                        .padding(.horizontal, 16)
                                                        .lineSpacing(12)
                                                        .opacity(showReward ? 0 : 1)
                                                        .animation(.easeOut(duration: 0.3), value: showReward)
                                                    
                                                    Spacer()
                                                    
                                                    // Bottom elements
                                                    VStack(alignment: .leading, spacing: 16) {
                                                        Text("xoxo")
                                                            .font(.custom("ComicSansMS", size: 24))
                                                            .foregroundColor(.black)
                                                        
                                                        Text("tip: tap tape to peel")
                                                            .font(.custom("ComicSansMS", size: 20))
                                                            .foregroundColor(.black)
                                                    }
                                                    .padding(.bottom, 60)
                                                    .padding(.horizontal, 32)
                                                    .opacity(showReward ? 0 : 1)
                                                    .animation(.easeOut(duration: 0.3), value: showReward)
                                                }
                                                .scaleEffect(showLoadingScreen ? 1 : 1.2)
                                                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showLoadingScreen)
                                                
                                                // Coin and tape with more dynamic animation
                                                ZStack {
                                                    // Coin with slight rotation
                                                    Image("coin")
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(width: 240, height: 240)
                                                        .rotationEffect(showLoadingScreen ? .degrees(0) : .degrees(-15))
                                                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showLoadingScreen)
                                                        .position(x: UIScreen.main.bounds.width/2, 
                                                                y: UIScreen.main.bounds.height/2)
                                                    
                                                    // Tape using image
                                                    Image("tape")
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(width: 385.12)
                                                        .scaleEffect(tapAnimation ? 1.5 : (showLoadingScreen ? 1 : 0.8))
                                                        .opacity(tapAnimation ? 0 : 1)
                                                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showLoadingScreen)
                                                        .animation(.easeOut(duration: 0.3), value: tapAnimation)
                                                        .position(x: UIScreen.main.bounds.width/2, 
                                                                y: UIScreen.main.bounds.height/2 - 20)
                                                }
                                                .onTapGesture {
                                                    // Play haptic feedback
                                                    let impact = UIImpactFeedbackGenerator(style: .heavy)
                                                    impact.impactOccurred(intensity: 1.0)
                                                    
                                                    // Only animate tape
                                                    withAnimation(.easeOut(duration: 0.3)) {
                                                        tapAnimation = true
                                                    }
                                                    
                                                    // Show reward text after animation
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                            showReward = true
                                                        }
                                                    }
                                                }
                                                
                                                // Reward text and button
                                                if showReward {
                                                    VStack {
                                                        VStack(spacing: 8) {
                                                            Text("You've got 999 $FILM!")
                                                                .font(.custom("ComicSansMS", size: 24))
                                                                .foregroundColor(.black)
                                                            
                                                            Text("You can take 999 photos")
                                                                .font(.custom("ComicSansMS", size: 18))
                                                                .foregroundColor(.black)
                                                        }
                                                        .multilineTextAlignment(.center)
                                                        .padding(.horizontal, 32)
                                                        .padding(.top, 160)
                                                        
                                                        Spacer()
                                                        
                                                        // Footer section
                                                        VStack(spacing: 12) {
                                                            Text("Time to Save the World")
                                                                .font(.custom("ComicSansMS", size: 14))
                                                                .foregroundColor(.black)
                                                            
                                                            Button(action: {
                                                                // Complete onboarding with animation
                                                                withAnimation {
                                                                    isComplete = true  // This will trigger the transition to MainCameraView
                                                                }
                                                            }) {
                                                                Text("Make Image Real Again")
                                                                    .font(.custom("ComicSansMS", size: 18))
                                                                    .foregroundColor(.black)
                                                                    .frame(maxWidth: .infinity)
                                                                    .frame(height: 60)
                                                                    .background(Color.white)
                                                                    .cornerRadius(15)
                                                            }
                                                        }
                                                        .padding(.horizontal, 32)
                                                        .padding(.bottom, 40)
                                                    }
                                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                                }
                                            }
                                            .transition(.opacity.combined(with: .scale(scale: 1.1)))
                                        }
                                    }
                                } else {
                                    // Name input view (initial expanded state)
                                    nameInputView
                                }
                            }
                            .frame(
                                width: isFullScreen ? UIScreen.main.bounds.width : cardSize,
                                height: isFullScreen ? UIScreen.main.bounds.height : cardSize
                            )
                        } else {
                            // Initial "Get Started" button
                            Text("Get Started")
                                .font(.custom("ComicSansMS", size: 20))
                                .foregroundColor(.black)
                                .frame(height: buttonHeight)
                                .frame(width: min(geometry.size.width - 64, 280))
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isExpanded = true
                                    }
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isInputFocused = true
                                    }
                                }
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(isFullScreen ? 0 : 30)
                    .shadow(radius: isFullScreen ? 0 : (isExpanded ? 10 : 5))
                    .position(
                        x: geometry.size.width / 2,
                        y: isExpanded 
                            ? (geometry.size.height / 2) - (isInputFocused ? keyboardHeight/2 : 0)
                            : geometry.size.height - buttonHeight - 30
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: keyboardHeight)
                }
            }
            
            // Floating status button at root level
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        // Setup progress indicator
                        Image(systemName: setupIcon)
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 3)
                            .scaleEffect(isRotating ? 1.2 : 1.0)
                            .animation(
                                isRotating ? 
                                    Animation.easeInOut(duration: 0.8)
                                        .repeatForever(autoreverses: true) : 
                                    .default,
                                value: isRotating
                            )
                    }
                    .onTapGesture {
                        if setupManager.setupProgress == .failed {
                            Task {
                                await runSetup()
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
            .ignoresSafeArea()
            .zIndex(999)
        }
        .task {
            await runSetup()
            await refreshBalance()
        }
        // Add sheets and alerts from SetupView
        .onAppear {
            // Set up keyboard notifications
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
            
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    keyboardHeight = 0
                }
            }
        }
    }
    
    // Add helper views and methods from both files
    private var nameInputView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 32)
            
            Text("Hi, my name is")
                .font(.custom("ComicSansMS", size: 24))
                .fontWeight(.medium)
                .foregroundColor(.black)
            
            VStack {
                Spacer()
                TextField("", text: $name)
                    .font(.custom("ComicSansMS", size: 21))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .focused($isInputFocused)
                    .placeholder(when: name.isEmpty) {
                        Text("enter your name")
                            .font(.custom("ComicSansMS", size: 21))
                            .fontWeight(.bold)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                Spacer()
            }
            .frame(maxHeight: .infinity)
            
            Divider()
                .frame(maxWidth: .infinity)
                .frame(height: 1)
                .background(Color.gray.opacity(0.3))
            
            Text(".miracam.com")
                .font(.custom("ComicSansMS", size: 16))
                .foregroundColor(.gray)
                .padding(.top, 8)
                .padding(.bottom, 24)
            
            Button(action: {
                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                impactHeavy.impactOccurred()
                isInputFocused = false
                
                // Save username
                setupManager.saveUsername(name)
                
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isFullScreen = true
                }
                
                // Start the animation sequence after going fullscreen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation {
                        isNameMoved = true
                        let impactMed = UIImpactFeedbackGenerator(style: .soft)
                        impactMed.impactOccurred()
                        
                        // Start typing animation after name moves
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            startTyping = true
                            typeWriter()
                        }
                    }
                }
            }) {
                Text("Submit")
                    .font(.custom("ComicSansMS", size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }
    
    // Add all the helper methods from SetupView
    private func runSetup() async {
        isRotating = true
        
        let success = await setupManager.runAllChecks()
        
        // If setup was already complete (found existing keys), stop rotating immediately
        if setupManager.setupProgress == .completed {
            withAnimation {
                isRotating = false
            }
            return
        }
        
        withAnimation {
            if !success {
                isRotating = false
            } else {
                // Add a small delay before stopping the animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        isRotating = false
                    }
                }
            }
        }
    }
    
    private func refreshBalance() async {
        // Implementation from SetupView
    }
    
    // Add typing animation methods from NewOnboardContentView
    private func typeWriter(at position: Int = 0, isFinalLine: Bool = false) {
        if position == 0 {
            if !isFinalLine {
                typingText = ""
            } else {
                finalTypingText = ""
            }
        }
        
        let currentText = isFinalLine ? finalLine : mainText
        if position < currentText.count {
            let index = currentText.index(currentText.startIndex, offsetBy: position)
            let nextIndex = currentText.index(currentText.startIndex, offsetBy: min(position + 1, currentText.count - 1))
            let currentChar = currentText[index]
            let nextChar = position + 1 < currentText.count ? currentText[nextIndex] : " "
            
            let delay: TimeInterval
            if currentChar == "\n" && nextChar == "\n" {
                delay = 0.5
            } else {
                delay = isFinalLine ? 0.08 : 0.03
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if isFinalLine {
                    finalTypingText.append(currentChar)
                } else {
                    typingText.append(currentChar)
                }
                
                let impact = UIImpactFeedbackGenerator(style: isFinalLine ? .heavy : .soft)
                impact.prepare()
                impact.impactOccurred(intensity: isFinalLine ? 1.0 : 0.5)
                
                typeWriter(at: position + 1, isFinalLine: isFinalLine)
            }
        } else {
            if !isFinalLine {
                mainTypingDone = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    typeWriter(at: 0, isFinalLine: true)
                }
            } else {
                withAnimation {
                    finalTypingDone = true
                }
            }
        }
    }
    
    private func typeWriterSlide2(at position: Int = 0) {
        if position == 0 {
            slide2Text = ""
        }
        if position < slide2Content.count {
            let index = slide2Content.index(slide2Content.startIndex, offsetBy: position)
            let nextIndex = slide2Content.index(slide2Content.startIndex, offsetBy: min(position + 1, slide2Content.count - 1))
            let currentChar = slide2Content[index]
            let nextChar = position + 1 < slide2Content.count ? slide2Content[nextIndex] : " "
            
            let delay: TimeInterval = (currentChar == "\n" && nextChar == "\n") ? 0.5 : 0.03
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                slide2Text.append(currentChar)
                let impact = UIImpactFeedbackGenerator(style: .soft)
                impact.prepare()
                impact.impactOccurred(intensity: 0.5)
                typeWriterSlide2(at: position + 1)
            }
        } else {
            withAnimation {
                slide2TypeDone = true
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
} 