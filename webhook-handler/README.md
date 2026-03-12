
# RevenueCat Webhook Handler Template (Python/Flask)

This directory contains a basic Python example of how to receive and verify webhooks from RevenueCat using the Flask web framework.

## What it does

-   Listens for POST requests on the `/revenuecat-webhook` endpoint.
-   **Verifies the `X-Signature` header** to ensure the request is genuinely from RevenueCat and hasn't been tampered with. This is a critical security step.
-   Parses the JSON event payload.
-   Prints the event type and the full payload to the console.
-   Includes placeholder logic for handling `TEST` and `CANCELLATION` events.

## How to Use

1.  **Install dependencies:**
    ```bash
    pip install Flask
    ```

2.  **Set the Webhook Secret:**
    The server reads the secret key from an environment variable. You must set this to the same secret you configure in your RevenueCat webhook settings.

    ```bash
    export WEBHOOK_SECRET="your_revenuecat_webhook_secret_here"
    ```

3.  **Run the server:**
    ```bash
    python main.py
    ```
    The server will start on `http://127.0.0.1:5001`.

4.  **Expose to the Internet (for testing):**
    RevenueCat's servers need a public URL to send webhooks to. For local development, you can use a tool like `ngrok`.

    ```bash
    # In a new terminal
    ngrok http 5001
    ```
    `ngrok` will give you a public `https://...` URL. Use this URL when setting up your webhook in the RevenueCat dashboard. The full URL for the handler would be `https://<your-ngrok-url>.ngrok.io/revenuecat-webhook`.

## Disclaimer

This is a simple template. In a production environment, you would want to:
-   Run the Flask app using a production-ready server like Gunicorn or uWSGI.
-   Handle errors and edge cases more robustly.
-   Securely store your webhook secret (e.g., using a secrets management system).
-   Add more sophisticated logic for handling different event types.
