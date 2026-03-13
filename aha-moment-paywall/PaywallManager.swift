import Foundation
import RevenueCat
import SwiftUI

/// Manages the "Aha Moment" paywall strategy
/// 
/// The key insight: Don't show the paywall immediately.
/// Wait for the user to experience value first.
@MainActor
class PaywallManager: ObservableObject {
    static let shared = PaywallManager()
    
    // MARK: - Published State
    
    @Published var hasCompletedAhaMoment = false
    @Published var shouldShowPaywall = false
    @Published var isPremium = false
    @Published var currentOffering: Offering?
    
    // MARK: - Configuration
    
    /// Number of "aha moments" before showing paywall
    /// Duolingo waits for 1 lesson. You might want more.
    private let ahaMomentsRequired = 1
    
    /// Track how many aha moments the user has had
    @AppStorage("ahaMomentCount") private var ahaMomentCount = 0
    
    // MARK: - Initialization
    
    private init() {
        Task {
            await checkSubscriptionStatus()
            await fetchOfferings()
        }
    }
    
    // MARK: - The Core Pattern
    
    /// Call this when the user completes a valuable action
    /// Examples: finishes a lesson, completes a workout, creates their first note
    func trackAhaMoment() {
        ahaMomentCount += 1
        hasCompletedAhaMoment = true
        
        // Only show paywall if:
        // 1. User has hit enough aha moments
        // 2. User is not already premium
        if ahaMomentCount >= ahaMomentsRequired && !isPremium {
            // Small delay for better UX - let them savor the win first
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                shouldShowPaywall = true
            }
        }
        
        // Track the event in RevenueCat for analytics
        Purchases.shared.attribution.setAttributes([
            "aha_moment_count": "\(ahaMomentCount)",
            "first_aha_moment_date": hasCompletedAhaMoment ? ISO8601DateFormatter().string(from: Date()) : ""
        ])
    }
    
    /// Reset after paywall is dismissed (whether purchased or not)
    func paywallDismissed() {
        shouldShowPaywall = false
    }
    
    // MARK: - RevenueCat Integration
    
    func checkSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            isPremium = customerInfo.entitlements["premium"]?.isActive == true
        } catch {
            print("Error checking subscription: \(error)")
        }
    }
    
    func fetchOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            // Use a specific "aha_moment" offering if configured,
            // otherwise fall back to current
            currentOffering = offerings.offering(identifier: "aha_moment") ?? offerings.current
        } catch {
            print("Error fetching offerings: \(error)")
        }
    }
    
    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        isPremium = result.customerInfo.entitlements["premium"]?.isActive == true
        shouldShowPaywall = false
    }
    
    func restorePurchases() async throws {
        let customerInfo = try await Purchases.shared.restorePurchases()
        isPremium = customerInfo.entitlements["premium"]?.isActive == true
    }
}

// MARK: - Paywall Placement Helpers

extension PaywallManager {
    /// Different paywall contexts for A/B testing
    enum PaywallContext: String {
        case ahaMoment = "aha_moment"      // After completing valuable action
        case featureGate = "feature_gate"   // When hitting a premium feature
        case settings = "settings"          // From settings/upgrade button
        case onboarding = "onboarding"      // During onboarding (not recommended!)
    }
    
    /// Track which context triggered the paywall
    func showPaywall(context: PaywallContext) {
        Purchases.shared.attribution.setAttributes([
            "last_paywall_context": context.rawValue
        ])
        shouldShowPaywall = true
    }
}
