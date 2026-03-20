/**
 * Custom hooks for RevenueCat subscription management
 *
 * Provides convenient access to subscription state and operations.
 */

import { useCallback, useMemo } from 'react';
import { useSubscriptionContext } from './SubscriptionProvider';
import type {
  UseSubscriptionResult,
  UsePurchaseResult,
  UseOfferingsResult,
} from './types';

/**
 * Hook for accessing subscription state
 *
 * @param premiumEntitlementId - ID of the "premium" entitlement (default: "premium")
 *
 * @example
 * ```tsx
 * const { isPremium, isLoading, hasEntitlement } = useSubscription();
 *
 * if (isLoading) return <Spinner />;
 * if (!isPremium) return <Paywall />;
 * return <PremiumContent />;
 * ```
 */
export function useSubscription(
  premiumEntitlementId: string = 'premium'
): UseSubscriptionResult {
  const { customerInfo, isLoading, hasEntitlement } = useSubscriptionContext();

  const activeEntitlements = useMemo(() => {
    if (!customerInfo) return [];
    return Object.keys(customerInfo.entitlements.active);
  }, [customerInfo]);

  const isSubscribed = useMemo(() => {
    return activeEntitlements.length > 0;
  }, [activeEntitlements]);

  const isPremium = useMemo(() => {
    return hasEntitlement(premiumEntitlementId);
  }, [hasEntitlement, premiumEntitlementId]);

  const getExpirationDate = useCallback(
    (entitlementId: string): Date | null => {
      if (!customerInfo) return null;
      const entitlement = customerInfo.entitlements.active[entitlementId];
      if (!entitlement?.expirationDate) return null;
      return new Date(entitlement.expirationDate);
    },
    [customerInfo]
  );

  const willRenew = useCallback(
    (entitlementId: string): boolean => {
      if (!customerInfo) return false;
      const entitlement = customerInfo.entitlements.active[entitlementId];
      return entitlement?.willRenew ?? false;
    },
    [customerInfo]
  );

  return {
    isSubscribed,
    isPremium,
    isLoading,
    customerInfo,
    hasEntitlement,
    activeEntitlements,
    getExpirationDate,
    willRenew,
  };
}

/**
 * Hook for purchase operations
 *
 * @example
 * ```tsx
 * const { purchase, purchasing, error } = usePurchase();
 *
 * const handlePurchase = async () => {
 *   const success = await purchase('premium_monthly');
 *   if (success) {
 *     navigation.navigate('Welcome');
 *   }
 * };
 * ```
 */
export function usePurchase(): UsePurchaseResult {
  const {
    offerings,
    purchasePackage,
    purchaseProduct,
    restorePurchases,
    isPurchasing,
    isRestoring,
    error,
  } = useSubscriptionContext();

  /**
   * Purchase a package by identifier
   * Looks up the package from current offerings
   */
  const purchase = useCallback(
    async (packageId: string): Promise<boolean> => {
      const pkg = offerings?.current?.availablePackages.find(
        (p) => p.identifier === packageId
      );

      if (!pkg) {
        console.warn(`[usePurchase] Package "${packageId}" not found in offerings`);
        return false;
      }

      const result = await purchasePackage(pkg);
      return result !== null;
    },
    [offerings, purchasePackage]
  );

  /**
   * Purchase a product by product ID
   */
  const purchaseProductById = useCallback(
    async (productId: string): Promise<boolean> => {
      const result = await purchaseProduct(productId);
      return result !== null;
    },
    [purchaseProduct]
  );

  /**
   * Restore previous purchases
   */
  const restore = useCallback(async (): Promise<boolean> => {
    const result = await restorePurchases();
    return result !== null;
  }, [restorePurchases]);

  return {
    purchase,
    purchaseProduct: purchaseProductById,
    restore,
    purchasing: isPurchasing,
    restoring: isRestoring,
    error,
  };
}

/**
 * Hook for accessing offerings
 *
 * @example
 * ```tsx
 * const { packages, getPackage, loading } = useOfferings();
 *
 * return (
 *   <View>
 *     {packages.map(pkg => (
 *       <PackageCard key={pkg.identifier} package={pkg} />
 *     ))}
 *   </View>
 * );
 * ```
 */
export function useOfferings(): UseOfferingsResult {
  const { offerings, isLoading, refreshOfferings } = useSubscriptionContext();

  const currentOffering = offerings?.current ?? null;

  const packages = useMemo(() => {
    return currentOffering?.availablePackages ?? [];
  }, [currentOffering]);

  const getPackage = useCallback(
    (identifier: string) => {
      return packages.find((pkg) => pkg.identifier === identifier);
    },
    [packages]
  );

  return {
    offerings,
    currentOffering,
    packages,
    getPackage,
    loading: isLoading,
    refresh: refreshOfferings,
  };
}

/**
 * Hook to check a specific entitlement
 *
 * @param entitlementId - The entitlement ID to check
 *
 * @example
 * ```tsx
 * const hasPro = useEntitlement('pro_features');
 *
 * return hasPro ? <ProFeature /> : <UpgradeButton />;
 * ```
 */
export function useEntitlement(entitlementId: string): boolean {
  const { hasEntitlement, isLoading } = useSubscriptionContext();

  // Return false while loading to prevent flash of premium content
  if (isLoading) return false;

  return hasEntitlement(entitlementId);
}

/**
 * Hook to get subscription expiration info
 *
 * @param entitlementId - The entitlement ID to check
 *
 * @example
 * ```tsx
 * const { expiresAt, daysRemaining, willRenew } = useExpiration('premium');
 *
 * if (!willRenew && daysRemaining <= 3) {
 *   return <RenewalReminder days={daysRemaining} />;
 * }
 * ```
 */
export function useExpiration(entitlementId: string) {
  const { customerInfo, isLoading } = useSubscriptionContext();

  return useMemo(() => {
    if (isLoading || !customerInfo) {
      return {
        expiresAt: null,
        daysRemaining: null,
        willRenew: false,
        isExpired: false,
      };
    }

    const entitlement = customerInfo.entitlements.active[entitlementId];
    if (!entitlement?.expirationDate) {
      return {
        expiresAt: null,
        daysRemaining: null,
        willRenew: false,
        isExpired: !entitlement,
      };
    }

    const expiresAt = new Date(entitlement.expirationDate);
    const now = new Date();
    const msRemaining = expiresAt.getTime() - now.getTime();
    const daysRemaining = Math.max(0, Math.ceil(msRemaining / (1000 * 60 * 60 * 24)));

    return {
      expiresAt,
      daysRemaining,
      willRenew: entitlement.willRenew ?? false,
      isExpired: msRemaining <= 0,
    };
  }, [customerInfo, entitlementId, isLoading]);
}
