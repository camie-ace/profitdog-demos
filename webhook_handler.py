"""
RevenueCat Webhook Handler - by ProfitDog 🐕

A production-ready webhook handler for RevenueCat events.
Handles subscription lifecycle events with proper validation,
idempotency, and error handling.

Works with: Flask, FastAPI, or any WSGI-compatible framework.
"""

import hmac
import hashlib
import json
import logging
from datetime import datetime
from functools import wraps
from typing import Callable, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("revenuecat_webhooks")


# =============================================================================
# Webhook Event Types
# =============================================================================

class EventType:
    """RevenueCat webhook event types."""
    # Subscription lifecycle
    INITIAL_PURCHASE = "INITIAL_PURCHASE"
    RENEWAL = "RENEWAL"
    CANCELLATION = "CANCELLATION"
    UNCANCELLATION = "UNCANCELLATION"
    EXPIRATION = "EXPIRATION"
    
    # Billing issues
    BILLING_ISSUE = "BILLING_ISSUE"
    
    # Product changes
    PRODUCT_CHANGE = "PRODUCT_CHANGE"
    
    # Transfers
    TRANSFER = "TRANSFER"
    
    # Non-subscription
    NON_RENEWING_PURCHASE = "NON_RENEWING_PURCHASE"
    
    # Testing
    TEST = "TEST"


# =============================================================================
# Signature Verification
# =============================================================================

def verify_signature(payload: bytes, signature: str, secret: str) -> bool:
    """
    Verify RevenueCat webhook signature.
    
    Args:
        payload: Raw request body bytes
        signature: X-RevenueCat-Signature header value
        secret: Your webhook secret from RevenueCat dashboard
    
    Returns:
        True if signature is valid
    """
    expected = hmac.new(
        secret.encode('utf-8'),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(expected, signature)


# =============================================================================
# Event Processing
# =============================================================================

class WebhookEvent:
    """Parsed webhook event with helper properties."""
    
    def __init__(self, data: dict):
        self.raw = data
        self.event = data.get("event", {})
        self.api_version = data.get("api_version")
    
    @property
    def event_type(self) -> str:
        return self.event.get("type", "")
    
    @property
    def app_user_id(self) -> str:
        return self.event.get("app_user_id", "")
    
    @property
    def original_app_user_id(self) -> str:
        """Original user ID (useful for transfers)."""
        return self.event.get("original_app_user_id", "")
    
    @property
    def product_id(self) -> str:
        return self.event.get("product_id", "")
    
    @property
    def entitlement_ids(self) -> list:
        return self.event.get("entitlement_ids", [])
    
    @property
    def event_timestamp_ms(self) -> int:
        return self.event.get("event_timestamp_ms", 0)
    
    @property
    def event_timestamp(self) -> Optional[datetime]:
        if self.event_timestamp_ms:
            return datetime.fromtimestamp(self.event_timestamp_ms / 1000)
        return None
    
    @property
    def expiration_at_ms(self) -> int:
        return self.event.get("expiration_at_ms", 0)
    
    @property
    def is_family_share(self) -> bool:
        return self.event.get("is_family_share", False)
    
    @property
    def store(self) -> str:
        """APP_STORE, PLAY_STORE, STRIPE, etc."""
        return self.event.get("store", "")
    
    @property
    def environment(self) -> str:
        """SANDBOX or PRODUCTION."""
        return self.event.get("environment", "")
    
    @property
    def is_sandbox(self) -> bool:
        return self.environment == "SANDBOX"
    
    @property
    def price_in_purchased_currency(self) -> float:
        return self.event.get("price_in_purchased_currency", 0.0)
    
    @property
    def currency(self) -> str:
        return self.event.get("currency", "")


# =============================================================================
# Handler Registry
# =============================================================================

class WebhookHandler:
    """
    Webhook handler with event routing and middleware support.
    
    Usage:
        handler = WebhookHandler(webhook_secret="your_secret")
        
        @handler.on(EventType.INITIAL_PURCHASE)
        def handle_new_sub(event: WebhookEvent):
            print(f"New subscriber: {event.app_user_id}")
            
        # In your route:
        result = handler.process(request.data, request.headers)
    """
    
    def __init__(self, webhook_secret: str, verify_signatures: bool = True):
        self.webhook_secret = webhook_secret
        self.verify_signatures = verify_signatures
        self._handlers: dict[str, list[Callable]] = {}
        self._processed_events: set = set()  # Simple in-memory idempotency
    
    def on(self, event_type: str):
        """Decorator to register an event handler."""
        def decorator(func: Callable):
            if event_type not in self._handlers:
                self._handlers[event_type] = []
            self._handlers[event_type].append(func)
            return func
        return decorator
    
    def _get_idempotency_key(self, event: WebhookEvent) -> str:
        """Generate idempotency key from event."""
        return f"{event.event_type}:{event.app_user_id}:{event.event_timestamp_ms}"
    
    def process(self, payload: bytes, headers: dict) -> dict:
        """
        Process incoming webhook.
        
        Args:
            payload: Raw request body
            headers: Request headers dict
            
        Returns:
            dict with 'success' bool and optional 'error' message
        """
        # Verify signature
        if self.verify_signatures:
            signature = headers.get("X-RevenueCat-Signature", "")
            if not signature:
                logger.warning("Missing webhook signature")
                return {"success": False, "error": "Missing signature"}
            
            if not verify_signature(payload, signature, self.webhook_secret):
                logger.warning("Invalid webhook signature")
                return {"success": False, "error": "Invalid signature"}
        
        # Parse event
        try:
            data = json.loads(payload)
            event = WebhookEvent(data)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse webhook: {e}")
            return {"success": False, "error": "Invalid JSON"}
        
        # Idempotency check
        idempotency_key = self._get_idempotency_key(event)
        if idempotency_key in self._processed_events:
            logger.info(f"Duplicate event ignored: {idempotency_key}")
            return {"success": True, "message": "Duplicate event"}
        
        # Log event
        logger.info(
            f"Processing {event.event_type} for {event.app_user_id} "
            f"[{event.environment}] product={event.product_id}"
        )
        
        # Route to handlers
        handlers = self._handlers.get(event.event_type, [])
        if not handlers:
            logger.debug(f"No handlers for {event.event_type}")
        
        for handler_func in handlers:
            try:
                handler_func(event)
            except Exception as e:
                logger.exception(f"Handler error: {e}")
                # Continue processing other handlers
        
        # Mark as processed
        self._processed_events.add(idempotency_key)
        
        # Cleanup old keys (simple approach - in production use Redis/DB)
        if len(self._processed_events) > 10000:
            self._processed_events.clear()
        
        return {"success": True}


# =============================================================================
# Flask Example
# =============================================================================

def create_flask_app(webhook_secret: str):
    """Example Flask app with webhook endpoint."""
    from flask import Flask, request, jsonify
    
    app = Flask(__name__)
    handler = WebhookHandler(webhook_secret)
    
    # Register handlers
    @handler.on(EventType.INITIAL_PURCHASE)
    def on_new_subscription(event: WebhookEvent):
        logger.info(f"🎉 New subscriber: {event.app_user_id}")
        logger.info(f"   Product: {event.product_id}")
        logger.info(f"   Entitlements: {event.entitlement_ids}")
        # TODO: Update your database, send welcome email, etc.
    
    @handler.on(EventType.RENEWAL)
    def on_renewal(event: WebhookEvent):
        logger.info(f"🔄 Renewal: {event.app_user_id} - {event.product_id}")
        # TODO: Update subscription end date in your database
    
    @handler.on(EventType.CANCELLATION)
    def on_cancellation(event: WebhookEvent):
        logger.info(f"😢 Cancellation: {event.app_user_id}")
        # TODO: Trigger win-back campaign, collect feedback
    
    @handler.on(EventType.EXPIRATION)
    def on_expiration(event: WebhookEvent):
        logger.info(f"⏰ Expired: {event.app_user_id}")
        # TODO: Revoke access, send re-engagement email
    
    @handler.on(EventType.BILLING_ISSUE)
    def on_billing_issue(event: WebhookEvent):
        logger.warning(f"💳 Billing issue: {event.app_user_id}")
        # TODO: Send payment update reminder, pause dunning emails
    
    @handler.on(EventType.PRODUCT_CHANGE)
    def on_product_change(event: WebhookEvent):
        logger.info(f"📦 Product change: {event.app_user_id} -> {event.product_id}")
        # TODO: Handle upgrade/downgrade logic
    
    # Webhook endpoint
    @app.route("/webhooks/revenuecat", methods=["POST"])
    def revenuecat_webhook():
        result = handler.process(
            request.data,
            dict(request.headers)
        )
        
        if result.get("success"):
            return jsonify({"status": "ok"}), 200
        else:
            return jsonify({"error": result.get("error")}), 400
    
    return app


# =============================================================================
# FastAPI Example
# =============================================================================

def create_fastapi_app(webhook_secret: str):
    """Example FastAPI app with webhook endpoint."""
    from fastapi import FastAPI, Request, HTTPException
    
    app = FastAPI()
    handler = WebhookHandler(webhook_secret)
    
    @handler.on(EventType.INITIAL_PURCHASE)
    def on_new_subscription(event: WebhookEvent):
        # Your logic here
        pass
    
    @app.post("/webhooks/revenuecat")
    async def revenuecat_webhook(request: Request):
        body = await request.body()
        headers = dict(request.headers)
        
        result = handler.process(body, headers)
        
        if not result.get("success"):
            raise HTTPException(status_code=400, detail=result.get("error"))
        
        return {"status": "ok"}
    
    return app


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    import os
    
    secret = os.environ.get("REVENUECAT_WEBHOOK_SECRET", "test_secret")
    
    print("Starting webhook handler demo...")
    print("Run with: REVENUECAT_WEBHOOK_SECRET=your_secret python webhook_handler.py")
    print()
    
    # Demo: Create Flask app
    try:
        app = create_flask_app(secret)
        print("Flask app created. Run with:")
        print("  flask --app webhook_handler:create_flask_app run --port 8000")
    except ImportError:
        print("Flask not installed. Install with: pip install flask")
    
    print()
    print("For production, use ngrok or similar to expose your local server:")
    print("  ngrok http 8000")
    print()
    print("Then configure the webhook URL in RevenueCat dashboard:")
    print("  https://your-ngrok-url.ngrok.io/webhooks/revenuecat")
