# React Native Subscription Manager

A complete subscription state management solution for React Native apps using RevenueCat.

## Features

- 🔄 Real-time subscription state with React Context
- 🎣 Custom hooks for easy access (`useSubscription`, `usePurchase`, `useOfferings`)
- 🔒 Type-safe with full TypeScript support
- ⚡ Automatic listener setup/cleanup
- 🛡️ Entitlement checking utilities
- 📦 Works with React Navigation for paywall gating

## Installation

```bash
npm install react-native-purchases
# or
yarn add react-native-purchases
```

Then copy the files from this example into your project.

## Quick Start

1. Wrap your app with the provider:

```tsx
import { SubscriptionProvider } from './subscription/SubscriptionProvider';

export default function App() {
  return (
    <SubscriptionProvider apiKey="your_revenuecat_api_key">
      <YourApp />
    </SubscriptionProvider>
  );
}
```

2. Use the hooks anywhere:

```tsx
import { useSubscription, usePurchase } from './subscription/hooks';

function PaywallScreen() {
  const { isPremium, isLoading } = useSubscription();
  const { purchase, purchasing } = usePurchase();

  if (isLoading) return <LoadingSpinner />;
  if (isPremium) return <PremiumContent />;

  return (
    <Button
      title={purchasing ? 'Processing...' : 'Upgrade to Premium'}
      onPress={() => purchase('premium_monthly')}
      disabled={purchasing}
    />
  );
}
```

## Files

- `SubscriptionProvider.tsx` - Context provider with RevenueCat setup
- `hooks.ts` - Custom hooks for subscription state and purchases
- `types.ts` - TypeScript type definitions
- `PaywallGate.tsx` - Component for gating premium content

## Usage Patterns

### Check Entitlement

```tsx
const { hasEntitlement } = useSubscription();

if (hasEntitlement('pro_features')) {
  // Show pro features
}
```

### Get Available Packages

```tsx
const { offerings, loading } = useOfferings();

if (!loading && offerings?.current) {
  offerings.current.availablePackages.map(pkg => (
    <PackageCard key={pkg.identifier} package={pkg} />
  ));
}
```

### Gate Content

```tsx
<PaywallGate entitlement="premium" fallback={<UpgradePrompt />}>
  <PremiumFeature />
</PaywallGate>
```

## Best Practices

1. **Initialize early** - Set up the provider at app root
2. **Handle loading states** - Always show UI feedback during purchases
3. **Cache customer info** - The SDK handles this, but respect the state
4. **Test with sandbox** - Use RevenueCat's sandbox environment during development

## Resources

- [RevenueCat React Native SDK Docs](https://docs.revenuecat.com/docs/reactnative)
- [RevenueCat Entitlements Guide](https://docs.revenuecat.com/docs/entitlements)
- [Testing Purchases](https://docs.revenuecat.com/docs/sandbox-purchases)

---

Built with 🐕 by [ProfitDog](https://github.com/camie-ace/profitdog-demos)
