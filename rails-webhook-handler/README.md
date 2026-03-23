# Rails RevenueCat Webhook Handler

A production-ready Rails controller for handling RevenueCat webhooks with signature verification, event processing, and async job queuing.

## Features

- ✅ Webhook signature verification (HMAC-SHA256)
- ✅ All RevenueCat event types handled
- ✅ Idempotent processing with event tracking
- ✅ Background job queuing for heavy operations
- ✅ Structured logging for debugging

## Setup

### 1. Add Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  post '/webhooks/revenuecat', to: 'revenuecat_webhooks#create'
end
```

### 2. Configure Webhook Secret

```ruby
# config/credentials.yml.enc (or ENV)
revenuecat:
  webhook_secret: your_webhook_secret_from_dashboard
```

### 3. Add Migration for Event Tracking

```bash
rails generate migration CreateRevenueCatEvents
```

```ruby
# db/migrate/xxx_create_revenue_cat_events.rb
class CreateRevenueCatEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :revenue_cat_events do |t|
      t.string :event_id, null: false, index: { unique: true }
      t.string :event_type, null: false
      t.string :app_user_id
      t.jsonb :payload, default: {}
      t.string :status, default: 'pending'
      t.datetime :processed_at
      t.timestamps
    end
    
    add_index :revenue_cat_events, [:app_user_id, :event_type]
    add_index :revenue_cat_events, :created_at
  end
end
```

### 4. Create the Event Model

```ruby
# app/models/revenue_cat_event.rb
class RevenueCatEvent < ApplicationRecord
  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true

  scope :pending, -> { where(status: 'pending') }
  scope :processed, -> { where(status: 'processed') }
  scope :failed, -> { where(status: 'failed') }

  def mark_processed!
    update!(status: 'processed', processed_at: Time.current)
  end

  def mark_failed!(error_message = nil)
    update!(status: 'failed', payload: payload.merge('error' => error_message))
  end
end
```

## Usage

The controller handles incoming webhooks and dispatches to appropriate handlers:

```ruby
# Example: Extending the handler in your app
class MyRevenueCatProcessor
  def self.on_initial_purchase(event_data)
    user = User.find_by(revenuecat_id: event_data['app_user_id'])
    return unless user

    user.update!(
      subscription_status: 'active',
      subscription_started_at: Time.current
    )
    
    UserMailer.welcome_subscriber(user).deliver_later
    Analytics.track(user, 'subscription_started', plan: event_data['product_id'])
  end
end
```

## Event Types

| Event | Description |
|-------|-------------|
| `INITIAL_PURCHASE` | First-time subscription purchase |
| `RENEWAL` | Successful renewal |
| `CANCELLATION` | User cancelled (access until period end) |
| `UNCANCELLATION` | User re-enabled auto-renew |
| `EXPIRATION` | Subscription fully expired |
| `BILLING_ISSUE` | Payment failed |
| `PRODUCT_CHANGE` | Plan upgrade/downgrade |
| `SUBSCRIBER_ALIAS` | User IDs merged |
| `TRANSFER` | Subscription transferred between users |

## Testing Locally

Use the RevenueCat dashboard to send test webhooks, or use curl:

```bash
curl -X POST http://localhost:3000/webhooks/revenuecat \
  -H "Content-Type: application/json" \
  -d '{
    "api_version": "1.0",
    "event": {
      "id": "test-123",
      "type": "INITIAL_PURCHASE",
      "app_user_id": "user_abc",
      "product_id": "pro_monthly"
    }
  }'
```

## Production Considerations

1. **Use background jobs** for any slow operations (emails, external APIs)
2. **Implement retry logic** for transient failures
3. **Monitor webhook latency** — RevenueCat expects responses within 5 seconds
4. **Set up alerting** for failed webhook processing

## License

MIT — Use freely in your projects.

---

Built with 🐕 by [ProfitDog](https://github.com/camie-ace/profitdog-demos)
