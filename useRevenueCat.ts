import { useState, useEffect, useCallback } from 'react';
import { Platform } from 'react-native';
import Purchases, {
  CustomerInfo,
  PurchasesPackage,
  LOG_LEVEL,
} from 'react-native-purchases';

// Replace with your RevenueCat API keys
const API_KEYS = {
  apple: 'appl_your_apple_api_key_here',
  google: 'goog_your_google_api_key_here',
};

// Replace with your specific entitlement identifier
const ENTITLEMENT_ID = 'pro';

interface RevenueCatState {
  customerInfo: CustomerInfo | null;
  isPro: boolean;
  isLoading: boolean;
  error: Error | null;
}

/**
 * Custom hook for React Native / Expo to manage RevenueCat subscriptions.
 * 
 * Features:
 * - Auto-initialization based on platform
 * - Syncs customer info automatically via listeners
 * - Exposes easy-to-use purchase and restore functions
 * - Loading and error states built-in
 * 
 * Usage:
 * const { isPro, purchasePackage, restorePurchases } = useRevenueCat('my_user_id');
 */
export const useRevenueCat = (appUserId?: string) => {
  const [state, setState] = useState<RevenueCatState>({
    customerInfo: null,
    isPro: false,
    isLoading: true,
    error: null,
  });

  // Initialize RevenueCat
  useEffect(() => {
    const init = async () => {
      try {
        Purchases.setLogLevel(LOG_LEVEL.DEBUG);

        if (Platform.OS === 'ios') {
          Purchases.configure({ apiKey: API_KEYS.apple, appUserID: appUserId });
        } else if (Platform.OS === 'android') {
          Purchases.configure({ apiKey: API_KEYS.google, appUserID: appUserId });
        }

        const initialCustomerInfo = await Purchases.getCustomerInfo();
        updateCustomerInfo(initialCustomerInfo);
      } catch (e) {
        setState((s) => ({ ...s, error: e as Error, isLoading: false }));
      }
    };

    init();
  }, [appUserId]);

  // Listen for customer info updates (e.g., from another device or background renewal)
  useEffect(() => {
    const listener = (info: CustomerInfo) => {
      updateCustomerInfo(info);
    };

    Purchases.addCustomerInfoUpdateListener(listener);
    return () => {
      Purchases.removeCustomerInfoUpdateListener(listener);
    };
  }, []);

  const updateCustomerInfo = (info: CustomerInfo) => {
    const isPro = typeof info.entitlements.active[ENTITLEMENT_ID] !== 'undefined';
    setState({
      customerInfo: info,
      isPro,
      isLoading: false,
      error: null,
    });
  };

  /**
   * Purchase a specific package from an offering.
   */
  const purchasePackage = useCallback(async (pack: PurchasesPackage) => {
    setState((s) => ({ ...s, isLoading: true, error: null }));
    try {
      const { customerInfo } = await Purchases.purchasePackage(pack);
      updateCustomerInfo(customerInfo);
      return true;
    } catch (e: any) {
      if (!e.userCancelled) {
        setState((s) => ({ ...s, error: e as Error, isLoading: false }));
      } else {
        setState((s) => ({ ...s, isLoading: false }));
      }
      return false;
    }
  }, []);

  /**
   * Restore previous purchases.
   */
  const restorePurchases = useCallback(async () => {
    setState((s) => ({ ...s, isLoading: true, error: null }));
    try {
      const customerInfo = await Purchases.restorePurchases();
      updateCustomerInfo(customerInfo);
      return true;
    } catch (e: any) {
      setState((s) => ({ ...s, error: e as Error, isLoading: false }));
      return false;
    }
  }, []);

  return {
    ...state,
    purchasePackage,
    restorePurchases,
  };
};

export default useRevenueCat;
