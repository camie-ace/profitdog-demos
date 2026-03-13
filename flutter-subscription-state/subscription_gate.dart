/// Widget for gating premium content based on subscription state
/// 
/// Provides flexible UI patterns for:
/// - Hard gates (must subscribe to see content)
/// - Soft gates (show preview with upgrade prompt)
/// - Contextual banners (payment issues, trial expiring)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'subscription_state.dart';
import 'subscription_provider.dart';

/// Hard gate - blocks access to premium content
/// 
/// Usage:
/// ```dart
/// SubscriptionGate(
///   child: PremiumFeatureScreen(),
///   paywallBuilder: (context) => MyPaywall(),
/// )
/// ```
class SubscriptionGate extends ConsumerWidget {
  final Widget child;
  final WidgetBuilder paywallBuilder;
  final WidgetBuilder? loadingBuilder;
  
  const SubscriptionGate({
    super.key,
    required this.child,
    required this.paywallBuilder,
    this.loadingBuilder,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionProvider);
    
    if (state.hasAccess) {
      return child;
    }
    
    return paywallBuilder(context);
  }
}


/// Soft gate - shows content with upgrade prompt overlay
/// 
/// Usage:
/// ```dart
/// SoftSubscriptionGate(
///   child: PremiumContent(),
///   previewLines: 3,
///   onUpgradeTap: () => showPaywall(context),
/// )
/// ```
class SoftSubscriptionGate extends ConsumerWidget {
  final Widget child;
  final int? previewLines;
  final VoidCallback onUpgradeTap;
  final String upgradeText;
  
  const SoftSubscriptionGate({
    super.key,
    required this.child,
    this.previewLines,
    required this.onUpgradeTap,
    this.upgradeText = 'Upgrade to see full content',
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccess = ref.watch(hasAccessProvider);
    
    if (hasAccess) {
      return child;
    }
    
    return Stack(
      children: [
        // Blurred/faded content preview
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white.withOpacity(0)],
            stops: const [0.3, 0.8],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: IgnorePointer(child: child),
        ),
        // Upgrade prompt overlay
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            child: ElevatedButton(
              onPressed: onUpgradeTap,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(upgradeText),
            ),
          ),
        ),
      ],
    );
  }
}


/// Banner for subscription status alerts (payment issues, trial expiring, etc.)
/// 
/// Place this in your app shell to show contextual warnings.
/// 
/// Usage:
/// ```dart
/// Scaffold(
///   body: Column(
///     children: [
///       SubscriptionStatusBanner(),
///       Expanded(child: content),
///     ],
///   ),
/// )
/// ```
class SubscriptionStatusBanner extends ConsumerWidget {
  final VoidCallback? onTap;
  
  const SubscriptionStatusBanner({
    super.key,
    this.onTap,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(subscriptionProvider);
    
    return switch (state) {
      // Payment issue - urgent warning
      SubscriptionGracePeriod(:final daysLeft) => _WarningBanner(
        icon: Icons.warning_amber_rounded,
        message: 'Payment issue - fix within $daysLeft days to keep access',
        color: Colors.orange,
        onTap: onTap,
      ),
      
      SubscriptionBillingRetry() => _WarningBanner(
        icon: Icons.error_outline,
        message: 'Payment failing - update your payment method',
        color: Colors.red,
        onTap: onTap,
      ),
      
      // Trial expiring soon
      SubscriptionTrial(:final daysLeft) when daysLeft <= 3 => _WarningBanner(
        icon: Icons.timer_outlined,
        message: daysLeft == 1 
          ? 'Trial ends tomorrow!' 
          : 'Trial ends in $daysLeft days',
        color: Colors.blue,
        onTap: onTap,
      ),
      
      // Subscription canceling
      SubscriptionActive(:final willRenew, :final daysUntilExpiration) 
        when !willRenew && daysUntilExpiration <= 7 => _WarningBanner(
        icon: Icons.info_outline,
        message: 'Subscription ends in $daysUntilExpiration days',
        color: Colors.grey,
        onTap: onTap,
      ),
      
      // Win-back for recently expired
      SubscriptionExpired(:final isRecentlyExpired) when isRecentlyExpired => _WarningBanner(
        icon: Icons.favorite_border,
        message: 'We miss you! Resubscribe and pick up where you left off',
        color: Colors.purple,
        onTap: onTap,
      ),
      
      // No banner needed for other states
      _ => const SizedBox.shrink(),
    };
  }
}

class _WarningBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback? onTap;
  
  const _WarningBanner({
    required this.icon,
    required this.message,
    required this.color,
    this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: color.withOpacity(0.1),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: color.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onTap != null) 
              Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}


/// Hook-style helper for checking tier access
/// 
/// Usage:
/// ```dart
/// final canAccessPro = ref.watch(hasTierAccessProvider('pro'));
/// ```
final hasTierAccessProvider = Provider.family<bool, String>((ref, requiredTier) {
  final state = ref.watch(subscriptionProvider);
  
  if (!state.hasAccess) return false;
  
  // Define tier hierarchy
  const tierHierarchy = ['free', 'pro', 'premium', 'business'];
  
  final currentTier = state.tier;
  if (currentTier == null) return false;
  
  final requiredIndex = tierHierarchy.indexOf(requiredTier);
  final currentIndex = tierHierarchy.indexOf(currentTier);
  
  // User has access if their tier is >= required tier
  return currentIndex >= requiredIndex;
});
