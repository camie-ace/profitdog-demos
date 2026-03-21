package com.example.paywall

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel for the Paywall screen.
 * 
 * Handles fetching offerings, processing purchases, and managing UI state
 * with proper error handling and analytics tracking.
 */
class PaywallViewModel : ViewModel() {
    
    private val _state = MutableStateFlow<PaywallState>(PaywallState.Loading)
    val state: StateFlow<PaywallState> = _state.asStateFlow()
    
    private val _purchaseResult = MutableSharedFlow<PurchaseResult>()
    val purchaseResult: SharedFlow<PurchaseResult> = _purchaseResult.asSharedFlow()
    
    private val _events = MutableSharedFlow<PaywallEvent>()
    val events: SharedFlow<PaywallEvent> = _events.asSharedFlow()
    
    private var currentOfferings: Offerings? = null
    
    init {
        loadOfferings()
    }
    
    /**
     * Fetches available offerings from RevenueCat.
     * Uses the current offering by default, or specify an offering identifier
     * to test different paywalls.
     */
    fun loadOfferings(offeringIdentifier: String? = null) {
        viewModelScope.launch {
            _state.value = PaywallState.Loading
            _events.emit(PaywallEvent.Viewed)
            
            try {
                val offerings = Purchases.sharedInstance.awaitOfferings()
                currentOfferings = offerings
                
                val offering = if (offeringIdentifier != null) {
                    offerings.getOffering(offeringIdentifier)
                } else {
                    offerings.current
                }
                
                if (offering == null || offering.availablePackages.isEmpty()) {
                    _state.value = PaywallState.Error(
                        "No subscription options available. Please try again later."
                    )
                    return@launch
                }
                
                // Get monthly price for savings calculations
                val monthlyPackage = offering.monthly
                val monthlyPrice = monthlyPackage?.product?.price?.amountMicros
                    ?.let { it / 1_000_000.0 }
                
                // Convert packages to display models
                val packages = offering.availablePackages
                    .map { PackageInfo.from(it, monthlyPrice) }
                    .sortedByDescending { it.isBestValue } // Best value first
                
                _state.value = PaywallState.Ready(
                    packages = packages,
                    selectedPackage = packages.firstOrNull { it.isBestValue }
                        ?: packages.firstOrNull()
                )
                
            } catch (e: PurchasesError) {
                _state.value = PaywallState.Error(
                    getErrorMessage(e)
                )
            } catch (e: Exception) {
                _state.value = PaywallState.Error(
                    "Unable to load subscription options: ${e.message}"
                )
            }
        }
    }
    
    /**
     * Selects a package for purchase.
     */
    fun selectPackage(packageInfo: PackageInfo) {
        val currentState = _state.value as? PaywallState.Ready ?: return
        _state.value = currentState.copy(selectedPackage = packageInfo)
        
        viewModelScope.launch {
            _events.emit(PaywallEvent.PackageSelected(packageInfo.rcPackage.identifier))
        }
    }
    
    /**
     * Initiates a purchase for the selected package.
     */
    fun purchase(activity: Activity) {
        val currentState = _state.value as? PaywallState.Ready ?: return
        val selectedPackage = currentState.selectedPackage ?: return
        
        if (currentState.isPurchasing) return
        
        viewModelScope.launch {
            _state.value = currentState.copy(isPurchasing = true)
            _events.emit(PaywallEvent.PurchaseStarted(selectedPackage.rcPackage.identifier))
            
            try {
                val purchaseParams = PurchaseParams.Builder(activity, selectedPackage.rcPackage)
                    .build()
                
                val (_, customerInfo) = Purchases.sharedInstance.awaitPurchase(purchaseParams)
                
                // Calculate revenue for analytics
                val revenue = selectedPackage.rcPackage.product.price.amountMicros / 1_000_000.0
                _events.emit(
                    PaywallEvent.PurchaseCompleted(
                        packageId = selectedPackage.rcPackage.identifier,
                        revenue = revenue
                    )
                )
                
                _purchaseResult.emit(PurchaseResult.Success)
                
            } catch (e: PurchasesError) {
                val result = when (e.code) {
                    PurchasesErrorCode.PurchaseCancelledError -> {
                        PurchaseResult.Cancelled
                    }
                    else -> {
                        _events.emit(
                            PaywallEvent.PurchaseFailed(
                                packageId = selectedPackage.rcPackage.identifier,
                                error = e.code.name
                            )
                        )
                        PurchaseResult.Error(
                            message = getErrorMessage(e),
                            code = e.code.code
                        )
                    }
                }
                _purchaseResult.emit(result)
                
            } finally {
                val newState = _state.value as? PaywallState.Ready
                if (newState != null) {
                    _state.value = newState.copy(isPurchasing = false)
                }
            }
        }
    }
    
    /**
     * Restores previous purchases.
     */
    fun restorePurchases() {
        val currentState = _state.value as? PaywallState.Ready ?: return
        if (currentState.isPurchasing) return
        
        viewModelScope.launch {
            _state.value = currentState.copy(isPurchasing = true)
            
            try {
                val customerInfo = Purchases.sharedInstance.awaitRestore()
                
                if (customerInfo.entitlements.active.isNotEmpty()) {
                    _purchaseResult.emit(PurchaseResult.Success)
                } else {
                    _purchaseResult.emit(
                        PurchaseResult.Error("No previous purchases found to restore.")
                    )
                }
                
            } catch (e: PurchasesError) {
                _purchaseResult.emit(
                    PurchaseResult.Error(getErrorMessage(e))
                )
                
            } finally {
                val newState = _state.value as? PaywallState.Ready
                if (newState != null) {
                    _state.value = newState.copy(isPurchasing = false)
                }
            }
        }
    }
    
    /**
     * Called when the paywall is dismissed without purchasing.
     */
    fun onDismiss() {
        viewModelScope.launch {
            _events.emit(PaywallEvent.Dismissed)
        }
    }
    
    /**
     * Returns a user-friendly error message for RevenueCat errors.
     */
    private fun getErrorMessage(error: PurchasesError): String {
        return when (error.code) {
            PurchasesErrorCode.NetworkError -> 
                "Network connection issue. Please check your internet and try again."
            PurchasesErrorCode.PurchaseCancelledError -> 
                "Purchase was cancelled."
            PurchasesErrorCode.StoreProblemError -> 
                "There was a problem with the App Store. Please try again."
            PurchasesErrorCode.PurchaseNotAllowedError -> 
                "Purchases are not allowed on this device."
            PurchasesErrorCode.PurchaseInvalidError -> 
                "The purchase was invalid. Please try again."
            PurchasesErrorCode.ProductNotAvailableForPurchaseError -> 
                "This product is not available for purchase."
            PurchasesErrorCode.ProductAlreadyPurchasedError -> 
                "You've already purchased this product."
            PurchasesErrorCode.ReceiptAlreadyInUseError -> 
                "This purchase is already associated with another account."
            PurchasesErrorCode.PaymentPendingError -> 
                "Payment is pending. Please complete the payment to continue."
            else -> 
                error.message ?: "An unexpected error occurred. Please try again."
        }
    }
}
