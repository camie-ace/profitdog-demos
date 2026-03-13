import SwiftUI
import RevenueCat

struct ContentView: View {
    @EnvironmentObject var paywallManager: PaywallManager
    @State private var isShowingLesson = false
    @State private var lessonsCompleted = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Hero section
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue.gradient)
                    
                    Text("Learn Something New")
                        .font(.largeTitle.bold())
                    
                    Text("Complete your first lesson to unlock your potential")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Progress indicator
                if lessonsCompleted > 0 {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(lessonsCompleted) lesson\(lessonsCompleted == 1 ? "" : "s") completed!")
                            .font(.headline)
                    }
                    .padding()
                    .background(.orange.opacity(0.1))
                    .clipShape(Capsule())
                }
                
                // Premium badge if subscribed
                if paywallManager.isPremium {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("Premium Member")
                            .font(.headline)
                    }
                    .padding()
                    .background(.yellow.opacity(0.1))
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // Main CTA
                Button {
                    isShowingLesson = true
                } label: {
                    Label("Start Lesson", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationTitle("AhaLearn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !paywallManager.isPremium {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Upgrade") {
                            paywallManager.showPaywall(context: .settings)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingLesson) {
                LessonView(lessonsCompleted: $lessonsCompleted)
                    .environmentObject(paywallManager)
            }
            .sheet(isPresented: $paywallManager.shouldShowPaywall) {
                paywallManager.paywallDismissed()
            } content: {
                AhaMomentPaywallView()
                    .environmentObject(paywallManager)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PaywallManager.shared)
}
