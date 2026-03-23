# frozen_string_literal: true

# app/controllers/revenuecat_webhooks_controller.rb
#
# Production-ready RevenueCat webhook handler for Rails
# Handles signature verification, idempotent processing, and event routing
#
# Setup:
#   1. Add route: post '/webhooks/revenuecat', to: 'revenuecat_webhooks#create'
#   2. Set REVENUECAT_WEBHOOK_SECRET in your environment
#   3. Create RevenueCatEvent model (see README.md)

class RevenuecatWebhooksController < ApplicationController
  # Skip CSRF for webhook endpoints
  skip_before_action :verify_authenticity_token
  
  # Optional: Add IP allowlist for extra security
  # before_action :verify_ip_allowlist

  def create
    # Verify webhook signature (skip in development if needed)
    unless valid_signature?
      Rails.logger.warn("[RevenueCat] Invalid webhook signature from #{request.remote_ip}")
      return head :unauthorized
    end

    event_data = parsed_event
    return head :bad_request unless event_data

    # Idempotency check — don't process the same event twice
    if already_processed?(event_data['id'])
      Rails.logger.info("[RevenueCat] Skipping duplicate event: #{event_data['id']}")
      return head :ok
    end

    # Store event for tracking and recovery
    event_record = store_event(event_data)

    # Route to appropriate handler
    begin
      process_event(event_data)
      event_record.mark_processed!
      Rails.logger.info("[RevenueCat] Processed event: #{event_data['type']} for #{event_data['app_user_id']}")
    rescue StandardError => e
      event_record.mark_failed!(e.message)
      Rails.logger.error("[RevenueCat] Failed to process event #{event_data['id']}: #{e.message}")
      # Still return 200 to prevent retries for application errors
      # RevenueCat will retry on 5xx, which we want for infra issues only
    end

    head :ok
  end

  private

  # ============================================
  # Signature Verification
  # ============================================

  def valid_signature?
    return true if Rails.env.development? && skip_signature_in_dev?

    secret = webhook_secret
    return false unless secret.present?

    # RevenueCat sends signature in X-RevenueCat-Signature header
    signature = request.headers['X-RevenueCat-Signature']
    return false unless signature.present?

    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)
    ActiveSupport::SecurityUtils.secure_compare(signature, expected)
  end

  def webhook_secret
    ENV['REVENUECAT_WEBHOOK_SECRET'] || 
      Rails.application.credentials.dig(:revenuecat, :webhook_secret)
  end

  def skip_signature_in_dev?
    ENV['SKIP_WEBHOOK_SIGNATURE'].present?
  end

  # ============================================
  # Event Parsing
  # ============================================

  def parsed_event
    body = JSON.parse(request.raw_post)
    event = body['event'] || body
    
    # Ensure required fields exist
    return nil unless event['id'].present? && event['type'].present?
    
    event
  rescue JSON::ParserError => e
    Rails.logger.error("[RevenueCat] Invalid JSON payload: #{e.message}")
    nil
  end

  # ============================================
  # Idempotency & Storage
  # ============================================

  def already_processed?(event_id)
    RevenueCatEvent.exists?(event_id: event_id)
  end

  def store_event(event_data)
    RevenueCatEvent.create!(
      event_id: event_data['id'],
      event_type: event_data['type'],
      app_user_id: event_data['app_user_id'],
      payload: event_data
    )
  end

  # ============================================
  # Event Routing
  # ============================================

  def process_event(event_data)
    case event_data['type']
    when 'INITIAL_PURCHASE'
      handle_initial_purchase(event_data)
    when 'RENEWAL'
      handle_renewal(event_data)
    when 'CANCELLATION'
      handle_cancellation(event_data)
    when 'UNCANCELLATION'
      handle_uncancellation(event_data)
    when 'EXPIRATION'
      handle_expiration(event_data)
    when 'BILLING_ISSUE'
      handle_billing_issue(event_data)
    when 'PRODUCT_CHANGE'
      handle_product_change(event_data)
    when 'SUBSCRIBER_ALIAS'
      handle_subscriber_alias(event_data)
    when 'TRANSFER'
      handle_transfer(event_data)
    when 'NON_RENEWING_PURCHASE'
      handle_non_renewing_purchase(event_data)
    else
      Rails.logger.info("[RevenueCat] Unhandled event type: #{event_data['type']}")
    end
  end

  # ============================================
  # Event Handlers
  # ============================================

  def handle_initial_purchase(event_data)
    # Queue background job for heavy processing
    ProcessSubscriptionJob.perform_later(
      action: 'activate',
      app_user_id: event_data['app_user_id'],
      product_id: event_data['product_id'],
      event_data: event_data
    )
  end

  def handle_renewal(event_data)
    ProcessSubscriptionJob.perform_later(
      action: 'renew',
      app_user_id: event_data['app_user_id'],
      product_id: event_data['product_id'],
      event_data: event_data
    )
  end

  def handle_cancellation(event_data)
    # User still has access until expiration_at
    ProcessSubscriptionJob.perform_later(
      action: 'cancel',
      app_user_id: event_data['app_user_id'],
      expiration_at: event_data['expiration_at'],
      event_data: event_data
    )
  end

  def handle_uncancellation(event_data)
    # User re-enabled auto-renew
    ProcessSubscriptionJob.perform_later(
      action: 'reactivate',
      app_user_id: event_data['app_user_id'],
      event_data: event_data
    )
  end

  def handle_expiration(event_data)
    # Access should be revoked now
    ProcessSubscriptionJob.perform_later(
      action: 'expire',
      app_user_id: event_data['app_user_id'],
      event_data: event_data
    )
  end

  def handle_billing_issue(event_data)
    # Payment failed — trigger dunning flow
    BillingIssueJob.perform_later(
      app_user_id: event_data['app_user_id'],
      grace_period_expires_at: event_data['grace_period_expires_at'],
      event_data: event_data
    )
  end

  def handle_product_change(event_data)
    # Upgrade or downgrade
    ProcessSubscriptionJob.perform_later(
      action: 'change_plan',
      app_user_id: event_data['app_user_id'],
      new_product_id: event_data['new_product_id'],
      old_product_id: event_data['product_id'],
      event_data: event_data
    )
  end

  def handle_subscriber_alias(event_data)
    # Merge user accounts
    MergeSubscriberJob.perform_later(
      original_app_user_id: event_data['original_app_user_id'],
      alias_app_user_id: event_data['alias'],
      event_data: event_data
    )
  end

  def handle_transfer(event_data)
    # Subscription moved to different user
    TransferSubscriptionJob.perform_later(
      from_app_user_id: event_data['transferred_from'],
      to_app_user_id: event_data['transferred_to'],
      event_data: event_data
    )
  end

  def handle_non_renewing_purchase(event_data)
    # One-time purchase (consumable or non-consumable)
    ProcessPurchaseJob.perform_later(
      app_user_id: event_data['app_user_id'],
      product_id: event_data['product_id'],
      event_data: event_data
    )
  end
end
