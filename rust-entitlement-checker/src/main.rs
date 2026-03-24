//! Example: Server-side entitlement checker CLI
//!
//! Demonstrates checking RevenueCat entitlements from a Rust backend.
//!
//! Usage:
//!   REVENUECAT_API_KEY=sk_xxx cargo run -- check user_123 premium
//!   REVENUECAT_API_KEY=sk_xxx cargo run -- list user_123

use revenuecat_entitlements::{EntitlementCheck, RevenueCatClient};
use std::env;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing for debug output
    tracing_subscriber::fmt::init();

    let api_key = env::var("REVENUECAT_API_KEY")
        .expect("REVENUECAT_API_KEY environment variable required");

    let client = RevenueCatClient::new(&api_key)?;

    let args: Vec<String> = env::args().collect();

    match args.get(1).map(|s| s.as_str()) {
        Some("check") => {
            let user_id = args.get(2).expect("Usage: check <user_id> <entitlement_id>");
            let entitlement_id = args.get(3).expect("Usage: check <user_id> <entitlement_id>");

            println!("Checking entitlement '{}' for user '{}'...\n", entitlement_id, user_id);

            let status = client.get_entitlement_status(user_id, entitlement_id).await?;

            println!("Active: {}", status.is_active);
            println!("In Grace Period: {}", status.in_grace_period);
            println!("Is Lifetime: {}", status.is_lifetime());

            if let Some(expires_in) = status.expires_in {
                let hours = expires_in.num_hours();
                if hours > 24 {
                    println!("Expires in: {} days", hours / 24);
                } else {
                    println!("Expires in: {} hours", hours);
                }

                // Warn if expiring soon
                if status.expires_within(chrono::Duration::days(3)) {
                    println!("\n⚠️  Subscription expiring soon - consider renewal prompt");
                }
            }

            if status.in_grace_period {
                println!("\n⚠️  User in grace period - billing issue detected");
            }
        }

        Some("list") => {
            let user_id = args.get(2).expect("Usage: list <user_id>");

            println!("Fetching active entitlements for '{}'...\n", user_id);

            let entitlements = client.get_active_entitlements(user_id).await?;

            if entitlements.is_empty() {
                println!("No active entitlements found.");
            } else {
                println!("Active entitlements:");
                for ent in entitlements {
                    println!("  ✓ {}", ent);
                }
            }
        }

        Some("subscriber") => {
            let user_id = args.get(2).expect("Usage: subscriber <user_id>");

            println!("Fetching full subscriber data for '{}'...\n", user_id);

            let subscriber = client.get_subscriber(user_id).await?;

            println!("Original App User ID: {}", subscriber.original_app_user_id);
            println!("First Seen: {}", subscriber.first_seen);
            println!("Last Seen: {}", subscriber.last_seen);

            if let Some(url) = subscriber.management_url {
                println!("Management URL: {}", url);
            }

            println!("\nEntitlements:");
            for (id, ent) in &subscriber.entitlements {
                println!("  {} (product: {})", id, ent.product_identifier);
                if let Some(exp) = ent.expires_date {
                    println!("    Expires: {}", exp);
                } else {
                    println!("    Expires: Never (lifetime)");
                }
            }

            println!("\nSubscriptions:");
            for (id, sub) in &subscriber.subscriptions {
                println!("  {} (store: {}, sandbox: {})", id, sub.store, sub.is_sandbox);
                if let Some(exp) = sub.expires_date {
                    println!("    Expires: {}", exp);
                }
                if sub.billing_issues_detected_at.is_some() {
                    println!("    ⚠️  Billing issue detected");
                }
            }
        }

        _ => {
            eprintln!("Usage:");
            eprintln!("  check <user_id> <entitlement_id>  - Check specific entitlement");
            eprintln!("  list <user_id>                    - List all active entitlements");
            eprintln!("  subscriber <user_id>              - Get full subscriber info");
            eprintln!();
            eprintln!("Environment:");
            eprintln!("  REVENUECAT_API_KEY  - Your RevenueCat secret API key");
            std::process::exit(1);
        }
    }

    Ok(())
}
