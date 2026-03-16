"""
FastAPI Purchase Validator - Server-side subscription verification with RevenueCat

A lightweight backend service for verifying purchases and managing entitlements
server-side. Essential for apps that need secure purchase validation beyond
client-side SDK checks.

Created by ProfitDog 🐕
https://github.com/camie-ace/profitdog-demos
"""

import os
import hashlib
import hmac
import time
from datetime import datetime, timezone
from typing import Optional, Literal
from functools import lru_cache

import httpx
from fastapi import FastAPI, HTTPException, Header, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


# =============================================================================
# Configuration
# =============================================================================

class Settings(BaseModel):
    """App configuration - load from environment variables."""
    revenuecat_api_key: str = Field(default_factory=lambda: os.getenv("REVENUECAT_API_KEY", ""))
    revenuecat_webhook_secret: str = Field(default_factory=lambda: os.getenv("REVENUECAT_WEBHOOK_SECRET", ""))
    cache_ttl_seconds: int = 60  # How long to cache subscriber data
    
    @property
    def is_configured(self) -> bool:
        return bool(self.revenuecat_api_key)


@lru_cache()
def get_settings() -> Settings:
    return Settings()


# =============================================================================
# Models
# =============================================================================

class EntitlementStatus(BaseModel):
    """Simplified entitlement status for API responses."""
    is_active: bool
    identifier: str
    expires_date: Optional[datetime] = None
    product_identifier: Optional[str] = None
    purchase_date: Optional[datetime] = None
    will_renew: bool = False
    is_in_grace_period: bool = False
    billing_issue_detected: bool = False


class SubscriberInfo(BaseModel):
    """Subscriber information response."""
    app_user_id: str
    first_seen: Optional[datetime] = None
    entitlements: dict[str, EntitlementStatus]
    active_subscriptions: list[str]
    has_active_entitlement: bool
    
    
class VerifyRequest(BaseModel):
    """Request body for purchase verification."""
    app_user_id: str
    entitlement_id: Optional[str] = None  # If None, checks for any active entitlement


class VerifyResponse(BaseModel):
    """Response for purchase verification."""
    valid: bool
    app_user_id: str
    entitlement_id: Optional[str] = None
    expires_date: Optional[datetime] = None
    reason: str


class GrantEntitlementRequest(BaseModel):
    """Request to grant a promotional entitlement."""
    app_user_id: str
    entitlement_id: str
    duration_days: int = 30
    start_time_ms: Optional[int] = None  # Defaults to now


# =============================================================================
# RevenueCat API Client
# =============================================================================

class RevenueCatClient:
    """Async client for RevenueCat REST API v1."""
    
    BASE_URL = "https://api.revenuecat.com/v1"
    
    def __init__(self, api_key: str):
        self.api_key = api_key
        self._client: Optional[httpx.AsyncClient] = None
    
    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=self.BASE_URL,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                timeout=30.0,
            )
        return self._client
    
    async def get_subscriber(self, app_user_id: str) -> dict:
        """Fetch subscriber data from RevenueCat."""
        client = await self._get_client()
        
        # URL-encode the user ID (handles emails, etc.)
        encoded_id = httpx.URL(f"/subscribers/{app_user_id}").path
        
        response = await client.get(encoded_id)
        
        if response.status_code == 404:
            raise HTTPException(status_code=404, detail="Subscriber not found")
        elif response.status_code != 200:
            raise HTTPException(
                status_code=502, 
                detail=f"RevenueCat API error: {response.status_code}"
            )
        
        return response.json()
    
    async def grant_promotional(
        self,
        app_user_id: str,
        entitlement_id: str,
        duration_days: int,
        start_time_ms: Optional[int] = None,
    ) -> dict:
        """Grant a promotional entitlement to a user."""
        client = await self._get_client()
        
        if start_time_ms is None:
            start_time_ms = int(time.time() * 1000)
        
        end_time_ms = start_time_ms + (duration_days * 24 * 60 * 60 * 1000)
        
        response = await client.post(
            f"/subscribers/{app_user_id}/entitlements/{entitlement_id}/promotional",
            json={
                "duration": "custom",
                "start_time_ms": start_time_ms,
                "end_time_ms": end_time_ms,
            }
        )
        
        if response.status_code not in (200, 201):
            raise HTTPException(
                status_code=502,
                detail=f"Failed to grant entitlement: {response.text}"
            )
        
        return response.json()
    
    async def close(self):
        if self._client:
            await self._client.aclose()
            self._client = None


# Singleton client instance
_rc_client: Optional[RevenueCatClient] = None


def get_revenuecat_client(settings: Settings = Depends(get_settings)) -> RevenueCatClient:
    global _rc_client
    if _rc_client is None:
        if not settings.is_configured:
            raise HTTPException(
                status_code=503,
                detail="RevenueCat API key not configured"
            )
        _rc_client = RevenueCatClient(settings.revenuecat_api_key)
    return _rc_client


# =============================================================================
# Helper Functions
# =============================================================================

def parse_subscriber_response(data: dict) -> SubscriberInfo:
    """Parse RevenueCat API response into our clean model."""
    subscriber = data.get("subscriber", {})
    
    entitlements = {}
    raw_entitlements = subscriber.get("entitlements", {})
    
    for ent_id, ent_data in raw_entitlements.items():
        expires_str = ent_data.get("expires_date")
        purchase_str = ent_data.get("purchase_date")
        
        expires_date = None
        if expires_str:
            expires_date = datetime.fromisoformat(expires_str.replace("Z", "+00:00"))
        
        purchase_date = None
        if purchase_str:
            purchase_date = datetime.fromisoformat(purchase_str.replace("Z", "+00:00"))
        
        # Check if currently active
        is_active = expires_date is None or expires_date > datetime.now(timezone.utc)
        
        # Billing issue detection
        billing_issue = ent_data.get("billing_issue_detected_at") is not None
        
        # Grace period check
        grace_period_expires = ent_data.get("grace_period_expires_date")
        in_grace = False
        if grace_period_expires:
            grace_dt = datetime.fromisoformat(grace_period_expires.replace("Z", "+00:00"))
            in_grace = grace_dt > datetime.now(timezone.utc)
        
        entitlements[ent_id] = EntitlementStatus(
            is_active=is_active,
            identifier=ent_id,
            expires_date=expires_date,
            product_identifier=ent_data.get("product_identifier"),
            purchase_date=purchase_date,
            will_renew=ent_data.get("unsubscribe_detected_at") is None,
            is_in_grace_period=in_grace,
            billing_issue_detected=billing_issue,
        )
    
    # Get active subscriptions
    active_subs = list(subscriber.get("subscriptions", {}).keys())
    
    # Check if any entitlement is active
    has_active = any(e.is_active for e in entitlements.values())
    
    first_seen_str = subscriber.get("first_seen")
    first_seen = None
    if first_seen_str:
        first_seen = datetime.fromisoformat(first_seen_str.replace("Z", "+00:00"))
    
    return SubscriberInfo(
        app_user_id=subscriber.get("original_app_user_id", "unknown"),
        first_seen=first_seen,
        entitlements=entitlements,
        active_subscriptions=active_subs,
        has_active_entitlement=has_active,
    )


def verify_webhook_signature(
    payload: bytes,
    signature: str,
    secret: str,
) -> bool:
    """Verify RevenueCat webhook signature using HMAC-SHA256."""
    expected = hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(expected, signature)


# =============================================================================
# FastAPI App
# =============================================================================

app = FastAPI(
    title="Purchase Validator API",
    description="Server-side subscription verification with RevenueCat",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for your domain in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health_check(settings: Settings = Depends(get_settings)):
    """Health check endpoint."""
    return {
        "status": "healthy",
        "configured": settings.is_configured,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/subscriber/{app_user_id}", response_model=SubscriberInfo)
async def get_subscriber(
    app_user_id: str,
    rc: RevenueCatClient = Depends(get_revenuecat_client),
):
    """
    Get full subscriber information.
    
    Returns entitlements, active subscriptions, and billing status.
    """
    data = await rc.get_subscriber(app_user_id)
    return parse_subscriber_response(data)


@app.post("/verify", response_model=VerifyResponse)
async def verify_purchase(
    request: VerifyRequest,
    rc: RevenueCatClient = Depends(get_revenuecat_client),
):
    """
    Verify if a user has an active subscription/entitlement.
    
    This is the main endpoint for server-side purchase validation.
    Use this before granting access to premium features.
    """
    try:
        data = await rc.get_subscriber(request.app_user_id)
        subscriber = parse_subscriber_response(data)
    except HTTPException as e:
        if e.status_code == 404:
            return VerifyResponse(
                valid=False,
                app_user_id=request.app_user_id,
                reason="subscriber_not_found",
            )
        raise
    
    # If specific entitlement requested, check that one
    if request.entitlement_id:
        entitlement = subscriber.entitlements.get(request.entitlement_id)
        
        if not entitlement:
            return VerifyResponse(
                valid=False,
                app_user_id=request.app_user_id,
                entitlement_id=request.entitlement_id,
                reason="entitlement_not_found",
            )
        
        if not entitlement.is_active:
            return VerifyResponse(
                valid=False,
                app_user_id=request.app_user_id,
                entitlement_id=request.entitlement_id,
                expires_date=entitlement.expires_date,
                reason="entitlement_expired",
            )
        
        # Active!
        reason = "active"
        if entitlement.is_in_grace_period:
            reason = "active_grace_period"
        elif entitlement.billing_issue_detected:
            reason = "active_billing_issue"
        
        return VerifyResponse(
            valid=True,
            app_user_id=request.app_user_id,
            entitlement_id=request.entitlement_id,
            expires_date=entitlement.expires_date,
            reason=reason,
        )
    
    # Otherwise check for any active entitlement
    if subscriber.has_active_entitlement:
        # Find the first active one
        for ent_id, ent in subscriber.entitlements.items():
            if ent.is_active:
                return VerifyResponse(
                    valid=True,
                    app_user_id=request.app_user_id,
                    entitlement_id=ent_id,
                    expires_date=ent.expires_date,
                    reason="active",
                )
    
    return VerifyResponse(
        valid=False,
        app_user_id=request.app_user_id,
        reason="no_active_entitlements",
    )


@app.post("/entitlements/grant")
async def grant_entitlement(
    request: GrantEntitlementRequest,
    rc: RevenueCatClient = Depends(get_revenuecat_client),
):
    """
    Grant a promotional entitlement to a user.
    
    Useful for:
    - Influencer codes
    - Customer support credits
    - Contest prizes
    - Beta tester access
    """
    result = await rc.grant_promotional(
        app_user_id=request.app_user_id,
        entitlement_id=request.entitlement_id,
        duration_days=request.duration_days,
        start_time_ms=request.start_time_ms,
    )
    
    return {
        "success": True,
        "app_user_id": request.app_user_id,
        "entitlement_id": request.entitlement_id,
        "duration_days": request.duration_days,
        "subscriber": parse_subscriber_response(result),
    }


@app.post("/webhook")
async def handle_webhook(
    request: Request,
    x_revenuecat_signature: str = Header(None, alias="X-RevenueCat-Signature"),
    settings: Settings = Depends(get_settings),
):
    """
    Handle RevenueCat webhooks.
    
    Receives real-time events for:
    - New purchases
    - Renewals
    - Cancellations
    - Billing issues
    - And more
    
    Configure your webhook URL in RevenueCat dashboard.
    """
    body = await request.body()
    
    # Verify signature if secret is configured
    if settings.revenuecat_webhook_secret:
        if not x_revenuecat_signature:
            raise HTTPException(status_code=401, detail="Missing signature")
        
        if not verify_webhook_signature(
            body,
            x_revenuecat_signature,
            settings.revenuecat_webhook_secret,
        ):
            raise HTTPException(status_code=401, detail="Invalid signature")
    
    # Parse event
    import json
    event = json.loads(body)
    
    event_type = event.get("event", {}).get("type", "UNKNOWN")
    app_user_id = event.get("event", {}).get("app_user_id")
    
    # Log the event (in production, you'd process this properly)
    print(f"📬 Webhook received: {event_type} for {app_user_id}")
    
    # Handle different event types
    # In production, you'd trigger appropriate business logic here
    match event_type:
        case "INITIAL_PURCHASE":
            print(f"🎉 New subscriber: {app_user_id}")
            # TODO: Send welcome email, unlock features, etc.
            
        case "RENEWAL":
            print(f"🔄 Renewal: {app_user_id}")
            # TODO: Update internal records
            
        case "CANCELLATION":
            print(f"😢 Cancellation: {app_user_id}")
            # TODO: Trigger win-back campaign
            
        case "BILLING_ISSUE":
            print(f"⚠️ Billing issue: {app_user_id}")
            # TODO: Send recovery email
            
        case "SUBSCRIBER_ALIAS":
            print(f"🔗 Alias created: {app_user_id}")
            # TODO: Merge user records if needed
    
    # Always return 200 to acknowledge receipt
    return {"received": True, "event_type": event_type}


# =============================================================================
# Startup/Shutdown
# =============================================================================

@app.on_event("shutdown")
async def shutdown():
    global _rc_client
    if _rc_client:
        await _rc_client.close()


# =============================================================================
# Run with: uvicorn main:app --reload
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
