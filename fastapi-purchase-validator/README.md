# FastAPI Purchase Validator

Server-side subscription verification with RevenueCat. A lightweight backend service for validating purchases beyond client-side SDK checks.

## Why Server-Side Validation?

Client-side purchase checks can be spoofed. For sensitive operations (unlocking content, granting access, API rate limits), validate server-side:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Client    │───▶│  Your API   │───▶│ RevenueCat  │
│  (App/Web)  │    │ (This code) │    │     API     │
└─────────────┘    └─────────────┘    └─────────────┘
     │                   │                   │
     │   "I'm premium"   │                   │
     │──────────────────▶│ "Let me verify"   │
     │                   │──────────────────▶│
     │                   │   ✅ or ❌        │
     │    ✅ / 403       │◀──────────────────│
     │◀──────────────────│                   │
```

## Features

- **Purchase Verification**: Validate if a user has active entitlements
- **Subscriber Info**: Get full subscription details (entitlements, billing status, grace periods)
- **Promotional Grants**: Issue time-limited premium access (for influencers, support, contests)
- **Webhook Handling**: Receive real-time subscription events with signature verification

## Quick Start

```bash
# Clone and install
cd fastapi-purchase-validator
pip install -r requirements.txt

# Set your API key
export REVENUECAT_API_KEY="your_secret_api_key_v1"
export REVENUECAT_WEBHOOK_SECRET="your_webhook_secret"  # optional

# Run
uvicorn main:app --reload
```

Visit `http://localhost:8000/docs` for interactive API documentation.

## API Endpoints

### `GET /subscriber/{app_user_id}`

Get full subscriber information including all entitlements.

```bash
curl http://localhost:8000/subscriber/user_123
```

Response:
```json
{
  "app_user_id": "user_123",
  "entitlements": {
    "premium": {
      "is_active": true,
      "expires_date": "2024-12-15T00:00:00Z",
      "will_renew": true,
      "is_in_grace_period": false,
      "billing_issue_detected": false
    }
  },
  "active_subscriptions": ["$rc_annual"],
  "has_active_entitlement": true
}
```

### `POST /verify`

Quick verification for access control. Use this before granting premium features.

```bash
curl -X POST http://localhost:8000/verify \
  -H "Content-Type: application/json" \
  -d '{"app_user_id": "user_123", "entitlement_id": "premium"}'
```

Response:
```json
{
  "valid": true,
  "app_user_id": "user_123",
  "entitlement_id": "premium",
  "expires_date": "2024-12-15T00:00:00Z",
  "reason": "active"
}
```

Possible `reason` values:
- `active` - Subscription is active
- `active_grace_period` - Active but in grace period (payment pending)
- `active_billing_issue` - Active but billing issue detected
- `entitlement_expired` - Was subscribed, now expired
- `entitlement_not_found` - Never had this entitlement
- `subscriber_not_found` - User doesn't exist in RevenueCat
- `no_active_entitlements` - User exists but no active entitlements

### `POST /entitlements/grant`

Grant promotional access (requires secret API key with write access).

```bash
curl -X POST http://localhost:8000/entitlements/grant \
  -H "Content-Type: application/json" \
  -d '{
    "app_user_id": "influencer_456",
    "entitlement_id": "premium",
    "duration_days": 90
  }'
```

### `POST /webhook`

Receives RevenueCat webhooks. Configure in your RevenueCat dashboard:
`https://your-domain.com/webhook`

Supports all event types:
- `INITIAL_PURCHASE`
- `RENEWAL`
- `CANCELLATION`
- `BILLING_ISSUE`
- `SUBSCRIBER_ALIAS`
- And more...

## Integration Examples

### Python (requests)

```python
import requests

def check_premium(user_id: str) -> bool:
    response = requests.post(
        "https://your-api.com/verify",
        json={"app_user_id": user_id, "entitlement_id": "premium"}
    )
    return response.json()["valid"]
```

### JavaScript (fetch)

```javascript
async function checkPremium(userId) {
  const response = await fetch('https://your-api.com/verify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ 
      app_user_id: userId, 
      entitlement_id: 'premium' 
    })
  });
  const data = await response.json();
  return data.valid;
}
```

### Middleware Example

```python
from fastapi import Depends, HTTPException

async def require_premium(user_id: str = Depends(get_current_user)):
    """Dependency that requires premium subscription."""
    response = await verify_purchase(VerifyRequest(
        app_user_id=user_id,
        entitlement_id="premium"
    ))
    if not response.valid:
        raise HTTPException(403, "Premium subscription required")
    return response

@app.get("/premium-content")
async def get_premium_content(sub: VerifyResponse = Depends(require_premium)):
    return {"content": "Secret premium stuff", "expires": sub.expires_date}
```

## Production Deployment

1. **Use environment variables** for API keys (never commit them)
2. **Add rate limiting** to prevent abuse
3. **Add authentication** to your API endpoints
4. **Cache subscriber data** for frequently-checked users
5. **Set up webhook retry handling** (RevenueCat retries failed webhooks)

### Docker

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `REVENUECAT_API_KEY` | Yes | Your secret API key (starts with `sk_`) |
| `REVENUECAT_WEBHOOK_SECRET` | No | Webhook signing secret for verification |

## Related

- [RevenueCat REST API Docs](https://www.revenuecat.com/docs/api-v1)
- [Webhook Events Reference](https://www.revenuecat.com/docs/webhooks)

---

Created by ProfitDog 🐕 | [profitdog-demos](https://github.com/camie-ace/profitdog-demos)
