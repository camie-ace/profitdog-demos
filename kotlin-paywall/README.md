# Kotlin Android Paywall Implementation

A modern Kotlin implementation of a subscription paywall using RevenueCat with Jetpack Compose.

## Features

- 🎨 Jetpack Compose UI with Material 3 theming
- 🔄 Reactive state management with StateFlow
- 💳 Multiple package display (monthly, annual, lifetime)
- ✨ Free trial badge highlighting
- 🎯 A/B testing ready with offering metadata
- 📊 Purchase analytics integration
- ⚠️ Comprehensive error handling

## Quick Start

```kotlin
// In your Activity or Fragment
val viewModel: PaywallViewModel by viewModels()
PaywallScreen(viewModel = viewModel)
```

## Files

- `PaywallViewModel.kt` - ViewModel with RevenueCat integration
- `PaywallScreen.kt` - Compose UI components
- `PaywallState.kt` - State models and sealed classes

## Requirements

- RevenueCat SDK 7.x+
- Kotlin 1.9+
- Jetpack Compose 1.5+
- Material 3

## Installation

Add RevenueCat to your `build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.revenuecat.purchases:purchases:7.+")
    implementation("com.revenuecat.purchases:purchases-ui:7.+")
}
```

## Usage

### Basic Implementation

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Initialize RevenueCat in Application class
        setContent {
            val viewModel: PaywallViewModel = viewModel()
            PaywallScreen(viewModel = viewModel)
        }
    }
}
```

### Handling Purchase Results

```kotlin
viewModel.purchaseResult.collect { result ->
    when (result) {
        is PurchaseResult.Success -> navigateToContent()
        is PurchaseResult.Cancelled -> showMessage("Purchase cancelled")
        is PurchaseResult.Error -> showError(result.message)
    }
}
```

## Pro Tips

1. **Always show the best value first** — Annual plans typically convert better
2. **Highlight savings** — Show monthly equivalent price for annual plans
3. **Use free trials** — They significantly increase conversion rates
4. **Test your paywall** — Use RevenueCat's A/B testing with `offering.metadata`

---

*Built with 🐕 by ProfitDog for the RevenueCat community*
