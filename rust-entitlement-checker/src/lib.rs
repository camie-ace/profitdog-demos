//! RevenueCat Entitlement Checker for Rust
//!
//! Server-side entitlement validation using the RevenueCat REST API.
//! Use this to gate features, validate subscriptions, and sync entitlements
//! with your backend services.
//!
//! # Example
//!
//! ```rust,no_run
//! use revenuecat_entitlements::{RevenueCatClient, EntitlementCheck};
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     let client = RevenueCatClient::new("your_api_key")?;
//!     
//!     // Check if user has premium access
//!     if client.has_entitlement("user_123", "premium").await? {
//!         println!("User has premium access!");
//!     }
//!     
//!     Ok(())
//! }
//! ```

use chrono::{DateTime, Utc};
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;
use tracing::{debug, instrument, warn};

// ============================================================================
// Error Types
// ============================================================================

#[derive(Error, Debug)]
pub enum RevenueCatError {
    #[error("HTTP request failed: {0}")]
    RequestFailed(#[from] reqwest::Error),

    #[error("Invalid API key format")]
    InvalidApiKey,

    #[error("Subscriber not found: {app_user_id}")]
    SubscriberNotFound { app_user_id: String },

    #[error("Rate limited - retry after {retry_after_ms}ms")]
    RateLimited { retry_after_ms: u64 },

    #[error("API error ({code}): {message}")]
    ApiError { code: u16, message: String },

    #[error("Entitlement not found: {entitlement_id}")]
    EntitlementNotFound { entitlement_id: String },
}

pub type Result<T> = std::result::Result<T, RevenueCatError>;

// ============================================================================
// API Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct SubscriberResponse {
    pub request_date: DateTime<Utc>,
    pub request_date_ms: i64,
    pub subscriber: Subscriber,
}

#[derive(Debug, Deserialize)]
pub struct Subscriber {
    pub original_app_user_id: String,
    pub original_application_version: Option<String>,
    pub original_purchase_date: Option<DateTime<Utc>>,
    pub management_url: Option<String>,
    pub first_seen: DateTime<Utc>,
    pub last_seen: DateTime<Utc>,
    pub entitlements: HashMap<String, Entitlement>,
    pub subscriptions: HashMap<String, Subscription>,
    pub non_subscriptions: HashMap<String, Vec<NonSubscription>>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Entitlement {
    pub expires_date: Option<DateTime<Utc>>,
    pub grace_period_expires_date: Option<DateTime<Utc>>,
    pub product_identifier: String,
    pub purchase_date: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct Subscription {
    pub expires_date: Option<DateTime<Utc>>,
    pub grace_period_expires_date: Option<DateTime<Utc>>,
    pub purchase_date: DateTime<Utc>,
    pub original_purchase_date: DateTime<Utc>,
    pub product_plan_identifier: Option<String>,
    pub store: String,
    pub is_sandbox: bool,
    pub unsubscribe_detected_at: Option<DateTime<Utc>>,
    pub billing_issues_detected_at: Option<DateTime<Utc>>,
    pub ownership_type: Option<String>,
    pub period_type: Option<String>,
    pub refunded_at: Option<DateTime<Utc>>,
    pub auto_resume_date: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct NonSubscription {
    pub id: String,
    pub purchase_date: DateTime<Utc>,
    pub store: String,
    pub is_sandbox: bool,
}

// ============================================================================
// Entitlement Check Results
// ============================================================================

/// Result of checking a user's entitlement status
#[derive(Debug, Clone)]
pub struct EntitlementStatus {
    /// Whether the entitlement is currently active
    pub is_active: bool,
    /// The entitlement details, if found
    pub entitlement: Option<Entitlement>,
    /// Whether the user is in a grace period
    pub in_grace_period: bool,
    /// Time until expiration (None if lifetime or not active)
    pub expires_in: Option<chrono::Duration>,
}

impl EntitlementStatus {
    /// Check if entitlement will expire within the given duration
    pub fn expires_within(&self, duration: chrono::Duration) -> bool {
        self.expires_in
            .map(|exp| exp < duration)
            .unwrap_or(false)
    }

    /// Check if this is a lifetime/non-expiring entitlement
    pub fn is_lifetime(&self) -> bool {
        self.is_active && self.expires_in.is_none()
    }
}

/// Trait for checking entitlements - implement this for custom caching strategies
pub trait EntitlementCheck {
    /// Check if user has a specific active entitlement
    fn has_entitlement(
        &self,
        app_user_id: &str,
        entitlement_id: &str,
    ) -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Get detailed entitlement status
    fn get_entitlement_status(
        &self,
        app_user_id: &str,
        entitlement_id: &str,
    ) -> impl std::future::Future<Output = Result<EntitlementStatus>> + Send;

    /// Get all active entitlements for a user
    fn get_active_entitlements(
        &self,
        app_user_id: &str,
    ) -> impl std::future::Future<Output = Result<Vec<String>>> + Send;
}

// ============================================================================
// RevenueCat Client
// ============================================================================

/// RevenueCat API client for server-side entitlement checking
#[derive(Clone)]
pub struct RevenueCatClient {
    http: reqwest::Client,
    base_url: String,
}

impl RevenueCatClient {
    const DEFAULT_BASE_URL: &'static str = "https://api.revenuecat.com/v1";

    /// Create a new RevenueCat client with the given API key
    ///
    /// Use your **secret** API key from the RevenueCat dashboard
    /// (not the public SDK key).
    pub fn new(api_key: &str) -> Result<Self> {
        Self::with_base_url(api_key, Self::DEFAULT_BASE_URL)
    }

    /// Create a client with a custom base URL (useful for testing)
    pub fn with_base_url(api_key: &str, base_url: &str) -> Result<Self> {
        if api_key.is_empty() {
            return Err(RevenueCatError::InvalidApiKey);
        }

        let mut headers = HeaderMap::new();
        headers.insert(
            AUTHORIZATION,
            HeaderValue::from_str(&format!("Bearer {}", api_key))
                .map_err(|_| RevenueCatError::InvalidApiKey)?,
        );
        headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));

        let http = reqwest::Client::builder()
            .default_headers(headers)
            .build()?;

        Ok(Self {
            http,
            base_url: base_url.to_string(),
        })
    }

    /// Fetch full subscriber information
    #[instrument(skip(self), fields(app_user_id = %app_user_id))]
    pub async fn get_subscriber(&self, app_user_id: &str) -> Result<Subscriber> {
        let url = format!("{}/subscribers/{}", self.base_url, app_user_id);

        debug!("Fetching subscriber data");

        let response = self.http.get(&url).send().await?;

        match response.status().as_u16() {
            200 => {
                let subscriber_response: SubscriberResponse = response.json().await?;
                Ok(subscriber_response.subscriber)
            }
            404 => Err(RevenueCatError::SubscriberNotFound {
                app_user_id: app_user_id.to_string(),
            }),
            429 => {
                let retry_after = response
                    .headers()
                    .get("Retry-After")
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| v.parse::<u64>().ok())
                    .unwrap_or(1000);
                Err(RevenueCatError::RateLimited {
                    retry_after_ms: retry_after,
                })
            }
            code => {
                let message = response.text().await.unwrap_or_default();
                Err(RevenueCatError::ApiError { code, message })
            }
        }
    }
}

impl EntitlementCheck for RevenueCatClient {
    /// Quick check if user has an active entitlement
    async fn has_entitlement(&self, app_user_id: &str, entitlement_id: &str) -> Result<bool> {
        let status = self.get_entitlement_status(app_user_id, entitlement_id).await?;
        Ok(status.is_active)
    }

    /// Get detailed entitlement status with expiration info
    #[instrument(skip(self), fields(app_user_id = %app_user_id, entitlement_id = %entitlement_id))]
    async fn get_entitlement_status(
        &self,
        app_user_id: &str,
        entitlement_id: &str,
    ) -> Result<EntitlementStatus> {
        let subscriber = self.get_subscriber(app_user_id).await?;

        let entitlement = subscriber.entitlements.get(entitlement_id).cloned();

        let Some(ent) = &entitlement else {
            debug!("Entitlement not found");
            return Ok(EntitlementStatus {
                is_active: false,
                entitlement: None,
                in_grace_period: false,
                expires_in: None,
            });
        };

        let now = Utc::now();

        // Check if active (not expired or has grace period)
        let is_active = ent
            .expires_date
            .map(|exp| exp > now)
            .unwrap_or(true) // No expiration = lifetime
            || ent
                .grace_period_expires_date
                .map(|grace| grace > now)
                .unwrap_or(false);

        let in_grace_period = ent
            .expires_date
            .map(|exp| exp <= now)
            .unwrap_or(false)
            && ent
                .grace_period_expires_date
                .map(|grace| grace > now)
                .unwrap_or(false);

        let expires_in = ent.expires_date.map(|exp| exp - now);

        if in_grace_period {
            warn!("User in grace period - billing issue likely");
        }

        Ok(EntitlementStatus {
            is_active,
            entitlement,
            in_grace_period,
            expires_in,
        })
    }

    /// Get all currently active entitlement IDs for a user
    async fn get_active_entitlements(&self, app_user_id: &str) -> Result<Vec<String>> {
        let subscriber = self.get_subscriber(app_user_id).await?;
        let now = Utc::now();

        let active: Vec<String> = subscriber
            .entitlements
            .into_iter()
            .filter(|(_, ent)| {
                ent.expires_date.map(|exp| exp > now).unwrap_or(true)
                    || ent
                        .grace_period_expires_date
                        .map(|grace| grace > now)
                        .unwrap_or(false)
            })
            .map(|(id, _)| id)
            .collect();

        Ok(active)
    }
}

// ============================================================================
// Middleware helpers for common frameworks
// ============================================================================

/// Helper for Axum/Tower middleware integration
#[cfg(feature = "axum")]
pub mod axum_middleware {
    // Placeholder for Axum middleware - could add in future version
}

/// Helper for Actix-web middleware integration  
#[cfg(feature = "actix")]
pub mod actix_middleware {
    // Placeholder for Actix middleware - could add in future version
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_invalid_api_key() {
        let result = RevenueCatClient::new("");
        assert!(matches!(result, Err(RevenueCatError::InvalidApiKey)));
    }

    #[test]
    fn test_entitlement_status_expires_within() {
        let status = EntitlementStatus {
            is_active: true,
            entitlement: None,
            in_grace_period: false,
            expires_in: Some(chrono::Duration::hours(12)),
        };

        assert!(status.expires_within(chrono::Duration::days(1)));
        assert!(!status.expires_within(chrono::Duration::hours(6)));
    }

    #[test]
    fn test_entitlement_status_lifetime() {
        let lifetime = EntitlementStatus {
            is_active: true,
            entitlement: None,
            in_grace_period: false,
            expires_in: None,
        };

        assert!(lifetime.is_lifetime());

        let subscription = EntitlementStatus {
            is_active: true,
            entitlement: None,
            in_grace_period: false,
            expires_in: Some(chrono::Duration::days(30)),
        };

        assert!(!subscription.is_lifetime());
    }
}
