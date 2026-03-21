package com.example.paywall

import com.revenuecat.purchases.Package
import com.revenuecat.purchases.models.StoreProduct

/**
 * Represents the current state of the paywall screen.
 */
sealed class PaywallState {
    /** Initial loading state while fetching offerings */
    data object Loading : PaywallState()
    
    /** Successfully loaded offerings with packages to display */
    data class Ready(
        val packages: List<PackageInfo>,
        val selectedPackage: PackageInfo? = null,
        val isPurchasing: Boolean = false
    ) : PaywallState()
    
    /** Failed to load offerings */
    data class Error(val message: String) : PaywallState()
}

/**
 * Wrapper around RevenueCat Package with computed display properties.
 */
data class PackageInfo(
    val rcPackage: Package,
    val title: String,
    val description: String,
    val priceString: String,
    val pricePerMonth: String?,
    val hasFreeTrial: Boolean,
    val freeTrialDuration: String?,
    val savingsPercent: Int?,
    val isBestValue: Boolean
) {
    companion object {
        fun from(pkg: Package, monthlyPrice: Double? = null): PackageInfo {
            val product = pkg.product
            val hasFreeTrial = product.subscriptionOptions
                ?.defaultOffer
                ?.freePhase != null
            
            val freeTrialDuration = product.subscriptionOptions
                ?.defaultOffer
                ?.freePhase
                ?.billingPeriod
                ?.let { formatBillingPeriod(it.value, it.unit.name) }
            
            // Calculate monthly equivalent for annual plans
            val pricePerMonth = when (pkg.packageType.identifier) {
                "\$rc_annual" -> {
                    val monthlyEquiv = (product.price.amountMicros / 1_000_000.0) / 12
                    String.format("%.2f", monthlyEquiv) + "/mo"
                }
                else -> null
            }
            
            // Calculate savings vs monthly
            val savingsPercent = if (monthlyPrice != null && pkg.packageType.identifier == "\$rc_annual") {
                val annualMonthly = (product.price.amountMicros / 1_000_000.0) / 12
                ((1 - annualMonthly / monthlyPrice) * 100).toInt()
            } else null
            
            return PackageInfo(
                rcPackage = pkg,
                title = formatPackageTitle(pkg),
                description = product.description,
                priceString = product.price.formatted,
                pricePerMonth = pricePerMonth,
                hasFreeTrial = hasFreeTrial,
                freeTrialDuration = freeTrialDuration,
                savingsPercent = savingsPercent,
                isBestValue = pkg.packageType.identifier == "\$rc_annual"
            )
        }
        
        private fun formatPackageTitle(pkg: Package): String {
            return when (pkg.packageType.identifier) {
                "\$rc_monthly" -> "Monthly"
                "\$rc_annual" -> "Annual"
                "\$rc_six_month" -> "6 Months"
                "\$rc_three_month" -> "3 Months"
                "\$rc_two_month" -> "2 Months"
                "\$rc_weekly" -> "Weekly"
                "\$rc_lifetime" -> "Lifetime"
                else -> pkg.identifier
            }
        }
        
        private fun formatBillingPeriod(value: Int, unit: String): String {
            val unitDisplay = when (unit.lowercase()) {
                "day" -> if (value == 1) "day" else "days"
                "week" -> if (value == 1) "week" else "weeks"
                "month" -> if (value == 1) "month" else "months"
                "year" -> if (value == 1) "year" else "years"
                else -> unit.lowercase()
            }
            return "$value $unitDisplay"
        }
    }
}

/**
 * Result of a purchase attempt.
 */
sealed class PurchaseResult {
    data object Success : PurchaseResult()
    data object Cancelled : PurchaseResult()
    data class Error(val message: String, val code: Int? = null) : PurchaseResult()
}

/**
 * Events emitted by the paywall for analytics tracking.
 */
sealed class PaywallEvent {
    data object Viewed : PaywallEvent()
    data class PackageSelected(val packageId: String) : PaywallEvent()
    data class PurchaseStarted(val packageId: String) : PaywallEvent()
    data class PurchaseCompleted(val packageId: String, val revenue: Double) : PaywallEvent()
    data class PurchaseFailed(val packageId: String, val error: String) : PaywallEvent()
    data object Dismissed : PaywallEvent()
}
