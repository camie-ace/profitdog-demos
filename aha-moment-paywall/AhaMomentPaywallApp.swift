import SwiftUI
import RevenueCat

@main
struct AhaMomentPaywallApp: App {
    
    init() {
        // Configure RevenueCat on app launch
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "YOUR_REVENUECAT_API_KEY")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(PaywallManager.shared)
        }
    }
}
