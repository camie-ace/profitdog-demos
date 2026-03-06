"""
RevenueCat Quickstart - by ProfitDog 🐕

A minimal example showing how to check subscription status 
using RevenueCat's REST API. Perfect for agents building 
subscription-based apps.
"""

import os
import requests
from datetime import datetime

REVENUECAT_API_KEY = os.environ.get("REVENUECAT_API_KEY")
BASE_URL = "https://api.revenuecat.com/v1"

def get_subscriber(app_user_id: str) -> dict:
    """Fetch subscriber info from RevenueCat."""
    headers = {
        "Authorization": f"Bearer {REVENUECAT_API_KEY}",
        "Content-Type": "application/json"
    }
    response = requests.get(
        f"{BASE_URL}/subscribers/{app_user_id}",
        headers=headers
    )
    response.raise_for_status()
    return response.json()

def check_entitlement(subscriber_data: dict, entitlement_id: str) -> bool:
    """Check if user has an active entitlement."""
    entitlements = subscriber_data.get("subscriber", {}).get("entitlements", {})
    entitlement = entitlements.get(entitlement_id, {})
    
    if not entitlement:
        return False
    
    expires_date = entitlement.get("expires_date")
    if expires_date is None:
        return True  # Lifetime access
    
    return datetime.fromisoformat(expires_date.replace("Z", "+00:00")) > datetime.now().astimezone()

def get_active_subscriptions(subscriber_data: dict) -> list:
    """Get list of active subscription product IDs."""
    subscriptions = subscriber_data.get("subscriber", {}).get("subscriptions", {})
    active = []
    
    for product_id, sub_data in subscriptions.items():
        expires_date = sub_data.get("expires_date")
        if expires_date:
            if datetime.fromisoformat(expires_date.replace("Z", "+00:00")) > datetime.now().astimezone():
                active.append(product_id)
    
    return active

# Example usage
if __name__ == "__main__":
    # This would be your user's ID in RevenueCat
    user_id = "user_12345"
    
    try:
        subscriber = get_subscriber(user_id)
        
        # Check for "premium" entitlement
        has_premium = check_entitlement(subscriber, "premium")
        print(f"User has premium: {has_premium}")
        
        # Get all active subscriptions
        active_subs = get_active_subscriptions(subscriber)
        print(f"Active subscriptions: {active_subs}")
        
    except requests.exceptions.HTTPError as e:
        print(f"API Error: {e}")
