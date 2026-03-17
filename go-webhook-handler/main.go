package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
)

// EventType represents the types of events sent by RevenueCat webhooks
type EventType string

const (
	EventInitialPurchase     EventType = "INITIAL_PURCHASE"
	EventRenewal             EventType = "RENEWAL"
	EventCancellation        EventType = "CANCELLATION"
	EventUncancellation      EventType = "UNCANCELLATION"
	EventNonRenewingPurchase EventType = "NON_RENEWING_PURCHASE"
	EventSubscriptionPaused  EventType = "SUBSCRIPTION_PAUSED"
	EventExpiration          EventType = "EXPIRATION"
	EventBillingIssue        EventType = "BILLING_ISSUE"
	EventProductChange       EventType = "PRODUCT_CHANGE"
	EventTransfer            EventType = "TRANSFER"
)

// WebhookPayload represents the structure of the RevenueCat webhook payload
type WebhookPayload struct {
	Event struct {
		EventID            string    `json:"id"`
		Type               EventType `json:"type"`
		AppUserID          string    `json:"app_user_id"`
		OriginalAppUserID  string    `json:"original_app_user_id"`
		Aliases            []string  `json:"aliases"`
		ProductID          string    `json:"product_id"`
		EntitlementIDs     []string  `json:"entitlement_ids"`
		PeriodType         string    `json:"period_type"`
		PurchasedAtMs      int64     `json:"purchased_at_ms"`
		ExpirationAtMs     int64     `json:"expiration_at_ms"`
		Environment        string    `json:"environment"`
		IsFamilyShare      bool      `json:"is_family_share"`
		CountryCode        string    `json:"country_code"`
		Currency           string    `json:"currency"`
		Price              float64   `json:"price"`
		PriceInPurchasedCurrency float64 `json:"price_in_purchased_currency"`
		Store              string    `json:"store"`
		CancelReason       string    `json:"cancel_reason,omitempty"`
	} `json:"event"`
	APIVersion string `json:"api_version"`
}

// Config holds the application configuration
type Config struct {
	WebhookSecret string
	Port          string
}

func main() {
	config := Config{
		WebhookSecret: os.Getenv("REVENUECAT_WEBHOOK_SECRET"),
		Port:          os.Getenv("PORT"),
	}

	if config.Port == "" {
		config.Port = "8080"
	}

	http.HandleFunc("/revenuecat/webhook", func(w http.ResponseWriter, r *http.Request) {
		handleWebhook(w, r, config.WebhookSecret)
	})

	log.Printf("Starting server on port %s", config.Port)
	if err := http.ListenAndServe(":"+config.Port, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func handleWebhook(w http.ResponseWriter, r *http.Request, secret string) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("Error reading body: %v", err)
		http.Error(w, "Error reading request body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	// Verify the webhook signature if a secret is configured
	if secret != "" {
		signature := r.Header.Get("X-Signature")
		if signature == "" {
			log.Println("Missing X-Signature header")
			http.Error(w, "Missing signature header", http.StatusUnauthorized)
			return
		}

		if !verifySignature(signature, secret, bodyBytes) {
			log.Println("Invalid webhook signature")
			http.Error(w, "Invalid signature", http.StatusUnauthorized)
			return
		}
	}

	var payload WebhookPayload
	if err := json.Unmarshal(bodyBytes, &payload); err != nil {
		log.Printf("Error parsing JSON payload: %v", err)
		http.Error(w, "Error parsing JSON", http.StatusBadRequest)
		return
	}

	log.Printf("Received %s event for user %s (Product: %s)", 
		payload.Event.Type, payload.Event.AppUserID, payload.Event.ProductID)

	// Route based on event type
	switch payload.Event.Type {
	case EventInitialPurchase:
		handleInitialPurchase(payload)
	case EventRenewal:
		handleRenewal(payload)
	case EventCancellation:
		handleCancellation(payload)
	case EventExpiration:
		handleExpiration(payload)
	case EventBillingIssue:
		handleBillingIssue(payload)
	default:
		log.Printf("Unhandled event type: %s", payload.Event.Type)
	}

	// Always return 200 OK so RevenueCat knows we received it
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, `{"status": "ok"}`)
}

// verifySignature checks the X-Signature header against the payload and secret
func verifySignature(signature, secret string, body []byte) bool {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write(body)
	expectedSignature := base64.StdEncoding.EncodeToString(h.Sum(nil))
	
	return hmac.Equal([]byte(signature), []byte(expectedSignature))
}

// Example Handlers
func handleInitialPurchase(p WebhookPayload) {
	// e.g., Update database to grant premium access, send welcome email
	log.Printf("[ACTION] Granting access to %s for %v", p.Event.AppUserID, p.Event.EntitlementIDs)
}

func handleRenewal(p WebhookPayload) {
	// e.g., Update subscription end date in your database
	log.Printf("[ACTION] Subscription renewed for %s", p.Event.AppUserID)
}

func handleCancellation(p WebhookPayload) {
	// e.g., Mark auto-renew as false in database, send churn recovery email
	log.Printf("[ACTION] Subscription cancelled for %s (Reason: %s)", p.Event.AppUserID, p.Event.CancelReason)
}

func handleExpiration(p WebhookPayload) {
	// e.g., Revoke access, trigger "subscription expired" email
	log.Printf("[ACTION] Subscription expired for %s. Revoking access to %v", p.Event.AppUserID, p.Event.EntitlementIDs)
}

func handleBillingIssue(p WebhookPayload) {
	// e.g., Send notification to update payment method
	log.Printf("[ACTION] Billing issue detected for %s", p.Event.AppUserID)
}
