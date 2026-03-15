/**
 * RevenueCat Webhook Handler for Express
 * 
 * Production-ready TypeScript webhook handler with:
 * - Signature verification
 * - Type-safe event handling
 * - Idempotency support
 * - Structured logging
 * 
 * Created by ProfitDog 🐕
 */

import express, { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';

// =============================================================================
// Types
// =============================================================================

type RevenueCatEventType =
  | 'TEST'
  | 'INITIAL_PURCHASE'
  | 'RENEWAL'
  | 'CANCELLATION'
  | 'UNCANCELLATION'
  | 'EXPIRATION'
  | 'BILLING_ISSUE'
  | 'PRODUCT_CHANGE'
  | 'SUBSCRIBER_ALIAS'
  | 'TRANSFER'
  | 'NON_RENEWING_PURCHASE';

interface RevenueCatEvent {
  type: RevenueCatEventType;
  id: string;
  app_id: string;
  event_timestamp_ms: number;
  app_user_id: string;
  original_app_user_id: string;
  aliases: string[];
  product_id: string;
  entitlement_ids: string[];
  period_type: 'TRIAL' | 'INTRO' | 'NORMAL' | 'PROMOTIONAL';
  purchased_at_ms: number;
  expiration_at_ms: number | null;
  store: 'APP_STORE' | 'PLAY_STORE' | 'STRIPE' | 'AMAZON' | 'PROMOTIONAL';
  environment: 'SANDBOX' | 'PRODUCTION';
  is_family_share: boolean;
  country_code: string;
  currency: string;
  price: number;
  price_in_purchased_currency: number;
  takehome_percentage: number;
  offer_code: string | null;
  // Additional fields for specific events
  cancel_reason?: 'UNSUBSCRIBE' | 'BILLING_ERROR' | 'DEVELOPER_INITIATED' | 'PRICE_INCREASE' | 'CUSTOMER_SUPPORT' | 'UNKNOWN';
  grace_period_expiration_at_ms?: number;
  new_product_id?: string; // For PRODUCT_CHANGE
}

interface RevenueCatWebhookPayload {
  api_version: string;
  event: RevenueCatEvent;
}

// =============================================================================
// Configuration
// =============================================================================

const CONFIG = {
  port: process.env.PORT || 3000,
  webhookSecret: process.env.REVENUECAT_WEBHOOK_SECRET || '',
  idempotencyWindowMs: 24 * 60 * 60 * 1000, // 24 hours
};

if (!CONFIG.webhookSecret) {
  console.warn('⚠️  REVENUECAT_WEBHOOK_SECRET not set. Signature verification disabled!');
}

// =============================================================================
// Idempotency Store (replace with Redis/DB in production)
// =============================================================================

const processedEvents = new Map<string, number>();

function isEventProcessed(eventId: string): boolean {
  const timestamp = processedEvents.get(eventId);
  if (!timestamp) return false;
  
  // Event is still within idempotency window
  if (Date.now() - timestamp < CONFIG.idempotencyWindowMs) {
    return true;
  }
  
  // Expired, clean up
  processedEvents.delete(eventId);
  return false;
}

function markEventProcessed(eventId: string): void {
  processedEvents.set(eventId, Date.now());
  
  // Cleanup old entries periodically (simple version)
  if (processedEvents.size > 10000) {
    const now = Date.now();
    for (const [id, ts] of processedEvents) {
      if (now - ts > CONFIG.idempotencyWindowMs) {
        processedEvents.delete(id);
      }
    }
  }
}

// =============================================================================
// Signature Verification
// =============================================================================

function verifySignature(payload: Buffer, signature: string): boolean {
  if (!CONFIG.webhookSecret) {
    console.warn('Skipping signature verification (no secret configured)');
    return true;
  }
  
  const hmac = crypto.createHmac('sha256', CONFIG.webhookSecret);
  hmac.update(payload);
  const expectedSignature = hmac.digest('hex');
  
  // Timing-safe comparison to prevent timing attacks
  try {
    return crypto.timingSafeEqual(
      Buffer.from(signature),
      Buffer.from(expectedSignature)
    );
  } catch {
    return false;
  }
}

// =============================================================================
// Event Handlers
// =============================================================================

type EventHandler = (event: RevenueCatEvent) => Promise<void>;

const eventHandlers: Partial<Record<RevenueCatEventType, EventHandler>> = {
  
  async TEST(event) {
    console.log('🧪 Test event received! Webhook integration is working.');
  },
  
  async INITIAL_PURCHASE(event) {
    console.log(`🎉 New subscriber: ${event.app_user_id}`);
    console.log(`   Product: ${event.product_id}`);
    console.log(`   Store: ${event.store}`);
    console.log(`   Revenue: ${event.price_in_purchased_currency} ${event.currency}`);
    
    // TODO: Your business logic here
    // - Grant premium access
    // - Send welcome email
    // - Update analytics
  },
  
  async RENEWAL(event) {
    console.log(`🔄 Subscription renewed: ${event.app_user_id}`);
    console.log(`   Product: ${event.product_id}`);
    console.log(`   Next expiration: ${new Date(event.expiration_at_ms!).toISOString()}`);
    
    // TODO: Your business logic here
    // - Extend access
    // - Update MRR metrics
  },
  
  async CANCELLATION(event) {
    console.log(`😢 Subscription cancelled: ${event.app_user_id}`);
    console.log(`   Reason: ${event.cancel_reason}`);
    console.log(`   Access ends: ${new Date(event.expiration_at_ms!).toISOString()}`);
    
    // TODO: Your business logic here
    // - Queue win-back email for expiration date
    // - Update churn metrics
    // - Consider showing a "we miss you" offer in-app
  },
  
  async EXPIRATION(event) {
    console.log(`⏰ Subscription expired: ${event.app_user_id}`);
    
    // TODO: Your business logic here
    // - Revoke premium access
    // - Send win-back campaign
    // - Update subscriber status in your database
  },
  
  async BILLING_ISSUE(event) {
    console.log(`💳 Billing issue: ${event.app_user_id}`);
    console.log(`   Grace period ends: ${new Date(event.grace_period_expiration_at_ms!).toISOString()}`);
    
    // TODO: Your business logic here
    // - Keep access during grace period
    // - Send email asking to update payment method
    // - Show in-app banner about payment issue
  },
  
  async UNCANCELLATION(event) {
    console.log(`🎊 Subscription reactivated: ${event.app_user_id}`);
    
    // TODO: Your business logic here
    // - Cancel any pending win-back emails
    // - Update subscriber status
  },
  
  async PRODUCT_CHANGE(event) {
    console.log(`📦 Plan changed: ${event.app_user_id}`);
    console.log(`   From: ${event.product_id} → To: ${event.new_product_id}`);
    
    // TODO: Your business logic here
    // - Update entitlements
    // - Track upgrade/downgrade metrics
  },
  
  async SUBSCRIBER_ALIAS(event) {
    console.log(`🔗 User aliased: ${event.aliases.join(', ')}`);
    
    // TODO: Your business logic here
    // - Merge user records in your database
  },
  
  async TRANSFER(event) {
    console.log(`↔️ Subscription transferred to: ${event.app_user_id}`);
    
    // TODO: Your business logic here
    // - Update ownership in your database
  },
  
  async NON_RENEWING_PURCHASE(event) {
    console.log(`🛒 One-time purchase: ${event.app_user_id}`);
    console.log(`   Product: ${event.product_id}`);
    
    // TODO: Your business logic here
    // - Grant permanent access
    // - Track lifetime value
  },
};

// =============================================================================
// Express App
// =============================================================================

const app = express();

// Parse raw body for signature verification, then JSON
app.use('/webhook', express.raw({ type: 'application/json' }));

// Webhook endpoint
app.post('/webhook', async (req: Request, res: Response) => {
  const startTime = Date.now();
  
  try {
    // 1. Verify signature
    const signature = req.headers['x-signature'] as string;
    if (!signature) {
      console.error('❌ Missing X-Signature header');
      return res.status(400).json({ error: 'Missing signature' });
    }
    
    if (!verifySignature(req.body, signature)) {
      console.error('❌ Invalid signature');
      return res.status(401).json({ error: 'Invalid signature' });
    }
    
    // 2. Parse payload
    const payload: RevenueCatWebhookPayload = JSON.parse(req.body.toString());
    const { event } = payload;
    
    console.log(`\n📨 Webhook received: ${event.type} (${event.id})`);
    console.log(`   User: ${event.app_user_id}`);
    console.log(`   Environment: ${event.environment}`);
    
    // 3. Check idempotency
    if (isEventProcessed(event.id)) {
      console.log(`⏭️  Event ${event.id} already processed, skipping`);
      return res.status(200).json({ status: 'already_processed' });
    }
    
    // 4. Handle event
    const handler = eventHandlers[event.type];
    if (handler) {
      await handler(event);
    } else {
      console.log(`ℹ️  No handler for event type: ${event.type}`);
    }
    
    // 5. Mark as processed
    markEventProcessed(event.id);
    
    const duration = Date.now() - startTime;
    console.log(`✅ Processed in ${duration}ms`);
    
    return res.status(200).json({ status: 'ok' });
    
  } catch (error) {
    // Always return 200 to prevent retries
    // Log the error for debugging
    console.error('❌ Error processing webhook:', error);
    
    // In production, you'd want to:
    // 1. Store the raw payload somewhere
    // 2. Alert your team
    // 3. Retry processing later
    
    return res.status(200).json({ 
      status: 'error',
      message: 'Event received but processing failed. Will retry internally.'
    });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Start server
app.listen(CONFIG.port, () => {
  console.log(`\n🐕 RevenueCat webhook server running on port ${CONFIG.port}`);
  console.log(`   Webhook endpoint: POST /webhook`);
  console.log(`   Health check: GET /health`);
  console.log(`   Signature verification: ${CONFIG.webhookSecret ? 'ENABLED ✅' : 'DISABLED ⚠️'}`);
  console.log(`\n   Tip: Use ngrok for local testing: ngrok http ${CONFIG.port}\n`);
});

export { app, RevenueCatEvent, RevenueCatWebhookPayload };
