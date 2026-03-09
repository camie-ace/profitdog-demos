// paywall_implementation.swift
// Modern SwiftUI Paywall Implementation with RevenueCat
//
// Copy-paste patterns for subscription paywalls in iOS apps.
// Covers: basic paywall, feature-gated views, and A/B testing support.
//
// Requirements: RevenueCat SDK 4.0+, iOS 15+
// Install: https://docs.revenuecat.com/docs/ios-native-sdk-installation

import SwiftUI
import RevenueCat

// MARK: - 1. Basic Paywall View

/// Simple paywall showing available packages with purchase buttons
struct BasicPaywallView: View {
    @State private var offerings: Offerings?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if let offering = offerings?.current {
                    PackageListView(
                        offering: offering,
                        isPurchasing: $isPurchasing,
                        onPurchaseComplete: { dismiss() }
                    )
                } else if let error = errorMessage {
                    ErrorStateView(message: error) {
                        Task { await loadOfferings() }
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Go Premium")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Restore") {
                        Task { await restorePurchases() }
                    }
                    .disabled(isPurchasing)
                }
            }
        }
        .task { await loadOfferings() }
    }
    
    private func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            errorMessage = "Couldn't load subscription options. Please try again."
            print("RevenueCat offerings error: \(error)")
        }
    }
    
    private func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            if customerInfo.entitlements["premium"]?.isActive == true {
                dismiss()
            }
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }
}

// MARK: - Package List Component

struct PackageListView: View {
    let offering: Offering
    @Binding var isPurchasing: Bool
    let onPurchaseComplete: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Value proposition
                FeatureListView()
                
                // Package options
                ForEach(offering.availablePackages, id: \.identifier) { package in
                    PackageCard(
                        package: package,
                        isPurchasing: $isPurchasing,
                        onPurchaseComplete: onPurchaseComplete
                    )
                }
                
                // Legal links
                LegalLinksView()
            }
            .padding()
        }
    }
}

struct PackageCard: View {
    let package: Package
    @Binding var isPurchasing: Bool
    let onPurchaseComplete: () -> Void
    
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 12) {
            // Package title (e.g., "Monthly", "Annual")
            Text(package.storeProduct.localizedTitle)
                .font(.headline)
            
            // Price with period
            Text(priceString)
                .font(.title2)
                .fontWeight(.bold)
            
            // Savings badge for annual
            if package.packageType == .annual, let savings = calculateSavings() {
                Text("Save \(savings)%")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
            
            // Purchase button
            Button(action: { Task { await purchase() } }) {
                if isPurchasing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Subscribe")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPurchasing)
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var priceString: String {
        let price = package.storeProduct.localizedPriceString
        switch package.packageType {
        case .monthly: return "\(price)/month"
        case .annual: return "\(price)/year"
        case .weekly: return "\(price)/week"
        case .lifetime: return "\(price) once"
        default: return price
        }
    }
    
    private func calculateSavings() -> Int? {
        // Compare to monthly equivalent if available
        guard package.packageType == .annual else { return nil }
        // Simplified - in production, compare against monthly package price
        return 40 // Common annual discount
    }
    
    private func purchase() async {
        isPurchasing = true
        error = nil
        
        defer { isPurchasing = false }
        
        do {
            let result = try await Purchases.shared.purchase(package: package)
            
            if !result.userCancelled {
                // Purchase successful
                onPurchaseComplete()
            }
        } catch {
            self.error = "Purchase failed. Please try again."
            print("Purchase error: \(error)")
        }
    }
}

// MARK: - 2. Feature-Gated View Modifier

/// View modifier that shows paywall for non-premium users
struct PremiumGateModifier: ViewModifier {
    @State private var showPaywall = false
    @State private var isPremium = false
    
    func body(content: Content) -> some View {
        Group {
            if isPremium {
                content
            } else {
                PremiumLockedView {
                    showPaywall = true
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            BasicPaywallView()
        }
        .task {
            await checkPremiumStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .customerInfoUpdated)) { _ in
            Task { await checkPremiumStatus() }
        }
    }
    
    private func checkPremiumStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            isPremium = customerInfo.entitlements["premium"]?.isActive == true
        } catch {
            print("Failed to check premium status: \(error)")
        }
    }
}

extension View {
    /// Gate this view behind premium subscription
    func requiresPremium() -> some View {
        modifier(PremiumGateModifier())
    }
}

// Usage example:
// AdvancedAnalyticsView()
//     .requiresPremium()

// MARK: - 3. Paywall with A/B Test Support

/// Paywall that respects RevenueCat's placement-based experiments
struct ExperimentalPaywallView: View {
    let placementId: String
    @State private var offerings: Offerings?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if let placement = offerings?.currentOffering(forPlacement: placementId),
               let offering = placement {
                // RevenueCat returns the correct offering based on experiment assignment
                PaywallContent(offering: offering, onComplete: { dismiss() })
            } else if let defaultOffering = offerings?.current {
                // Fallback to default if placement not configured
                PaywallContent(offering: defaultOffering, onComplete: { dismiss() })
            } else {
                LoadingView()
            }
        }
        .task {
            offerings = try? await Purchases.shared.offerings()
        }
    }
}

// Usage:
// ExperimentalPaywallView(placementId: "onboarding_paywall")
// ExperimentalPaywallView(placementId: "feature_gate_paywall")

// MARK: - 4. Soft Paywall (Show Content Preview)

/// Paywall that shows a preview of premium content with upgrade prompt
struct SoftPaywallView<Content: View, Preview: View>: View {
    @ViewBuilder let fullContent: () -> Content
    @ViewBuilder let preview: () -> Preview
    
    @State private var isPremium = false
    @State private var showPaywall = false
    
    var body: some View {
        Group {
            if isPremium {
                fullContent()
            } else {
                VStack {
                    preview()
                    
                    // Upgrade banner
                    VStack(spacing: 8) {
                        Text("Unlock Full Access")
                            .font(.headline)
                        Text("Subscribe to see all content")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("View Plans") {
                            showPaywall = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            BasicPaywallView()
        }
        .task {
            let info = try? await Purchases.shared.customerInfo()
            isPremium = info?.entitlements["premium"]?.isActive == true
        }
    }
}

// Usage:
// SoftPaywallView {
//     FullArticleView(article: article)
// } preview: {
//     ArticlePreviewView(article: article, paragraphs: 2)
// }

// MARK: - 5. RevenueCat Paywall UI (Low-Code Option)

/// Using RevenueCat's native paywall UI (requires RevenueCatUI package)
/// This is the fastest way to get a paywall running - design it in the dashboard!
///
/// import RevenueCatUI
///
/// struct NativePaywallView: View {
///     @State private var showPaywall = false
///
///     var body: some View {
///         Button("Upgrade") {
///             showPaywall = true
///         }
///         .presentPaywallIfNeeded(
///             requiredEntitlementIdentifier: "premium",
///             isPresented: $showPaywall
///         )
///     }
/// }

// MARK: - Supporting Views

struct FeatureListView: View {
    let features = [
        ("star.fill", "Unlimited access"),
        ("bolt.fill", "Faster sync"),
        ("chart.bar.fill", "Advanced analytics"),
        ("icloud.fill", "Cloud backup")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features, id: \.1) { icon, text in
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                    Text(text)
                }
            }
        }
        .padding()
    }
}

struct PremiumLockedView: View {
    let onUnlock: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("Premium Feature")
                .font(.headline)
            
            Text("Upgrade to unlock this feature")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView("Loading...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
        }
        .padding()
    }
}

struct LegalLinksView: View {
    var body: some View {
        HStack {
            Link("Terms", destination: URL(string: "https://yourapp.com/terms")!)
            Text("•")
            Link("Privacy", destination: URL(string: "https://yourapp.com/privacy")!)
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

struct PaywallContent: View {
    let offering: Offering
    let onComplete: () -> Void
    @State private var isPurchasing = false
    
    var body: some View {
        PackageListView(
            offering: offering,
            isPurchasing: $isPurchasing,
            onPurchaseComplete: onComplete
        )
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let customerInfoUpdated = Notification.Name("CustomerInfoUpdated")
}

// MARK: - App Setup (in your App.swift)
//
// import RevenueCat
//
// @main
// struct YourApp: App {
//     init() {
//         Purchases.logLevel = .debug // Remove in production
//         Purchases.configure(withAPIKey: "your_api_key")
//
//         // Listen for customer info updates
//         Purchases.shared.delegate = PurchasesDelegate.shared
//     }
// }
//
// class PurchasesDelegate: NSObject, PurchasesDelegate {
//     static let shared = PurchasesDelegate()
//
//     func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
//         NotificationCenter.default.post(name: .customerInfoUpdated, object: customerInfo)
//     }
// }
