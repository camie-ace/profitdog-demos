import SwiftUI
import RevenueCat

/// A paywall designed for the "aha moment" context
/// 
/// Key differences from a generic paywall:
/// 1. Acknowledges what the user just accomplished
/// 2. Copy ties directly to the value they experienced
/// 3. Feels like a natural next step, not an interruption
struct AhaMomentPaywallView: View {
    @EnvironmentObject var paywallManager: PaywallManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Celebration header
                    VStack(spacing: 16) {
                        Text("🎉")
                            .font(.system(size: 60))
                        
                        Text("You're On Fire!")
                            .font(.largeTitle.bold())
                        
                        Text("You just completed your first lesson. Unlock unlimited learning to keep the momentum going.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    
                    // Value props - specific to what they just did
                    VStack(spacing: 16) {
                        FeatureRow(
                            icon: "infinity",
                            title: "Unlimited Lessons",
                            subtitle: "Learn at your own pace, no limits"
                        )
                        FeatureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Track Your Progress",
                            subtitle: "See how far you've come"
                        )
                        FeatureRow(
                            icon: "bell.badge",
                            title: "Smart Reminders",
                            subtitle: "Never break your streak"
                        )
                    }
                    .padding(.horizontal)
                    
                    // Packages
                    if let offering = paywallManager.currentOffering {
                        VStack(spacing: 12) {
                            ForEach(offering.availablePackages) { package in
                                PackageButton(
                                    package: package,
                                    isLoading: isLoading
                                ) {
                                    await purchase(package)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    // Restore purchases
                    Button("Restore Purchases") {
                        Task {
                            await restorePurchases()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    
                    // Terms
                    Text("Cancel anytime. Terms apply.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Go Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    private func purchase(_ package: Package) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await paywallManager.purchase(package)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await paywallManager.restorePurchases()
        } catch {
            errorMessage = "Could not restore purchases"
        }
        
        isLoading = false
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct PackageButton: View {
    let package: Package
    let isLoading: Bool
    let action: () async -> Void
    
    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            VStack(spacing: 4) {
                Text(package.storeProduct.localizedTitle)
                    .font(.headline)
                
                Text(package.localizedPriceString)
                    .font(.title2.bold())
                
                if let intro = package.storeProduct.introductoryDiscount {
                    Text(introText(for: intro))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(package.packageType == .annual ? .blue.gradient : .gray.opacity(0.1))
            .foregroundStyle(package.packageType == .annual ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                if package.packageType == .annual {
                    Text("BEST VALUE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .offset(y: -40)
                }
            }
        }
        .disabled(isLoading)
    }
    
    private func introText(for discount: StoreProductDiscount) -> String {
        switch discount.paymentMode {
        case .freeTrial:
            return "\(discount.subscriptionPeriod.value) \(discount.subscriptionPeriod.unit) free trial"
        case .payUpFront:
            return "Pay upfront, save more"
        case .payAsYouGo:
            return "Introductory pricing"
        @unknown default:
            return ""
        }
    }
}

#Preview {
    AhaMomentPaywallView()
        .environmentObject(PaywallManager.shared)
}
