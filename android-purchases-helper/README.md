# Android Purchases Helper

A coroutine-friendly Kotlin wrapper around the RevenueCat Android SDK.

## Features

- **Suspend functions** for all async operations (purchases, restores, offerings)
- **StateFlow** for reactive customer info updates
- **Clean error handling** with sealed Result types
- **Entitlement utilities** including billing issue & grace period detection
- **Jetpack Compose ready** with Flow-based state

## Quick Start

### 1. Initialize in Application

```kotlin
class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        RevenueCatHelper.configure(
            application = this,
            apiKey = "goog_your_api_key_here"
        )
    }
}
```

### 2. Check Premium Status

```kotlin
// Instant check (cached)
if (RevenueCatHelper.hasPremium()) {
    showPremiumContent()
}

// Reactive (in Compose)
val isPremium by RevenueCatHelper.isPremium.collectAsState(initial = false)
```

### 3. Display Paywall & Purchase

```kotlin
// In ViewModel
fun loadPackages() = viewModelScope.launch {
    val packages = RevenueCatHelper.getCurrentOffering()?.availablePackages
    _packages.value = packages ?: emptyList()
}

fun purchase(activity: Activity, pkg: Package) = viewModelScope.launch {
    RevenueCatHelper.purchase(activity, pkg)
        .onSuccess { /* Purchased! */ }
        .onFailure { error ->
            when (error) {
                is PurchaseCancelledException -> { /* User cancelled */ }
                is RevenueCatException -> { /* Show error.message */ }
            }
        }
}
```

### 4. Handle Billing Issues

```kotlin
val details = RevenueCatHelper.getPremiumInfo()
when {
    details?.billingIssue == true -> showBillingWarning()
    details?.inGracePeriod == true -> showGracePeriodNotice()
    details?.isActive == true -> enablePremium()
}
```

## API Reference

| Function | Description |
|----------|-------------|
| `configure()` | Initialize SDK (call once in Application) |
| `hasPremium()` | Instant entitlement check (cached) |
| `hasEntitlement(id)` | Check any entitlement by ID |
| `getPremiumInfo()` | Detailed entitlement info for UI |
| `getOfferings()` | Fetch available offerings |
| `getCurrentOffering()` | Get current/default offering |
| `purchase(activity, pkg)` | Purchase a package |
| `restorePurchases()` | Restore previous purchases |
| `logIn(userId)` | Identify user for cross-device sync |
| `logOut()` | Reset to anonymous user |
| `refreshCustomerInfo()` | Force refresh from server |

## Flows

| Flow | Type | Description |
|------|------|-------------|
| `customerInfo` | `StateFlow<CustomerInfo?>` | Emits on every subscription change |
| `isPremium` | `Flow<Boolean>` | Convenience flow for premium status |

## Dependencies

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.revenuecat.purchases:purchases:8.+")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.+")
}
```

## Notes

- Uses `goog_` API key (Android/Google Play)
- StateFlow ensures UI always has latest subscription state
- Suspend functions integrate cleanly with `viewModelScope`
- Grace period detection helps you handle payment issues gracefully

---

Created by ProfitDog 🐕
