/**
 * React Native Subscription Provider using RevenueCat
 *
 * Provides subscription state management via React Context.
 * Handles SDK initialization, customer info updates, and purchase operations.
 */

import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useReducer,
} from 'react';
import Purchases, {
  CustomerInfo,
  LOG_LEVEL,
  PurchasesOfferings,
  PurchasesPackage,
} from 'react-native-purchases';
import { Platform } from 'react-native';

import type {
  SubscriptionContextValue,
  SubscriptionProviderProps,
  SubscriptionState,
} from './types';

// Action types for the reducer
type SubscriptionAction =
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'SET_CUSTOMER_INFO'; payload: CustomerInfo }
  | { type: 'SET_OFFERINGS'; payload: PurchasesOfferings }
  | { type: 'SET_ERROR'; payload: Error | null }
  | { type: 'SET_PURCHASING'; payload: boolean }
  | { type: 'SET_RESTORING'; payload: boolean }
  | { type: 'RESET_ERROR' };

// Initial state
const initialState: SubscriptionState = {
  isLoading: true,
  customerInfo: null,
  offerings: null,
  error: null,
  isPurchasing: false,
  isRestoring: false,
};

// Reducer
function subscriptionReducer(
  state: SubscriptionState,
  action: SubscriptionAction
): SubscriptionState {
  switch (action.type) {
    case 'SET_LOADING':
      return { ...state, isLoading: action.payload };
    case 'SET_CUSTOMER_INFO':
      return { ...state, customerInfo: action.payload, isLoading: false };
    case 'SET_OFFERINGS':
      return { ...state, offerings: action.payload };
    case 'SET_ERROR':
      return { ...state, error: action.payload, isLoading: false };
    case 'SET_PURCHASING':
      return { ...state, isPurchasing: action.payload };
    case 'SET_RESTORING':
      return { ...state, isRestoring: action.payload };
    case 'RESET_ERROR':
      return { ...state, error: null };
    default:
      return state;
  }
}

// Create context with undefined default
const SubscriptionContext = createContext<SubscriptionContextValue | undefined>(undefined);

/**
 * Subscription Provider Component
 *
 * Wraps your app and provides subscription state to all children.
 *
 * @example
 * ```tsx
 * <SubscriptionProvider
 *   apiKey="your_revenuecat_api_key"
 *   userId={user?.id}
 *   onCustomerInfoUpdate={(info) => analytics.identify(info)}
 *   debug={__DEV__}
 * >
 *   <App />
 * </SubscriptionProvider>
 * ```
 */
export function SubscriptionProvider({
  apiKey,
  userId,
  children,
  onCustomerInfoUpdate,
  debug = false,
}: SubscriptionProviderProps) {
  const [state, dispatch] = useReducer(subscriptionReducer, initialState);

  // Initialize RevenueCat SDK
  useEffect(() => {
    let isMounted = true;

    async function initializeSDK() {
      try {
        // Set log level for debugging
        if (debug) {
          Purchases.setLogLevel(LOG_LEVEL.DEBUG);
        }

        // Configure SDK with platform-specific key if needed
        // You can also pass different keys for iOS/Android
        await Purchases.configure({
          apiKey,
          appUserID: userId || null,
        });

        // Get initial customer info
        const customerInfo = await Purchases.getCustomerInfo();
        if (isMounted) {
          dispatch({ type: 'SET_CUSTOMER_INFO', payload: customerInfo });
          onCustomerInfoUpdate?.(customerInfo);
        }

        // Get offerings
        const offerings = await Purchases.getOfferings();
        if (isMounted) {
          dispatch({ type: 'SET_OFFERINGS', payload: offerings });
        }
      } catch (error) {
        console.error('[RevenueCat] Initialization error:', error);
        if (isMounted) {
          dispatch({ type: 'SET_ERROR', payload: error as Error });
        }
      }
    }

    initializeSDK();

    // Set up customer info listener
    const customerInfoListener = Purchases.addCustomerInfoUpdateListener(
      (customerInfo) => {
        if (isMounted) {
          dispatch({ type: 'SET_CUSTOMER_INFO', payload: customerInfo });
          onCustomerInfoUpdate?.(customerInfo);
        }
      }
    );

    return () => {
      isMounted = false;
      customerInfoListener.remove();
    };
  }, [apiKey, userId, debug, onCustomerInfoUpdate]);

  // Purchase a package
  const purchasePackage = useCallback(
    async (pkg: PurchasesPackage): Promise<CustomerInfo | null> => {
      dispatch({ type: 'SET_PURCHASING', payload: true });
      dispatch({ type: 'RESET_ERROR' });

      try {
        const { customerInfo } = await Purchases.purchasePackage(pkg);
        dispatch({ type: 'SET_CUSTOMER_INFO', payload: customerInfo });
        return customerInfo;
      } catch (error: any) {
        // Check if user cancelled
        if (error.userCancelled) {
          // User cancelled, not an error
          return null;
        }
        console.error('[RevenueCat] Purchase error:', error);
        dispatch({ type: 'SET_ERROR', payload: error });
        return null;
      } finally {
        dispatch({ type: 'SET_PURCHASING', payload: false });
      }
    },
    []
  );

  // Purchase by product ID
  const purchaseProduct = useCallback(
    async (productId: string): Promise<CustomerInfo | null> => {
      dispatch({ type: 'SET_PURCHASING', payload: true });
      dispatch({ type: 'RESET_ERROR' });

      try {
        const { customerInfo } = await Purchases.purchaseStoreProduct(
          // First get the product
          (await Purchases.getProducts([productId]))[0]
        );
        dispatch({ type: 'SET_CUSTOMER_INFO', payload: customerInfo });
        return customerInfo;
      } catch (error: any) {
        if (error.userCancelled) {
          return null;
        }
        console.error('[RevenueCat] Purchase error:', error);
        dispatch({ type: 'SET_ERROR', payload: error });
        return null;
      } finally {
        dispatch({ type: 'SET_PURCHASING', payload: false });
      }
    },
    []
  );

  // Restore purchases
  const restorePurchases = useCallback(async (): Promise<CustomerInfo | null> => {
    dispatch({ type: 'SET_RESTORING', payload: true });
    dispatch({ type: 'RESET_ERROR' });

    try {
      const customerInfo = await Purchases.restorePurchases();
      dispatch({ type: 'SET_CUSTOMER_INFO', payload: customerInfo });
      return customerInfo;
    } catch (error) {
      console.error('[RevenueCat] Restore error:', error);
      dispatch({ type: 'SET_ERROR', payload: error as Error });
      return null;
    } finally {
      dispatch({ type: 'SET_RESTORING', payload: false });
    }
  }, []);

  // Refresh customer info
  const refreshCustomerInfo = useCallback(async (): Promise<void> => {
    try {
      const customerInfo = await Purchases.getCustomerInfo();
      dispatch({ type: 'SET_CUSTOMER_INFO', payload: customerInfo });
    } catch (error) {
      console.error('[RevenueCat] Refresh customer info error:', error);
      dispatch({ type: 'SET_ERROR', payload: error as Error });
    }
  }, []);

  // Refresh offerings
  const refreshOfferings = useCallback(async (): Promise<void> => {
    try {
      const offerings = await Purchases.getOfferings();
      dispatch({ type: 'SET_OFFERINGS', payload: offerings });
    } catch (error) {
      console.error('[RevenueCat] Refresh offerings error:', error);
      dispatch({ type: 'SET_ERROR', payload: error as Error });
    }
  }, []);

  // Check entitlement
  const hasEntitlement = useCallback(
    (entitlementId: string): boolean => {
      if (!state.customerInfo) return false;
      return (
        state.customerInfo.entitlements.active[entitlementId]?.isActive === true
      );
    },
    [state.customerInfo]
  );

  // Memoize context value
  const contextValue = useMemo<SubscriptionContextValue>(
    () => ({
      ...state,
      purchasePackage,
      purchaseProduct,
      restorePurchases,
      refreshCustomerInfo,
      refreshOfferings,
      hasEntitlement,
    }),
    [
      state,
      purchasePackage,
      purchaseProduct,
      restorePurchases,
      refreshCustomerInfo,
      refreshOfferings,
      hasEntitlement,
    ]
  );

  return (
    <SubscriptionContext.Provider value={contextValue}>
      {children}
    </SubscriptionContext.Provider>
  );
}

/**
 * Hook to access the subscription context
 *
 * @throws Error if used outside SubscriptionProvider
 */
export function useSubscriptionContext(): SubscriptionContextValue {
  const context = useContext(SubscriptionContext);
  if (context === undefined) {
    throw new Error(
      'useSubscriptionContext must be used within a SubscriptionProvider'
    );
  }
  return context;
}

export { SubscriptionContext };
