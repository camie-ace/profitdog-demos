# frozen_string_literal: true

# app/jobs/process_subscription_job.rb
#
# Background job for processing subscription lifecycle events
# Called by RevenuecatWebhooksController for async processing

class ProcessSubscriptionJob < ApplicationJob
  queue_as :subscriptions
  
  # Retry on transient failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  
  # Don't retry on permanent failures
  discard_on ActiveRecord::RecordNotFound

  def perform(action:, app_user_id:, event_data:, **options)
    user = find_user(app_user_id)
    return unless user

    case action.to_s
    when 'activate'
      activate_subscription(user, options[:product_id], event_data)
    when 'renew'
      renew_subscription(user, options[:product_id], event_data)
    when 'cancel'
      cancel_subscription(user, options[:expiration_at], event_data)
    when 'reactivate'
      reactivate_subscription(user, event_data)
    when 'expire'
      expire_subscription(user, event_data)
    when 'change_plan'
      change_plan(user, options[:old_product_id], options[:new_product_id], event_data)
    else
      Rails.logger.warn("[ProcessSubscription] Unknown action: #{action}")
    end
  end

  private

  def find_user(app_user_id)
    # Adjust to match your user identification strategy
    User.find_by(revenuecat_app_user_id: app_user_id) ||
      User.find_by(id: app_user_id) ||
      User.find_by(email: app_user_id)
  end

  # ============================================
  # Subscription Actions
  # ============================================

  def activate_subscription(user, product_id, event_data)
    subscription = user.subscription || user.build_subscription

    subscription.update!(
      status: 'active',
      product_id: product_id,
      started_at: parse_time(event_data['purchased_at']),
      current_period_ends_at: parse_time(event_data['expiration_at']),
      revenuecat_original_transaction_id: event_data['original_transaction_id']
    )

    # Track for analytics
    track_event(user, 'subscription.started', {
      product_id: product_id,
      price: event_data['price'],
      currency: event_data['currency']
    })

    # Send welcome email
    SubscriptionMailer.welcome(user).deliver_later

    # Sync entitlements
    sync_entitlements(user, event_data)
  end

  def renew_subscription(user, product_id, event_data)
    return unless user.subscription

    user.subscription.update!(
      status: 'active',
      current_period_ends_at: parse_time(event_data['expiration_at']),
      renewal_count: user.subscription.renewal_count.to_i + 1
    )

    track_event(user, 'subscription.renewed', {
      product_id: product_id,
      renewal_count: user.subscription.renewal_count
    })
  end

  def cancel_subscription(user, expiration_at, event_data)
    return unless user.subscription

    # User still has access until expiration
    user.subscription.update!(
      status: 'cancelled',
      will_renew: false,
      cancellation_reason: event_data['cancel_reason'],
      expires_at: parse_time(expiration_at)
    )

    track_event(user, 'subscription.cancelled', {
      reason: event_data['cancel_reason'],
      days_remaining: days_until(expiration_at)
    })

    # Trigger win-back campaign
    WinBackCampaignJob.set(wait: 1.day).perform_later(user.id)
  end

  def reactivate_subscription(user, event_data)
    return unless user.subscription

    user.subscription.update!(
      status: 'active',
      will_renew: true,
      cancellation_reason: nil,
      expires_at: nil
    )

    track_event(user, 'subscription.reactivated', {})
  end

  def expire_subscription(user, event_data)
    return unless user.subscription

    user.subscription.update!(
      status: 'expired',
      will_renew: false,
      expired_at: Time.current
    )

    # Revoke access
    revoke_entitlements(user)

    track_event(user, 'subscription.expired', {
      total_months: months_subscribed(user)
    })

    # Final win-back attempt
    SubscriptionMailer.we_miss_you(user).deliver_later
  end

  def change_plan(user, old_product_id, new_product_id, event_data)
    return unless user.subscription

    is_upgrade = plan_rank(new_product_id) > plan_rank(old_product_id)

    user.subscription.update!(
      product_id: new_product_id,
      current_period_ends_at: parse_time(event_data['expiration_at'])
    )

    # Update entitlements for new plan
    sync_entitlements(user, event_data)

    track_event(user, is_upgrade ? 'subscription.upgraded' : 'subscription.downgraded', {
      from: old_product_id,
      to: new_product_id
    })

    mailer_method = is_upgrade ? :plan_upgraded : :plan_downgraded
    SubscriptionMailer.send(mailer_method, user).deliver_later
  end

  # ============================================
  # Helpers
  # ============================================

  def parse_time(timestamp)
    return nil unless timestamp
    Time.parse(timestamp.to_s)
  rescue ArgumentError
    nil
  end

  def days_until(timestamp)
    return 0 unless timestamp
    ((parse_time(timestamp) - Time.current) / 1.day).ceil
  rescue
    0
  end

  def months_subscribed(user)
    return 0 unless user.subscription&.started_at
    ((Time.current - user.subscription.started_at) / 1.month).floor
  end

  def plan_rank(product_id)
    # Customize based on your product hierarchy
    case product_id
    when /basic/i then 1
    when /pro/i then 2
    when /premium/i, /enterprise/i then 3
    else 0
    end
  end

  def sync_entitlements(user, event_data)
    entitlements = event_data.dig('subscriber_attributes', 'entitlements') || []
    user.update!(entitlements: entitlements)
  end

  def revoke_entitlements(user)
    user.update!(entitlements: [])
  end

  def track_event(user, event_name, properties)
    # Plug in your analytics provider
    # Analytics.track(user.id, event_name, properties)
    Rails.logger.info("[Analytics] #{event_name} for user #{user.id}: #{properties}")
  end
end
