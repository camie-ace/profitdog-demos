package com.example.subscriptions

import android.app.Activity
import android.app.Application
import android.util.Log
import com.revenuecat.purchases.*
import com.revenuecat.purchases.interfaces.*
import com.revenuecat.purchases.models.*
import com.revenuecat.purchases.paywalls.events.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * RevenueCatHelper.kt
 * 
 * A coroutine-friendly wrapper around the RevenueCat Android SDK.
 * 
 * Features:
 * - Suspend functions for all async operations
 * - StateFlow for reactive customer info updates
 * - Clean error handling with sealed Result types
 * - Entitlement checking utilities
 * - Purchase flow helpers
 * 
 * Usage:
 * 1. Initialize once in Application.onCreate()
 * 2. Collect customerInfo flow for reactive UI updates
 * 3. Use suspend functions for purchases and restores
 * 
 * Created by ProfitDog 🐕
 */

object RevenueCatHelper {
    
    private const val TAG = "RevenueCatHelper"
    
    // Entitlement ID - configure this for your app
    const val PREMIUM_ENTITLEMENT = "premium"
    
    private val _customerInfo = MutableStateFlow<CustomerInfo?>(null)
    
    /**
     * Reactive stream of customer info updates.
     * Emits whenever subscription status changes.
     */
    val customerInfo: StateFlow<CustomerInfo?> = _customerInfo.asStateFlow()
    
    /**
     * Convenience flow for checking premium status.
     * Emits true when user has active premium entitlement.
     */
    val isPremium: Flow<Boolean> = customerInfo.map { info ->
        info?.entitlements?.get(PREMIUM_ENTITLEMENT)?.isActive == true
    }
    
    /**
     * Initialize RevenueCat. Call once in Application.onCreate().
     * 
     * @param application Your Application instance
     * @param apiKey Your RevenueCat public API key (starts with "goog_" for Android)
     * @param appUserId Optional user ID for cross-platform sync
     */
    fun configure(
        application: Application,
        apiKey: String,
        appUserId: String? = null
    ) {
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        
        val builder = PurchasesConfiguration.Builder(application, apiKey)
        appUserId?.let { builder.appUserID(it) }
        
        Purchases.configure(builder.build())
        
        // Set up listener for customer info updates
        Purchases.sharedInstance.updatedCustomerInfoListener = 
            UpdatedCustomerInfoListener { info ->
                _customerInfo.value = info
                Log.d(TAG, "Customer info updated: premium=${hasPremium(info)}")
            }
        
        // Fetch initial customer info
        Purchases.sharedInstance.getCustomerInfoWith { info ->
            _customerInfo.value = info
        }
    }
    
    // =========================================================================
    // Entitlement Checks
    // =========================================================================
    
    /**
     * Check if user has premium entitlement.
     * Uses cached customer info for instant results.
     */
    fun hasPremium(): Boolean = hasPremium(_customerInfo.value)
    
    private fun hasPremium(info: CustomerInfo?): Boolean {
        return info?.entitlements?.get(PREMIUM_ENTITLEMENT)?.isActive == true
    }
    
    /**
     * Check if a specific entitlement is active.
     */
    fun hasEntitlement(entitlementId: String): Boolean {
        return _customerInfo.value?.entitlements?.get(entitlementId)?.isActive == true
    }
    
    /**
     * Get detailed entitlement info for UI display.
     */
    fun getPremiumInfo(): EntitlementDetails? {
        val entitlement = _customerInfo.value?.entitlements?.get(PREMIUM_ENTITLEMENT)
            ?: return null
        
        return EntitlementDetails(
            isActive = entitlement.isActive,
            willRenew = entitlement.willRenew,
            expirationDate = entitlement.expirationDate,
            productId = entitlement.productIdentifier,
            isSandbox = entitlement.isSandbox,
            ownershipType = entitlement.ownershipType,
            periodType = entitlement.periodType,
            // Check for billing issues
            billingIssue = entitlement.billingIssueDetectedAt != null,
            // Grace period detection
            inGracePeriod = entitlement.isActive && 
                entitlement.expirationDate?.before(java.util.Date()) == true
        )
    }
    
    // =========================================================================
    // Offerings & Packages
    // =========================================================================
    
    /**
     * Fetch current offerings (suspend function).
     * Returns available packages for your paywall.
     */
    suspend fun getOfferings(): Result<Offerings> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.getOfferingsWith(
            onError = { error ->
                Log.e(TAG, "Failed to fetch offerings: ${error.message}")
                cont.resume(Result.failure(RevenueCatException(error)))
            },
            onSuccess = { offerings ->
                cont.resume(Result.success(offerings))
            }
        )
    }
    
    /**
     * Get the current offering with available packages.
     * This is what you typically display in your paywall.
     */
    suspend fun getCurrentOffering(): Offering? {
        return getOfferings().getOrNull()?.current
    }
    
    /**
     * Get a specific offering by identifier.
     * Useful for A/B tests or custom placements.
     */
    suspend fun getOffering(identifier: String): Offering? {
        return getOfferings().getOrNull()?.get(identifier)
    }
    
    // =========================================================================
    // Purchases
    // =========================================================================
    
    /**
     * Purchase a package (suspend function).
     * 
     * @param activity Current activity (required for Google Play billing)
     * @param package The package to purchase
     * @return Result with CustomerInfo on success
     */
    suspend fun purchase(
        activity: Activity,
        packageToPurchase: Package
    ): Result<CustomerInfo> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.purchaseWith(
            PurchaseParams.Builder(activity, packageToPurchase).build(),
            onError = { error, userCancelled ->
                if (userCancelled) {
                    Log.d(TAG, "Purchase cancelled by user")
                    cont.resume(Result.failure(PurchaseCancelledException()))
                } else {
                    Log.e(TAG, "Purchase failed: ${error.message}")
                    cont.resume(Result.failure(RevenueCatException(error)))
                }
            },
            onSuccess = { _, customerInfo ->
                Log.d(TAG, "Purchase successful!")
                _customerInfo.value = customerInfo
                cont.resume(Result.success(customerInfo))
            }
        )
    }
    
    /**
     * Restore previous purchases.
     * Call this from your "Restore Purchases" button.
     */
    suspend fun restorePurchases(): Result<CustomerInfo> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { error ->
                Log.e(TAG, "Restore failed: ${error.message}")
                cont.resume(Result.failure(RevenueCatException(error)))
            },
            onSuccess = { customerInfo ->
                Log.d(TAG, "Restore successful: premium=${hasPremium(customerInfo)}")
                _customerInfo.value = customerInfo
                cont.resume(Result.success(customerInfo))
            }
        )
    }
    
    // =========================================================================
    // User Management
    // =========================================================================
    
    /**
     * Log in an identified user (for cross-device sync).
     * Call this after your own authentication flow.
     */
    suspend fun logIn(appUserId: String): Result<CustomerInfo> = 
        suspendCancellableCoroutine { cont ->
            Purchases.sharedInstance.logInWith(
                appUserId,
                onError = { error ->
                    Log.e(TAG, "Login failed: ${error.message}")
                    cont.resume(Result.failure(RevenueCatException(error)))
                },
                onSuccess = { customerInfo, _ ->
                    _customerInfo.value = customerInfo
                    cont.resume(Result.success(customerInfo))
                }
            )
        }
    
    /**
     * Log out the current user.
     * Resets to anonymous user.
     */
    suspend fun logOut(): Result<CustomerInfo> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.logOutWith(
            onError = { error ->
                cont.resume(Result.failure(RevenueCatException(error)))
            },
            onSuccess = { customerInfo ->
                _customerInfo.value = customerInfo
                cont.resume(Result.success(customerInfo))
            }
        )
    }
    
    /**
     * Get current app user ID.
     */
    val appUserId: String
        get() = Purchases.sharedInstance.appUserID
    
    /**
     * Check if current user is anonymous.
     */
    val isAnonymous: Boolean
        get() = Purchases.sharedInstance.isAnonymous
    
    // =========================================================================
    // Customer Info
    // =========================================================================
    
    /**
     * Force refresh customer info from RevenueCat.
     * Use sparingly - cached info is usually sufficient.
     */
    suspend fun refreshCustomerInfo(): Result<CustomerInfo> = 
        suspendCancellableCoroutine { cont ->
            Purchases.sharedInstance.getCustomerInfoWith(
                CacheFetchPolicy.FETCH_CURRENT,
                onError = { error ->
                    cont.resume(Result.failure(RevenueCatException(error)))
                },
                onSuccess = { customerInfo ->
                    _customerInfo.value = customerInfo
                    cont.resume(Result.success(customerInfo))
                }
            )
        }
    
    // =========================================================================
    // Subscription Management
    // =========================================================================
    
    /**
     * Get management URL for the current subscription.
     * Opens Play Store subscription management.
     */
    fun getManagementUrl(): String? {
        return _customerInfo.value?.managementURL?.toString()
    }
    
    /**
     * Check if user is eligible for intro pricing.
     */
    suspend fun checkIntroEligibility(
        productIds: List<String>
    ): Map<String, IntroEligibility> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.getProductsWith(
            productIds,
            onError = { error ->
                cont.resume(emptyMap())
            },
            onGetStoreProducts = { products ->
                val result = products.associate { product ->
                    product.id to determineIntroEligibility(product)
                }
                cont.resume(result)
            }
        )
    }
    
    private fun determineIntroEligibility(product: StoreProduct): IntroEligibility {
        // Check if product has free trial or intro pricing
        val subscriptionOption = product.subscriptionOptions?.defaultOption
        return if (subscriptionOption?.freePhase != null || 
                   subscriptionOption?.introPhase != null) {
            IntroEligibility.ELIGIBLE
        } else {
            IntroEligibility.INELIGIBLE
        }
    }
}

// =========================================================================
// Data Classes & Exceptions
// =========================================================================

/**
 * Detailed information about an entitlement for UI display.
 */
data class EntitlementDetails(
    val isActive: Boolean,
    val willRenew: Boolean,
    val expirationDate: java.util.Date?,
    val productId: String,
    val isSandbox: Boolean,
    val ownershipType: OwnershipType,
    val periodType: PeriodType,
    val billingIssue: Boolean,
    val inGracePeriod: Boolean
)

enum class IntroEligibility {
    ELIGIBLE,
    INELIGIBLE,
    UNKNOWN
}

/**
 * Exception wrapper for RevenueCat errors.
 */
class RevenueCatException(
    val error: PurchasesError
) : Exception(error.message) {
    val code: PurchasesErrorCode = error.code
    val underlyingError: String? = error.underlyingErrorMessage
}

/**
 * Thrown when user cancels a purchase.
 */
class PurchaseCancelledException : Exception("Purchase cancelled by user")

// =========================================================================
// Extension Functions
// =========================================================================

/**
 * Observe customer info as a Flow with custom transformations.
 * 
 * Usage:
 * lifecycleScope.launch {
 *     RevenueCatHelper.observeCustomerInfo { info ->
 *         info?.entitlements?.all?.keys ?: emptySet()
 *     }.collect { entitlementIds ->
 *         updateUI(entitlementIds)
 *     }
 * }
 */
fun <T> RevenueCatHelper.observeCustomerInfo(
    transform: (CustomerInfo?) -> T
): Flow<T> = customerInfo.map(transform)

/**
 * Collect premium status with a callback.
 * 
 * Usage in ViewModel:
 * init {
 *     viewModelScope.launch {
 *         RevenueCatHelper.isPremium.collect { isPremium ->
 *             _uiState.update { it.copy(isPremium = isPremium) }
 *         }
 *     }
 * }
 */

// =========================================================================
// Usage Examples
// =========================================================================

/*
 * 1. INITIALIZATION (in Application class):
 * 
 * class MyApp : Application() {
 *     override fun onCreate() {
 *         super.onCreate()
 *         RevenueCatHelper.configure(
 *             application = this,
 *             apiKey = "goog_your_api_key_here"
 *         )
 *     }
 * }
 *
 * 2. PAYWALL VIEWMODEL:
 * 
 * class PaywallViewModel : ViewModel() {
 *     private val _offerings = MutableStateFlow<List<Package>>(emptyList())
 *     val offerings: StateFlow<List<Package>> = _offerings.asStateFlow()
 *     
 *     val isPremium = RevenueCatHelper.isPremium
 *         .stateIn(viewModelScope, SharingStarted.Eagerly, false)
 *     
 *     init {
 *         loadOfferings()
 *     }
 *     
 *     private fun loadOfferings() {
 *         viewModelScope.launch {
 *             RevenueCatHelper.getCurrentOffering()?.availablePackages?.let {
 *                 _offerings.value = it
 *             }
 *         }
 *     }
 *     
 *     fun purchase(activity: Activity, pkg: Package) {
 *         viewModelScope.launch {
 *             RevenueCatHelper.purchase(activity, pkg)
 *                 .onSuccess { /* Handle success */ }
 *                 .onFailure { error ->
 *                     when (error) {
 *                         is PurchaseCancelledException -> { /* User cancelled */ }
 *                         is RevenueCatException -> { /* Show error */ }
 *                     }
 *                 }
 *         }
 *     }
 * }
 *
 * 3. SIMPLE ENTITLEMENT CHECK:
 * 
 * if (RevenueCatHelper.hasPremium()) {
 *     showPremiumContent()
 * } else {
 *     showPaywall()
 * }
 *
 * 4. REACTIVE GATING IN COMPOSE:
 * 
 * @Composable
 * fun PremiumFeature() {
 *     val isPremium by RevenueCatHelper.isPremium.collectAsState(initial = false)
 *     
 *     if (isPremium) {
 *         PremiumContent()
 *     } else {
 *         LockedContent(onUnlockClick = { showPaywall() })
 *     }
 * }
 *
 * 5. BILLING ISSUE HANDLING:
 * 
 * val premiumInfo = RevenueCatHelper.getPremiumInfo()
 * when {
 *     premiumInfo?.billingIssue == true -> showBillingWarning()
 *     premiumInfo?.inGracePeriod == true -> showGracePeriodNotice()
 *     premiumInfo?.isActive == true -> enablePremiumFeatures()
 * }
 */
