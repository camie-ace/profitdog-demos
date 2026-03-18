# Python: Entitlement Checking Pattern

This example demonstrates a server-side pattern for checking if a user has an active entitlement using the RevenueCat API. This is useful for protecting server-side resources, unlocking features in a web app, or validating access without relying solely on the client-side SDK.

## `entitlement_checker.py`

### What It Does

This script provides a function `check_entitlement` that takes a RevenueCat API key, an App User ID, and an Entitlement ID, and determines if that entitlement is currently active for the user.

### How It Works

1.  **Configuration**: It reads your RevenueCat API key from an environment variable `REVENUECAT_API_KEY`.
2.  **API Call**: It makes a GET request to the `/v1/subscribers/{app_user_id}` endpoint.
3.  **Authorization**: It uses your secret API key as a Bearer token in the `Authorization` header.
4.  **Parsing**: It parses the JSON response to find the `entitlements` object.
5.  **Validation**: It checks if the specified entitlement exists and if its `expires_date` is in the future (or `null`, for non-expiring purchases).
6.  **Result**: It returns a boolean indicating active status and a descriptive message.

### How to Use

1.  **Set Environment Variable**: Before running, set your API key.
    ```bash
    export REVENUECAT_API_KEY="your_rc_api_key_here"
    ```

2.  **Modify Placeholders**: Open the script and change the `APP_USER_ID` and `ENTITLEMENT_ID` placeholders to match a real user and entitlement in your project.

3.  **Run the script**:
    ```bash
    python entitlement_checker.py
    ```

### Disclaimer

This is a simple, direct example. For a production environment, consider:
-   **Caching**: Cache the entitlement status for a few minutes to reduce API calls and improve performance.
-   **Webhooks**: Use RevenueCat webhooks to keep your server's entitlement state in sync in real-time, which can be more efficient than polling the API.
-   **Error Handling**: Build more robust error handling for network issues or unexpected API responses.
