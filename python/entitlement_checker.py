import os
import requests

# --- Configuration ---
# It's best practice to load these from environment variables or a secure config store.
REVENUECAT_API_KEY = os.environ.get("REVENUECAT_API_KEY")
APP_USER_ID = "user_to_check_123"  # The app-specific user ID you want to check
ENTITLEMENT_ID = "pro_access"     # The entitlement identifier, e.g., "pro", "premium"

# --- API Details ---
API_VERSION = "v1"
BASE_URL = f"https://api.revenuecat.com/{API_VERSION}"

def check_entitlement(api_key, user_id, entitlement_id):
    """
    Checks if a user has an active entitlement using the RevenueCat API.

    This function provides a basic, direct server-to-server check.
    In a real-world scenario, you might want to cache these results
    to avoid hitting the API on every single protected action.

    Args:
        api_key (str): Your RevenueCat API Key (Secret).
        user_id (str): The Application User ID.
        entitlement_id (str): The identifier of the entitlement to check.

    Returns:
        bool: True if the user has an active entitlement, False otherwise.
        str: A status message.
    """
    if not api_key:
        return False, "API key is not configured. Please set REVENUECAT_API_KEY."

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    
    url = f"{BASE_URL}/subscribers/{user_id}"

    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()  # Raises an HTTPError for bad responses (4xx or 5xx)

        data = response.json()

        # Navigate through the subscriber object to find the entitlement
        entitlements = data.get("subscriber", {}).get("entitlements", {})

        if entitlement_id in entitlements:
            entitlement_info = entitlements[entitlement_id]
            # An entitlement is active if its 'expires_date' is null (for non-expiring)
            # or in the future.
            if entitlement_info.get("expires_date") is None or entitlement_info.get("expires_date") > "2023-01-01T00:00:00Z": # Replace with current time in a real app
                return True, f"User '{user_id}' has an active '{entitlement_id}' entitlement."
            else:
                return False, f"User '{user_id}' has an expired '{entitlement_id}' entitlement."
        else:
            return False, f"User '{user_id}' does not have the '{entitlement_id}' entitlement."

    except requests.exceptions.HTTPError as http_err:
        if http_err.response.status_code == 404:
            return False, f"Subscriber with App User ID '{user_id}' not found."
        return False, f"HTTP error occurred: {http_err}"
    except requests.exceptions.RequestException as req_err:
        return False, f"Request error occurred: {req_err}"
    except Exception as err:
        return False, f"An unexpected error occurred: {err}"

if __name__ == "__main__":
    print("--- RevenueCat Entitlement Check Demo ---")
    
    # In a real app, you would get the user_id from your authentication system.
    print(f"Checking for entitlement '{ENTITLEMENT_ID}' for user '{APP_USER_ID}'...")
    
    is_active, message = check_entitlement(REVENUECAT_API_KEY, APP_USER_ID, ENTITLEMENT_ID)
    
    print("\n--- Result ---")
    print(message)
    
    if is_active:
        print("\n✅ Access Granted: Unlocking premium features.")
        # Add your logic here to provide access to premium content or features.
    else:
        print("\n❌ Access Denied: User does not have required access.")
        # Guide the user towards your paywall or subscription screen.

