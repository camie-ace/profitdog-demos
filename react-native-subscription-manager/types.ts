/**
 * Type definitions for React Native RevenueCat subscription management
 */

import type {
  CustomerInfo,
  PurchasesOfferings,
  PurchasesPackage,
  PurchasesStoreProduct,
} from 'react-native-purchases';

/**
 * Subscription state managed by the context
 */
export interface SubscriptionState {
  /** Whether the initial load is in progress */
  isLoading: boolean;
  /** Current customer info from RevenueCat */
  customerInfo: CustomerInfo | null;
  /** Available offerings */
  offerings: PurchasesOfferings | null;
  /** Error from the last operation */
  error: Error | null;
  /** Whether a purchase is currently in progress */
  isPurchasing: boolean;
  /** Whether a restore is currently in progress */
  isRestoring: boolean;
}

/**
 * Actions available from the subscription context
 */
export interface SubscriptionActions {
  /** Purchase a package */
  purchasePackage: (pkg: PurchasesPackage) => Promise<CustomerInfo | null>;
  /** Purchase by product ID */
  purchaseProduct: (productId: string) => Promise<CustomerInfo | null>;
  /** Restore previous purchases */
  restorePurchases: () => Promise<CustomerInfo | null>;
  /** Refresh customer info */
  refreshCustomerInfo: () => Promise<void>;
  /** Refresh offerings */
  refreshOfferings: () => Promise<void>;
  /** Check if user has a specific entitlement */
  hasEntitlement: (entitlementId: string) => boolean;
}

/**
 * Combined context value
 */
export interface SubscriptionContextValue extends SubscriptionState, SubscriptionActions {}

/**
 * Props for the subscription provider
 */
export interface SubscriptionProviderProps {
  /** RevenueCat API key */
  apiKey: string;
  /** Optional user ID for identification */
  userId?: string;
  /** Children to render */
  children: React.ReactNode;
  /** Called when customer info updates */
  onCustomerInfoUpdate?: (customerInfo: CustomerInfo) => void;
  /** Enable debug logging */
  debug?: boolean;
}

/**
 * Result from the useSubscription hook
 */
export interface UseSubscriptionResult {
  /** Whether any active subscription exists */
  isSubscribed: boolean;
  /** Whether user has premium entitlement (customize entitlement ID as needed) */
  isPremium: boolean;
  /** Whether initial load is in progress */
  isLoading: boolean;
  /** Current customer info */
  customerInfo: CustomerInfo | null;
  /** Check for specific entitlement */
  hasEntitlement: (entitlementId: string) => boolean;
  /** Active entitlement IDs */
  activeEntitlements: string[];
  /** Expiration date for an entitlement */
  getExpirationDate: (entitlementId: string) => Date | null;
  /** Whether an entitlement will renew */
  willRenew: (entitlementId: string) => boolean;
}

/**
 * Result from the usePurchase hook
 */
export interface UsePurchaseResult {
  /** Purchase a package */
  purchase: (packageId: string) => Promise<boolean>;
  /** Purchase a product directly */
  purchaseProduct: (productId: string) => Promise<boolean>;
  /** Restore previous purchases */
  restore: () => Promise<boolean>;
  /** Whether a purchase is in progress */
  purchasing: boolean;
  /** Whether a restore is in progress */
  restoring: boolean;
  /** Last error */
  error: Error | null;
}

/**
 * Result from the useOfferings hook
 */
export interface UseOfferingsResult {
  /** All available offerings */
  offerings: PurchasesOfferings | null;
  /** Current offering */
  currentOffering: PurchasesOfferings['current'];
  /** All available packages from current offering */
  packages: PurchasesPackage[];
  /** Get a specific package by identifier */
  getPackage: (identifier: string) => PurchasesPackage | undefined;
  /** Whether offerings are loading */
  loading: boolean;
  /** Refresh offerings */
  refresh: () => Promise<void>;
}

/**
 * Props for the PaywallGate component
 */
export interface PaywallGateProps {
  /** Entitlement ID to check */
  entitlement: string;
  /** Content to show if user has entitlement */
  children: React.ReactNode;
  /** Content to show if user doesn't have entitlement */
  fallback: React.ReactNode;
  /** Content to show while loading */
  loading?: React.ReactNode;
}

/**
 * Helper type for formatted price display
 */
export interface FormattedPrice {
  /** Full price string (e.g., "$9.99") */
  price: string;
  /** Price per period (e.g., "$9.99/month") */
  pricePerPeriod: string;
  /** Currency code */
  currencyCode: string;
  /** Raw price in micros */
  priceAmountMicros: number;
}

/**
 * Extract formatted price from a product
 */
export function formatProductPrice(product: PurchasesStoreProduct): FormattedPrice {
  return {
    price: product.priceString,
    pricePerPeriod: `${product.priceString}/${getSubscriptionPeriodLabel(product)}`,
    currencyCode: product.currencyCode,
    priceAmountMicros: Math.round(product.price * 1_000_000),
  };
}

/**
 * Get human-readable subscription period
 */
function getSubscriptionPeriodLabel(product: PurchasesStoreProduct): string {
  const period = product.subscriptionPeriod;
  if (!period) return '';

  const { unit, value } = period;
  
  if (value === 1) {
    switch (unit) {
      case 'DAY': return 'day';
      case 'WEEK': return 'week';
      case 'MONTH': return 'month';
      case 'YEAR': return 'year';
      default: return '';
    }
  }
  
  switch (unit) {
    case 'DAY': return `${value} days`;
    case 'WEEK': return `${value} weeks`;
    case 'MONTH': return `${value} months`;
    case 'YEAR': return `${value} years`;
    default: return '';
  }
}
