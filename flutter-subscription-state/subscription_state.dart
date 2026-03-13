/// Subscription State Machine for RevenueCat + Flutter
/// 
/// Handles the full complexity of subscription states including trials,
/// grace periods, billing retry, paused subscriptions, and win-back eligibility.
library;

import 'package:purchases_flutter/purchases_flutter.dart';

/// Sealed class representing all possible subscription states.
/// Using Dart 3 sealed classes for exhaustive pattern matching.
sealed class SubscriptionState {
  const SubscriptionState();
  
  /// Parse CustomerInfo into the appropriate state
  factory SubscriptionState.fromCustomerInfo(CustomerInfo info) {
    return SubscriptionStateMachine.evaluate(info);
  }
  
  /// Quick check if user has premium access (includes trial and grace period)
  bool get hasAccess => switch (this) {
    SubscriptionActive() => true,
    SubscriptionTrial() => true,
    SubscriptionGracePeriod() => true,
    SubscriptionBillingRetry() => true, // Still has access during retry
    SubscriptionPaused() => false,
    SubscriptionExpired() => false,
    SubscriptionNone() => false,
  };
  
  /// Check if we should show payment issue warnings
  bool get hasPaymentIssue => switch (this) {
    SubscriptionGracePeriod() => true,
    SubscriptionBillingRetry() => true,
    _ => false,
  };
}

/// Active paid subscription
final class SubscriptionActive extends SubscriptionState {
  final String tier; // e.g., "pro", "premium", "business"
  final String productId;
  final DateTime expirationDate;
  final bool willRenew;
  
  const SubscriptionActive({
    required this.tier,
    required this.productId,
    required this.expirationDate,
    required this.willRenew,
  });
  
  /// Days until renewal/expiration
  int get daysUntilExpiration => 
    expirationDate.difference(DateTime.now()).inDays;
}

/// User is in a free trial
final class SubscriptionTrial extends SubscriptionState {
  final String tier;
  final String productId;
  final DateTime trialEndDate;
  
  const SubscriptionTrial({
    required this.tier,
    required this.productId,
    required this.trialEndDate,
  });
  
  int get daysLeft => trialEndDate.difference(DateTime.now()).inDays;
  bool get isLastDay => daysLeft <= 1;
}

/// Payment failed but user still has access (Apple/Google grace period)
final class SubscriptionGracePeriod extends SubscriptionState {
  final String tier;
  final DateTime gracePeriodEndDate;
  
  const SubscriptionGracePeriod({
    required this.tier,
    required this.gracePeriodEndDate,
  });
  
  int get daysLeft => gracePeriodEndDate.difference(DateTime.now()).inDays;
}

/// Active billing retry - payment is failing, access may end soon
final class SubscriptionBillingRetry extends SubscriptionState {
  final String tier;
  final DateTime? expectedResolutionDate;
  
  const SubscriptionBillingRetry({
    required this.tier,
    this.expectedResolutionDate,
  });
}

/// Subscription paused (Google Play feature)
final class SubscriptionPaused extends SubscriptionState {
  final String tier;
  final DateTime? resumeDate;
  
  const SubscriptionPaused({
    required this.tier,
    this.resumeDate,
  });
}

/// Subscription expired - user no longer has access
final class SubscriptionExpired extends SubscriptionState {
  final String? lastTier;
  final DateTime expirationDate;
  final Duration timeSinceExpiration;
  
  const SubscriptionExpired({
    this.lastTier,
    required this.expirationDate,
    required this.timeSinceExpiration,
  });
  
  /// Users who expired within 30 days are good win-back candidates
  bool get isWinbackEligible => timeSinceExpiration.inDays <= 30;
  
  /// Users who expired within 7 days might just need a payment reminder
  bool get isRecentlyExpired => timeSinceExpiration.inDays <= 7;
}

/// Never subscribed
final class SubscriptionNone extends SubscriptionState {
  const SubscriptionNone();
}


/// State machine that evaluates CustomerInfo and returns the correct state
class SubscriptionStateMachine {
  // Map entitlement IDs to tier names
  static const _entitlementToTier = {
    'pro': 'pro',
    'premium': 'premium', 
    'pro_access': 'pro',
    'premium_access': 'premium',
    // Add your entitlement IDs here
  };
  
  static SubscriptionState evaluate(CustomerInfo info) {
    // Check all active entitlements
    final activeEntitlements = info.entitlements.active;
    
    if (activeEntitlements.isEmpty) {
      return _evaluateInactiveState(info);
    }
    
    // Get the primary entitlement (first active one)
    final primaryEntitlement = activeEntitlements.values.first;
    final tier = _entitlementToTier[primaryEntitlement.identifier] ?? 
                 primaryEntitlement.identifier;
    
    // Check for trial
    if (primaryEntitlement.periodType == PeriodType.trial) {
      return SubscriptionTrial(
        tier: tier,
        productId: primaryEntitlement.productIdentifier,
        trialEndDate: primaryEntitlement.expirationDate != null 
          ? DateTime.parse(primaryEntitlement.expirationDate!)
          : DateTime.now().add(const Duration(days: 7)),
      );
    }
    
    // Check for grace period
    if (primaryEntitlement.billingIssueDetectedAt != null) {
      final gracePeriodEnd = primaryEntitlement.expirationDate != null
        ? DateTime.parse(primaryEntitlement.expirationDate!)
        : DateTime.now().add(const Duration(days: 16)); // Default grace period
      
      // If expiration is in the future, they're in grace period
      if (gracePeriodEnd.isAfter(DateTime.now())) {
        return SubscriptionGracePeriod(
          tier: tier,
          gracePeriodEndDate: gracePeriodEnd,
        );
      } else {
        // Past expiration but still active = billing retry
        return SubscriptionBillingRetry(tier: tier);
      }
    }
    
    // Normal active subscription
    final expirationDate = primaryEntitlement.expirationDate != null
      ? DateTime.parse(primaryEntitlement.expirationDate!)
      : DateTime.now().add(const Duration(days: 30));
    
    return SubscriptionActive(
      tier: tier,
      productId: primaryEntitlement.productIdentifier,
      expirationDate: expirationDate,
      willRenew: primaryEntitlement.willRenew,
    );
  }
  
  static SubscriptionState _evaluateInactiveState(CustomerInfo info) {
    // Check all entitlements (including inactive) for history
    final allEntitlements = info.entitlements.all;
    
    if (allEntitlements.isEmpty) {
      return const SubscriptionNone();
    }
    
    // Find the most recently expired entitlement
    EntitlementInfo? mostRecent;
    DateTime? mostRecentExpiration;
    
    for (final entitlement in allEntitlements.values) {
      if (entitlement.expirationDate != null) {
        final expDate = DateTime.parse(entitlement.expirationDate!);
        if (mostRecentExpiration == null || expDate.isAfter(mostRecentExpiration)) {
          mostRecentExpiration = expDate;
          mostRecent = entitlement;
        }
      }
    }
    
    if (mostRecent != null && mostRecentExpiration != null) {
      final tier = _entitlementToTier[mostRecent.identifier] ?? 
                   mostRecent.identifier;
      
      return SubscriptionExpired(
        lastTier: tier,
        expirationDate: mostRecentExpiration,
        timeSinceExpiration: DateTime.now().difference(mostRecentExpiration),
      );
    }
    
    return const SubscriptionNone();
  }
}


/// Extension for easy state checking in widgets
extension SubscriptionStateX on SubscriptionState {
  /// Get a user-friendly status string
  String get statusText => switch (this) {
    SubscriptionActive(:final tier, :final willRenew) => 
      willRenew ? '$tier (Active)' : '$tier (Canceling)',
    SubscriptionTrial(:final daysLeft) => 
      'Trial ($daysLeft days left)',
    SubscriptionGracePeriod(:final daysLeft) => 
      'Payment issue ($daysLeft days to fix)',
    SubscriptionBillingRetry() => 
      'Payment failing',
    SubscriptionPaused() => 
      'Paused',
    SubscriptionExpired(:final isWinbackEligible) => 
      isWinbackEligible ? 'Expired (Come back!)' : 'Expired',
    SubscriptionNone() => 
      'Free',
  };
  
  /// Get the tier if any subscription exists (active or expired)
  String? get tier => switch (this) {
    SubscriptionActive(:final tier) => tier,
    SubscriptionTrial(:final tier) => tier,
    SubscriptionGracePeriod(:final tier) => tier,
    SubscriptionBillingRetry(:final tier) => tier,
    SubscriptionPaused(:final tier) => tier,
    SubscriptionExpired(:final lastTier) => lastTier,
    SubscriptionNone() => null,
  };
}
