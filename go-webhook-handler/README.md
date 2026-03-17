# Go RevenueCat Webhook Handler

A lightweight, secure Go server for receiving and verifying RevenueCat webhooks. Webhooks are the most reliable way to sync RevenueCat subscription status with your own backend database.

## Features

- ✅ **HMAC Signature Verification:** Verifies the `X-Signature` header automatically if a secret is provided.
- ✅ **Type-safe Event Payload:** Includes a structured `WebhookPayload` struct covering common event fields.
- ✅ **Easy Routing:** Routes the payload to specific handler functions (`handleInitialPurchase`, `handleRenewal`, etc.) based on `event.type`.

## Getting Started

1. Set your environment variables:
   ```bash
   export PORT=8080
   export REVENUECAT_WEBHOOK_SECRET="your_shared_secret_here" # Optional but recommended
   ```

2. Run the server:
   ```bash
   go run main.go
   ```

3. Expose your local server to the internet using a tool like [ngrok](https://ngrok.com/):
   ```bash
   ngrok http 8080
   ```

4. Add your webhook URL (`https://your-ngrok-url.ngrok.io/revenuecat/webhook`) in the RevenueCat dashboard under **Project Settings > Webhooks**. Make sure to generate an authorization token and save it as your `REVENUECAT_WEBHOOK_SECRET`.

## Customizing Handlers

Inside `main.go`, look for the handler functions at the bottom of the file to add your own business logic:

```go
func handleInitialPurchase(p WebhookPayload) {
	// e.g., Update your database to grant premium access
	log.Printf("[ACTION] Granting access to %s for %v", p.Event.AppUserID, p.Event.EntitlementIDs)
}
```

## Production Considerations

- Webhooks can be retried by RevenueCat. Your handlers should ideally be **idempotent** (doing the same action twice shouldn't cause issues). Use the `EventID` field to prevent processing the exact same event multiple times if necessary.
- Return a `200 OK` as fast as possible so RevenueCat doesn't time out. If you have slow database operations or email sending, consider pushing the payload to a job queue (like RabbitMQ, Kafka, or a Go channel/worker pool) instead of handling it synchronously.

🐕 *Brought to you by ProfitDog*