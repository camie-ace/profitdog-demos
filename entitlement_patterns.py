#!/usr/bin/env python3
"""
Entitlement Checking Patterns
==============================

Common patterns for checking and managing entitlements with RevenueCat.
These patterns work with both client SDKs and server-side REST API.

Created by ProfitDog 🐕
"""

import os
import functools
from datetime import datetime
from typing import Callable, Optional, TypeVar, Any
from dataclasses import dataclass
from enum import Enum, auto

# For REST API examples
import requests


# =============================================================================
# Pattern 1: Simple Entitlement Check
# =============================================================================

def check_entitlement_simple(customer_info: dict, entitlement_id: str) -> bool:
    """
    Basic entitlement check - the most common pattern.
    
    Works with RevenueCat SDK's customerInfo or REST API response.
    
    Example:
        customer_info = Purchases.shared.customerInfo()
        if check_entitlement_simple(customer_info, "premium"):
            show_premium_content()
    """
    entitlements = customer_info.get("subscriber", {}).get("entitlements", {})
    entitlement = entitlements.get(entitlement_id, {})
    
    # An entitlement is active if it exists and hasn't expired
    if not entitlement:
        return False
    
    expires_date = entitlement.get("expires_date")
    if expires_date is None:
        # Lifetime purchase - no expiration
        return True
    
    # Parse ISO date and compare to now
    expires = datetime.fromisoformat(expires_date.replace("Z", "+00:00"))
    return expires > datetime.now(expires.tzinfo)


# =============================================================================
# Pattern 2: Entitlement with Grace Period Awareness
# =============================================================================

@dataclass
class EntitlementStatus:
    """Rich entitlement status with billing state awareness."""
    is_active: bool
    in_grace_period: bool
    in_billing_retry: bool
    will_renew: bool
    expires_date: Optional[datetime]
    product_identifier: Optional[str]


def check_entitlement_detailed(
    customer_info: dict, 
    entitlement_id: str
) -> EntitlementStatus:
    """
    Detailed entitlement check with grace period and billing retry awareness.
    
    Use this when you need to:
    - Show "fix your payment" banners
    - Handle grace periods differently
    - Know if subscription will renew
    
    Example:
        status = check_entitlement_detailed(customer_info, "pro")
        if status.is_active and status.in_billing_retry:
            show_payment_warning_banner()
        elif not status.is_active:
            show_upgrade_screen()
    """
    subscriber = customer_info.get("subscriber", {})
    entitlements = subscriber.get("entitlements", {})
    entitlement = entitlements.get(entitlement_id, {})
    
    if not entitlement:
        return EntitlementStatus(
            is_active=False,
            in_grace_period=False,
            in_billing_retry=False,
            will_renew=False,
            expires_date=None,
            product_identifier=None
        )
    
    # Get the underlying subscription
    product_id = entitlement.get("product_identifier")
    subscriptions = subscriber.get("subscriptions", {})
    subscription = subscriptions.get(product_id, {})
    
    # Parse dates
    expires_date = None
    if entitlement.get("expires_date"):
        expires_date = datetime.fromisoformat(
            entitlement["expires_date"].replace("Z", "+00:00")
        )
    
    # Check billing state
    billing_issues_detected = subscription.get("billing_issues_detected_at") is not None
    grace_period_expires = subscription.get("grace_period_expires_date")
    in_grace_period = grace_period_expires is not None
    
    # Is it currently active?
    is_active = False
    if expires_date is None:
        is_active = True  # Lifetime
    elif expires_date > datetime.now(expires_date.tzinfo):
        is_active = True
    elif in_grace_period:
        # Still active during grace period
        grace_expires = datetime.fromisoformat(
            grace_period_expires.replace("Z", "+00:00")
        )
        is_active = grace_expires > datetime.now(grace_expires.tzinfo)
    
    return EntitlementStatus(
        is_active=is_active,
        in_grace_period=in_grace_period,
        in_billing_retry=billing_issues_detected,
        will_renew=subscription.get("unsubscribe_detected_at") is None,
        expires_date=expires_date,
        product_identifier=product_id
    )


# =============================================================================
# Pattern 3: Feature Flags from Entitlements
# =============================================================================

class Feature(Enum):
    """Features that can be unlocked by entitlements."""
    REMOVE_ADS = auto()
    UNLIMITED_EXPORTS = auto()
    CLOUD_SYNC = auto()
    PRIORITY_SUPPORT = auto()
    ADVANCED_ANALYTICS = auto()
    TEAM_FEATURES = auto()


# Map entitlements to features they unlock
ENTITLEMENT_FEATURES: dict[str, set[Feature]] = {
    "basic": {Feature.REMOVE_ADS},
    "pro": {Feature.REMOVE_ADS, Feature.UNLIMITED_EXPORTS, Feature.CLOUD_SYNC},
    "team": {
        Feature.REMOVE_ADS, 
        Feature.UNLIMITED_EXPORTS, 
        Feature.CLOUD_SYNC,
        Feature.PRIORITY_SUPPORT,
        Feature.ADVANCED_ANALYTICS,
        Feature.TEAM_FEATURES
    },
}


def get_unlocked_features(customer_info: dict) -> set[Feature]:
    """
    Get all features unlocked by the user's active entitlements.
    
    This pattern is great for apps with multiple tiers where features
    accumulate rather than replace each other.
    
    Example:
        features = get_unlocked_features(customer_info)
        if Feature.CLOUD_SYNC in features:
            enable_cloud_sync()
        if Feature.REMOVE_ADS in features:
            hide_ad_banners()
    """
    unlocked: set[Feature] = set()
    entitlements = customer_info.get("subscriber", {}).get("entitlements", {})
    
    for entitlement_id, feature_set in ENTITLEMENT_FEATURES.items():
        if check_entitlement_simple(customer_info, entitlement_id):
            unlocked.update(feature_set)
    
    return unlocked


def has_feature(customer_info: dict, feature: Feature) -> bool:
    """Check if a specific feature is unlocked."""
    return feature in get_unlocked_features(customer_info)


# =============================================================================
# Pattern 4: Decorator for Feature-Gated Functions
# =============================================================================

T = TypeVar('T')

# In a real app, this would fetch from RevenueCat SDK or cache
_current_customer_info: dict = {}


def requires_feature(feature: Feature, fallback: Optional[Callable[..., T]] = None):
    """
    Decorator to gate functions behind features.
    
    If the user doesn't have the feature, either calls fallback or raises.
    
    Example:
        @requires_feature(Feature.UNLIMITED_EXPORTS)
        def export_to_pdf(document):
            # Only runs if user has UNLIMITED_EXPORTS
            ...
        
        @requires_feature(Feature.CLOUD_SYNC, fallback=show_upgrade_prompt)
        def sync_to_cloud(data):
            # Calls show_upgrade_prompt if user lacks CLOUD_SYNC
            ...
    """
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> T:
            if has_feature(_current_customer_info, feature):
                return func(*args, **kwargs)
            elif fallback:
                return fallback(*args, **kwargs)
            else:
                raise PermissionError(
                    f"Feature {feature.name} required. Please upgrade your subscription."
                )
        return wrapper
    return decorator


# =============================================================================
# Pattern 5: Server-Side Entitlement Check (REST API)
# =============================================================================

class RevenueCatClient:
    """
    Server-side RevenueCat client for entitlement checks.
    
    Use this for:
    - Backend feature gating
    - Webhook processing
    - Admin dashboards
    
    Example:
        client = RevenueCatClient(api_key=os.environ["REVENUECAT_API_KEY"])
        
        if client.has_entitlement(user_id, "premium"):
            return premium_content()
        else:
            return {"error": "Premium required", "upgrade_url": "/subscribe"}
    """
    
    BASE_URL = "https://api.revenuecat.com/v1"
    
    def __init__(self, api_key: str):
        self.api_key = api_key
        self._cache: dict[str, tuple[datetime, dict]] = {}  # Simple in-memory cache
        self._cache_ttl_seconds = 60
    
    def get_subscriber(self, app_user_id: str, use_cache: bool = True) -> dict:
        """Fetch subscriber info from RevenueCat API."""
        # Check cache first
        if use_cache and app_user_id in self._cache:
            cached_at, data = self._cache[app_user_id]
            age = (datetime.utcnow() - cached_at).total_seconds()
            if age < self._cache_ttl_seconds:
                return data
        
        response = requests.get(
            f"{self.BASE_URL}/subscribers/{app_user_id}",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            }
        )
        response.raise_for_status()
        data = response.json()
        
        # Cache the result
        self._cache[app_user_id] = (datetime.utcnow(), data)
        return data
    
    def has_entitlement(
        self, 
        app_user_id: str, 
        entitlement_id: str,
        use_cache: bool = True
    ) -> bool:
        """Check if user has an active entitlement."""
        try:
            subscriber_data = self.get_subscriber(app_user_id, use_cache)
            return check_entitlement_simple(subscriber_data, entitlement_id)
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return False  # User not found = no entitlements
            raise
    
    def get_entitlement_status(
        self,
        app_user_id: str,
        entitlement_id: str
    ) -> EntitlementStatus:
        """Get detailed entitlement status for a user."""
        subscriber_data = self.get_subscriber(app_user_id)
        return check_entitlement_detailed(subscriber_data, entitlement_id)


# =============================================================================
# Pattern 6: Middleware for Web Frameworks
# =============================================================================

def flask_requires_entitlement(entitlement_id: str):
    """
    Flask decorator for entitlement-gated endpoints.
    
    Example:
        @app.route("/api/premium/report")
        @flask_requires_entitlement("premium")
        def premium_report():
            return generate_report()
    """
    from flask import request, jsonify, g
    
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            # Get user ID from your auth system
            user_id = getattr(g, 'user_id', None) or request.headers.get('X-User-ID')
            if not user_id:
                return jsonify({"error": "Authentication required"}), 401
            
            client = RevenueCatClient(os.environ["REVENUECAT_API_KEY"])
            
            if not client.has_entitlement(user_id, entitlement_id):
                return jsonify({
                    "error": "Subscription required",
                    "required_entitlement": entitlement_id,
                    "upgrade_url": "/subscribe"
                }), 403
            
            return func(*args, **kwargs)
        return wrapper
    return decorator


def fastapi_requires_entitlement(entitlement_id: str):
    """
    FastAPI dependency for entitlement-gated endpoints.
    
    Example:
        @app.get("/api/premium/data")
        async def premium_data(
            user_id: str = Depends(get_current_user),
            _: bool = Depends(fastapi_requires_entitlement("premium"))
        ):
            return {"data": "premium stuff"}
    """
    from fastapi import HTTPException, Request, Depends
    
    async def dependency(request: Request):
        user_id = getattr(request.state, 'user_id', None)
        if not user_id:
            raise HTTPException(status_code=401, detail="Authentication required")
        
        client = RevenueCatClient(os.environ["REVENUECAT_API_KEY"])
        
        if not client.has_entitlement(user_id, entitlement_id):
            raise HTTPException(
                status_code=403,
                detail={
                    "error": "Subscription required",
                    "required_entitlement": entitlement_id,
                    "upgrade_url": "/subscribe"
                }
            )
        return True
    
    return dependency


# =============================================================================
# Usage Examples
# =============================================================================

if __name__ == "__main__":
    # Example customer info (as returned by RevenueCat)
    example_customer_info = {
        "subscriber": {
            "entitlements": {
                "pro": {
                    "expires_date": "2025-12-31T23:59:59Z",
                    "product_identifier": "com.app.pro_monthly",
                    "purchase_date": "2024-12-01T10:00:00Z"
                }
            },
            "subscriptions": {
                "com.app.pro_monthly": {
                    "expires_date": "2025-12-31T23:59:59Z",
                    "unsubscribe_detected_at": None,
                    "billing_issues_detected_at": None,
                    "grace_period_expires_date": None
                }
            }
        }
    }
    
    # Pattern 1: Simple check
    print("Has pro:", check_entitlement_simple(example_customer_info, "pro"))
    print("Has team:", check_entitlement_simple(example_customer_info, "team"))
    
    # Pattern 2: Detailed status
    status = check_entitlement_detailed(example_customer_info, "pro")
    print(f"\nPro status: active={status.is_active}, will_renew={status.will_renew}")
    
    # Pattern 3: Feature flags
    _current_customer_info = example_customer_info
    features = get_unlocked_features(example_customer_info)
    print(f"\nUnlocked features: {[f.name for f in features]}")
    
    # Pattern 4: Decorator
    @requires_feature(Feature.CLOUD_SYNC)
    def sync_data():
        return "Syncing..."
    
    try:
        result = sync_data()
        print(f"\nSync result: {result}")
    except PermissionError as e:
        print(f"\nSync blocked: {e}")
    
    print("\n✅ All patterns demonstrated!")
