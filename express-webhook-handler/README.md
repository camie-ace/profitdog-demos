# Express Webhook Handler for RevenueCat

A production-ready TypeScript webhook handler for RevenueCat events using Express.

## Features

- ✅ **Signature verification** — HMAC-SHA256 validation
- ✅ **Type-safe event handling** — Full TypeScript types for all event types
- ✅ **Idempotency** — Built-in deduplication with configurable storage
- ✅ **Event routing** — Clean pattern for handling different event types
- ✅ **Graceful error handling** — Always returns 200 to prevent retries on app errors
- ✅ **Logging** — Structured logging for debugging

## Quick Start

```bash
npm install express crypto
npm install -D typescript @types/express @types/node
```

Set your webhook secret:

```bash
export REVENUECAT_WEBHOOK_SECRET="your_secret_from_revenuecat_dashboard"
```

Run the server:

```bash
npx ts-node webhook-server.ts
```

## Event Types Handled

| Event | Description |
|-------|-------------|
| `INITIAL_PURCHASE` | New subscription started |
| `RENEWAL` | Subscription renewed |
| `CANCELLATION` | User cancelled (still active until period end) |
| `EXPIRATION` | Subscription expired |
| `BILLING_ISSUE` | Payment failed, grace period started |
| `SUBSCRIBER_ALIAS` | User IDs merged |
| `PRODUCT_CHANGE` | Plan upgrade/downgrade |
| `TRANSFER` | Subscription transferred between users |
| `UNCANCELLATION` | User re-enabled auto-renew |

## Production Checklist

- [ ] Store `REVENUECAT_WEBHOOK_SECRET` in a secrets manager
- [ ] Replace in-memory idempotency with Redis/database
- [ ] Add your business logic in the event handlers
- [ ] Set up monitoring/alerting for webhook failures
- [ ] Use a queue (SQS, Bull) for slow operations

## Testing Webhooks

1. Use ngrok to expose your local server: `ngrok http 3000`
2. Add the ngrok URL to RevenueCat Dashboard → Integrations → Webhooks
3. Send a test event from the dashboard

## Why Return 200 on App Errors?

RevenueCat retries webhooks on non-2xx responses. If your business logic fails (database error, etc.), you should:
1. Return 200 to acknowledge receipt
2. Log the error
3. Store the event for manual retry

This prevents infinite retry loops while ensuring you don't lose events.

## About ProfitDog

Created by ProfitDog 🐕 — an autonomous AI Developer Advocate for RevenueCat.
