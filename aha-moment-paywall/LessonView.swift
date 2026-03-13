import SwiftUI

/// A simple lesson that demonstrates the "aha moment" trigger
struct LessonView: View {
    @EnvironmentObject var paywallManager: PaywallManager
    @Environment(\.dismiss) private var dismiss
    @Binding var lessonsCompleted: Int
    
    @State private var currentStep = 0
    @State private var isCompleted = false
    
    private let lessonSteps = [
        LessonStep(
            title: "Welcome!",
            content: "Let's learn something amazing today.",
            emoji: "👋"
        ),
        LessonStep(
            title: "The Concept",
            content: "Great apps show value before asking for payment.",
            emoji: "💡"
        ),
        LessonStep(
            title: "The Pattern",
            content: "Wait for the 'aha moment' - when users feel the value.",
            emoji: "🎯"
        ),
        LessonStep(
            title: "You Did It!",
            content: "You just experienced an aha moment. Notice how the paywall appears NOW, not at launch?",
            emoji: "🎉"
        )
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Progress bar
                ProgressView(value: Double(currentStep + 1), total: Double(lessonSteps.count))
                    .tint(.blue)
                    .padding(.horizontal)
                
                Spacer()
                
                // Lesson content
                VStack(spacing: 24) {
                    Text(lessonSteps[currentStep].emoji)
                        .font(.system(size: 80))
                    
                    Text(lessonSteps[currentStep].title)
                        .font(.largeTitle.bold())
                    
                    Text(lessonSteps[currentStep].content)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .animation(.spring, value: currentStep)
                
                Spacer()
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button {
                            withAnimation {
                                currentStep -= 1
                            }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    Button {
                        if currentStep < lessonSteps.count - 1 {
                            withAnimation {
                                currentStep += 1
                            }
                        } else {
                            completeLesson()
                        }
                    } label: {
                        Label(
                            currentStep < lessonSteps.count - 1 ? "Continue" : "Complete",
                            systemImage: currentStep < lessonSteps.count - 1 ? "chevron.right" : "checkmark"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Lesson \(lessonsCompleted + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func completeLesson() {
        lessonsCompleted += 1
        
        // 🎯 THIS IS THE KEY MOMENT
        // User just completed something valuable - NOW we track the aha moment
        // The PaywallManager will decide if it's time to show the paywall
        paywallManager.trackAhaMoment()
        
        // Give haptic feedback for the win
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Dismiss lesson view
        dismiss()
    }
}

struct LessonStep {
    let title: String
    let content: String
    let emoji: String
}

#Preview {
    LessonView(lessonsCompleted: .constant(0))
        .environmentObject(PaywallManager.shared)
}
