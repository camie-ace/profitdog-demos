/**
 * React Native Subscription Manager
 *
 * A complete subscription state management solution for React Native apps using RevenueCat.
 *
 * @example
 * ```tsx
 * import {
 *   SubscriptionProvider,
 *   useSubscription,
 *   usePurchase,
 *   useOfferings,
 *   PaywallGate,
 * } from './subscription';
 *
 * // Wrap your app
 * function App() {
 *   return (
 *     <SubscriptionProvider apiKey="your_api_key">
 *       <MainApp />
 *     </SubscriptionProvider>
 *   );
 * }
 *
 * // Use hooks anywhere
 * function PremiumFeature() {
 *   const { isPremium, isLoading } = useSubscription();
 *   const { purchase, purchasing } = usePurchase();
 *
 *   if (isLoading) return <LoadingScreen />;
 *   if (!isPremium) {
 *     return (
 *       <Button
 *         title="Upgrade"
 *         onPress={() => purchase('premium_monthly')}
 *         disabled={purchasing}
 *       />
 *     );
 *   }
 *   return <PremiumContent />;
 * }
 * ```
 */

// Provider
export {
  SubscriptionProvider,
  SubscriptionContext,
  useSubscriptionContext,
} from './SubscriptionProvider';

// Hooks
export {
  useSubscription,
  usePurchase,
  useOfferings,
  useEntitlement,
  useExpiration,
} from './hooks';

// Components
export {
  PaywallGate,
  FreeOnlyGate,
  usePaywallGate,
} from './PaywallGate';

// Types
export type {
  SubscriptionState,
  SubscriptionActions,
  SubscriptionContextValue,
  SubscriptionProviderProps,
  UseSubscriptionResult,
  UsePurchaseResult,
  UseOfferingsResult,
  PaywallGateProps,
  FormattedPrice,
} from './types';

// Utilities
export { formatProductPrice } from './types';
