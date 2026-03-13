# Flutter Subscription State Machine

A robust pattern for managing subscription states in Flutter apps using RevenueCat.

## Why This Pattern?

Subscription state is more complex than `active` vs `inactive`. Users can be:
- In a free trial
- On a grace period (payment failed, still has access)
- In billing retry (payment failing, limited access window)
- Expired but eligible for win-back offers
- Paused (Google Play feature)

This state machine handles all these cases cleanly.

## Features

- **Type-safe state handling** via sealed classes
- **Reactive updates** with Riverpod
- **Grace period detection** for better UX during payment issues
- **Trial tracking** with days remaining
- **Win-back detection** for recently churned users

## Files

- `subscription_state.dart` - State definitions and machine logic
- `subscription_provider.dart` - Riverpod provider with RevenueCat integration
- `subscription_gate.dart` - Widget for gating premium content

## Quick Start

```dart
// Check subscription anywhere
final state = ref.watch(subscriptionProvider);

switch (state) {
  case SubscriptionActive(:final tier):
    return PremiumContent(tier: tier);
  case SubscriptionTrial(:final daysLeft):
    return TrialBanner(daysLeft: daysLeft);
  case SubscriptionGracePeriod():
    return PaymentIssueWarning();
  case SubscriptionExpired(:final isWinbackEligible):
    return isWinbackEligible ? WinbackOffer() : Paywall();
  case SubscriptionNone():
    return Paywall();
}
```

## Dependencies

```yaml
dependencies:
  purchases_flutter: ^6.0.0
  flutter_riverpod: ^2.4.0
```

## License

MIT - Use freely in your RevenueCat-powered apps.
