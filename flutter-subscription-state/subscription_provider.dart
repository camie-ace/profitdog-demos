/// Riverpod provider for reactive subscription state management
/// 
/// Automatically updates when RevenueCat CustomerInfo changes.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'subscription_state.dart';

/// Main subscription state provider
/// 
/// Usage:
/// ```dart
/// final state = ref.watch(subscriptionProvider);
/// if (state.hasAccess) { ... }
/// ```
final subscriptionProvider = StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});

/// Derived provider for quick access check
final hasAccessProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider).hasAccess;
});

/// Derived provider for payment issue detection
final hasPaymentIssueProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider).hasPaymentIssue;
});

/// Derived provider for current tier (null if no subscription)
final currentTierProvider = Provider<String?>((ref) {
  return ref.watch(subscriptionProvider).tier;
});


class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  StreamSubscription<CustomerInfo>? _subscription;
  
  SubscriptionNotifier() : super(const SubscriptionNone()) {
    _initialize();
  }
  
  Future<void> _initialize() async {
    // Get initial state
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      state = SubscriptionState.fromCustomerInfo(customerInfo);
    } catch (e) {
      // Handle error - keep as SubscriptionNone
      print('Error fetching initial customer info: $e');
    }
    
    // Listen for updates
    _subscription = Purchases.customerInfoStream.listen((customerInfo) {
      state = SubscriptionState.fromCustomerInfo(customerInfo);
    });
  }
  
  /// Force refresh subscription state
  Future<void> refresh() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      state = SubscriptionState.fromCustomerInfo(customerInfo);
    } catch (e) {
      print('Error refreshing customer info: $e');
    }
  }
  
  /// Restore purchases and update state
  Future<RestoreResult> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      final newState = SubscriptionState.fromCustomerInfo(customerInfo);
      state = newState;
      
      return RestoreResult(
        success: true,
        hasAccess: newState.hasAccess,
        state: newState,
      );
    } catch (e) {
      return RestoreResult(
        success: false,
        hasAccess: false,
        error: e.toString(),
      );
    }
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}


/// Result of a restore operation
class RestoreResult {
  final bool success;
  final bool hasAccess;
  final SubscriptionState? state;
  final String? error;
  
  const RestoreResult({
    required this.success,
    required this.hasAccess,
    this.state,
    this.error,
  });
}


/// Provider for available packages (offerings)
final packagesProvider = FutureProvider<List<Package>>((ref) async {
  try {
    final offerings = await Purchases.getOfferings();
    return offerings.current?.availablePackages ?? [];
  } catch (e) {
    print('Error fetching offerings: $e');
    return [];
  }
});

/// Purchase a package and return the new subscription state
Future<PurchaseResult> purchasePackage(Package package, WidgetRef ref) async {
  try {
    final customerInfo = await Purchases.purchasePackage(package);
    final newState = SubscriptionState.fromCustomerInfo(customerInfo);
    
    // Force refresh the provider
    ref.read(subscriptionProvider.notifier).refresh();
    
    return PurchaseResult(
      success: true,
      state: newState,
    );
  } on PurchasesErrorCode catch (e) {
    if (e == PurchasesErrorCode.purchaseCancelledError) {
      return const PurchaseResult(
        success: false,
        cancelled: true,
      );
    }
    return PurchaseResult(
      success: false,
      error: e.toString(),
    );
  } catch (e) {
    return PurchaseResult(
      success: false,
      error: e.toString(),
    );
  }
}

/// Result of a purchase operation  
class PurchaseResult {
  final bool success;
  final bool cancelled;
  final SubscriptionState? state;
  final String? error;
  
  const PurchaseResult({
    required this.success,
    this.cancelled = false,
    this.state,
    this.error,
  });
}
