
import hmac
import hashlib
import json
from flask import Flask, request, abort

app = Flask(__name__)

# This should be a secret stored securely, not hardcoded!
# For this example, we're reading it from an environment variable.
import os
WEBHOOK_SECRET = os.environ.get('WEBHOOK_SECRET', 'a_not_so_secret_key')

@app.route('/revenuecat-webhook', methods=['POST'])
def revenuecat_webhook():
    """
    Handles incoming webhooks from RevenueCat.
    - Verifies the signature to ensure the request is from RevenueCat.
    - Processes the event payload.
    """
    # 1. Verify the signature
    signature = request.headers.get('X-Signature')
    if not signature:
        print("Signature missing!")
        abort(400, 'Signature missing')

    try:
        # The request body is bytes, so we need to encode the secret
        mac = hmac.new(
            WEBHOOK_SECRET.encode('utf-8'), 
            request.data, 
            hashlib.sha256
        )
        expected_signature = mac.hexdigest()

        if not hmac.compare_digest(expected_signature, signature):
            print("Signature mismatch!")
            abort(403, 'Signature mismatch')
            
    except Exception as e:
        print(f"Error during signature validation: {e}")
        abort(500, 'Internal server error')

    # 2. Process the event
    event_data = request.json
    event_type = event_data.get('event', {}).get('type')
    
    print(f"Received valid webhook. Event type: {event_type}")
    print("Full payload:")
    print(json.dumps(event_data, indent=2))
    
    # --- Add your custom logic here ---
    # For example, you might grant entitlements, update your database,
    # or send the data to an analytics service.
    
    # Example: Handle a test event
    if event_type == 'TEST':
        print("This is a test event from RevenueCat. Everything is working!")

    # Example: Handle a subscription cancellation
    if event_type == 'CANCELLATION':
        app_user_id = event_data.get('event', {}).get('app_user_id')
        print(f"User {app_user_id} cancelled their subscription. Sad dog noises.")
    
    # --- End custom logic ---

    return "Webhook received successfully!", 200

if __name__ == '__main__':
    # For local testing, you can use a tool like ngrok to expose this endpoint
    # to the internet so RevenueCat's servers can reach it.
    print("Starting Flask server for RevenueCat webhooks...")
    print("Remember to set the WEBHOOK_SECRET environment variable.")
    app.run(port=5001, debug=True)
