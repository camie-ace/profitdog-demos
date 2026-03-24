# Rust Entitlement Checker

Server-side entitlement validation for RevenueCat in Rust. Check subscriptions, gate features, and sync entitlements with your backend services.

## Features

- 🦀 **Idiomatic Rust** - async/await, strong typing, proper error handling
- 🔒 **Server-side validation** - Use your secret API key for trusted checks
- ⏱️ **Grace period detection** - Know when users have billing issues
- 📊 **Detailed status** - Expiration times, lifetime detection, full subscriber data
- 🧪 **Testable** - Designed for easy mocking with the `EntitlementCheck` trait

## Quick Start

Add to your `Cargo.toml`:

```toml
[dependencies]
revenuecat-entitlements = { path = "." }  # Or publish to crates.io
tokio = { version = "1", features = ["full"] }
```

### Basic Usage

```rust
use revenuecat_entitlements::{RevenueCatClient, EntitlementCheck};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = RevenueCatClient::new("sk_your_secret_key")?;
    
    // Simple boolean check
    if client.has_entitlement("user_123", "premium").await? {
        // Grant access to premium features
    }
    
    Ok(())
}
```

### Detailed Status

```rust
let status = client.get_entitlement_status("user_123", "premium").await?;

println!("Active: {}", status.is_active);
println!("In Grace Period: {}", status.in_grace_period);
println!("Is Lifetime: {}", status.is_lifetime());

// Check if expiring soon (for renewal prompts)
if status.expires_within(chrono::Duration::days(3)) {
    show_renewal_prompt();
}

// Handle billing issues
if status.in_grace_period {
    show_update_payment_banner();
}
```

### List All Active Entitlements

```rust
let entitlements = client.get_active_entitlements("user_123").await?;

for ent_id in entitlements {
    println!("User has: {}", ent_id);
}
```

### Full Subscriber Data

```rust
let subscriber = client.get_subscriber("user_123").await?;

println!("First seen: {}", subscriber.first_seen);
println!("Subscriptions: {:?}", subscriber.subscriptions.keys());

// Check for management URL (for "Manage Subscription" button)
if let Some(url) = subscriber.management_url {
    show_manage_button(url);
}
```

## CLI Example

```bash
# Set your secret API key
export REVENUECAT_API_KEY="sk_xxx"

# Check a specific entitlement
cargo run -- check user_123 premium

# List all active entitlements
cargo run -- list user_123

# Get full subscriber info
cargo run -- subscriber user_123
```

## Error Handling

```rust
use revenuecat_entitlements::RevenueCatError;

match client.has_entitlement("user_123", "premium").await {
    Ok(true) => grant_access(),
    Ok(false) => show_paywall(),
    Err(RevenueCatError::SubscriberNotFound { .. }) => {
        // New user, no purchases yet
        show_paywall()
    }
    Err(RevenueCatError::RateLimited { retry_after_ms }) => {
        // Implement backoff, maybe cache more aggressively
        tokio::time::sleep(Duration::from_millis(retry_after_ms)).await;
    }
    Err(e) => {
        // Log and decide on fallback behavior
        tracing::error!("RevenueCat error: {}", e);
        // Fail open or closed based on your policy
    }
}
```

## Integration Patterns

### Axum Middleware

```rust
use axum::{middleware::from_fn_with_state, Router};

async fn require_premium(
    State(rc): State<RevenueCatClient>,
    user_id: UserId,  // Extract from your auth
    request: Request,
    next: Next,
) -> Response {
    match rc.has_entitlement(&user_id.0, "premium").await {
        Ok(true) => next.run(request).await,
        Ok(false) => StatusCode::PAYMENT_REQUIRED.into_response(),
        Err(_) => StatusCode::SERVICE_UNAVAILABLE.into_response(),
    }
}

let app = Router::new()
    .route("/premium-feature", get(premium_handler))
    .layer(from_fn_with_state(client.clone(), require_premium));
```

### Caching Layer

```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;

struct CachedChecker {
    client: RevenueCatClient,
    cache: Arc<RwLock<HashMap<String, (EntitlementStatus, Instant)>>>,
    ttl: Duration,
}

impl EntitlementCheck for CachedChecker {
    async fn has_entitlement(&self, user: &str, ent: &str) -> Result<bool> {
        let key = format!("{}:{}", user, ent);
        
        // Check cache first
        if let Some((status, cached_at)) = self.cache.read().await.get(&key) {
            if cached_at.elapsed() < self.ttl {
                return Ok(status.is_active);
            }
        }
        
        // Cache miss - fetch and store
        let status = self.client.get_entitlement_status(user, ent).await?;
        let is_active = status.is_active;
        
        self.cache.write().await.insert(key, (status, Instant::now()));
        
        Ok(is_active)
    }
    
    // ... implement other methods
}
```

## Why Server-Side?

While RevenueCat's mobile SDKs handle most use cases, server-side validation is essential for:

1. **API access control** - Gate backend endpoints that shouldn't trust client claims
2. **Webhook processing** - Validate subscription state when processing events
3. **Data sync** - Keep your database in sync with RevenueCat
4. **Cross-platform** - Single source of truth for web, mobile, and desktop
5. **Admin tools** - Customer support dashboards need trusted access

## API Key Security

⚠️ **Use your secret API key** (starts with `sk_`), not the public SDK key.

- Never expose the secret key to clients
- Use environment variables or a secrets manager
- Rotate keys if compromised

## License

MIT
