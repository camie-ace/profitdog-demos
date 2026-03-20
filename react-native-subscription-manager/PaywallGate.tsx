/**
 * PaywallGate Component
 *
 * Conditionally renders content based on entitlement status.
 * Shows fallback (typically a paywall or upgrade prompt) when user lacks access.
 */

import React from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useSubscription } from './hooks';
import type { PaywallGateProps } from './types';

/**
 * Gate premium content behind an entitlement check
 *
 * @example
 * ```tsx
 * // Simple usage
 * <PaywallGate
 *   entitlement="premium"
 *   fallback={<UpgradeScreen />}
 * >
 *   <PremiumFeature />
 * </PaywallGate>
 *
 * // With custom loading
 * <PaywallGate
 *   entitlement="pro_features"
 *   fallback={<Paywall />}
 *   loading={<SkeletonLoader />}
 * >
 *   <ProDashboard />
 * </PaywallGate>
 * ```
 */
export function PaywallGate({
  entitlement,
  children,
  fallback,
  loading,
}: PaywallGateProps): React.ReactElement {
  const { hasEntitlement, isLoading } = useSubscription();

  if (isLoading) {
    // Show loading state while checking subscription
    if (loading) {
      return <>{loading}</>;
    }

    // Default loading indicator
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#0066FF" />
      </View>
    );
  }

  // Show premium content if user has entitlement
  if (hasEntitlement(entitlement)) {
    return <>{children}</>;
  }

  // Show fallback (paywall/upgrade prompt) if user lacks entitlement
  return <>{fallback}</>;
}

/**
 * Inverse gate - shows content only to FREE users
 *
 * Useful for showing upgrade prompts or ads only to non-premium users.
 *
 * @example
 * ```tsx
 * <FreeOnlyGate entitlement="premium">
 *   <AdBanner />
 * </FreeOnlyGate>
 * ```
 */
export function FreeOnlyGate({
  entitlement,
  children,
  loading,
}: Omit<PaywallGateProps, 'fallback'>): React.ReactElement | null {
  const { hasEntitlement, isLoading } = useSubscription();

  if (isLoading) {
    if (loading) {
      return <>{loading}</>;
    }
    return null;
  }

  // Only render if user does NOT have the entitlement
  if (!hasEntitlement(entitlement)) {
    return <>{children}</>;
  }

  return null;
}

/**
 * Hook-based alternative for more complex conditional logic
 *
 * @example
 * ```tsx
 * function FeatureScreen() {
 *   const { gatedContent, isUnlocked } = usePaywallGate('pro_features');
 *
 *   if (gatedContent) return gatedContent;
 *
 *   // User has access
 *   return <ProFeature />;
 * }
 * ```
 */
export function usePaywallGate(
  entitlement: string,
  fallback?: React.ReactNode
) {
  const { hasEntitlement, isLoading } = useSubscription();

  const isUnlocked = !isLoading && hasEntitlement(entitlement);

  const gatedContent = isLoading
    ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color="#0066FF" />
        </View>
      )
    : !isUnlocked && fallback
      ? fallback
      : null;

  return {
    isUnlocked,
    isLoading,
    gatedContent,
  };
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
});

export default PaywallGate;
