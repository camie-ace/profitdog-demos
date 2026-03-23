# frozen_string_literal: true

# app/jobs/billing_issue_job.rb
#
# Handles failed payment (billing issue) events from RevenueCat
# Implements a dunning sequence to recover failed subscriptions

class BillingIssueJob < ApplicationJob
  queue_as :billing
  
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform(app_user_id:, grace_period_expires_at:, event_data:)
    user = find_user(app_user_id)
    return unless user

    subscription = user.subscription
    return unless subscription

    # Update subscription status
    subscription.update!(
      status: 'billing_issue',
      grace_period_ends_at: parse_time(grace_period_expires_at),
      billing_issue_detected_at: Time.current
    )

    # Determine dunning stage
    stage = determine_dunning_stage(subscription)

    # Execute dunning action
    case stage
    when :initial
      send_initial_payment_failed_notice(user, subscription)
    when :reminder
      send_payment_reminder(user, subscription)
    when :urgent
      send_urgent_notice(user, subscription)
    when :final
      send_final_notice(user, subscription)
    end

    # Schedule follow-up if still in grace period
    schedule_followup(user, subscription, stage) if within_grace_period?(subscription)

    # Track for analytics
    track_billing_issue(user, stage, event_data)
  end

  private

  def find_user(app_user_id)
    User.find_by(revenuecat_app_user_id: app_user_id) ||
      User.find_by(id: app_user_id)
  end

  def parse_time(timestamp)
    return nil unless timestamp
    Time.parse(timestamp.to_s)
  rescue ArgumentError
    nil
  end

  # ============================================
  # Dunning Logic
  # ============================================

  def determine_dunning_stage(subscription)
    days_since_issue = days_since_billing_issue(subscription)

    case days_since_issue
    when 0..1 then :initial
    when 2..4 then :reminder
    when 5..10 then :urgent
    else :final
    end
  end

  def days_since_billing_issue(subscription)
    return 0 unless subscription.billing_issue_detected_at
    ((Time.current - subscription.billing_issue_detected_at) / 1.day).floor
  end

  def within_grace_period?(subscription)
    return true unless subscription.grace_period_ends_at
    Time.current < subscription.grace_period_ends_at
  end

  # ============================================
  # Dunning Communications
  # ============================================

  def send_initial_payment_failed_notice(user, subscription)
    BillingMailer.payment_failed(
      user,
      update_payment_url: generate_management_url(user),
      grace_period_ends: subscription.grace_period_ends_at
    ).deliver_later
  end

  def send_payment_reminder(user, subscription)
    days_left = days_until_grace_expires(subscription)
    
    BillingMailer.payment_reminder(
      user,
      days_remaining: days_left,
      update_payment_url: generate_management_url(user)
    ).deliver_later
  end

  def send_urgent_notice(user, subscription)
    days_left = days_until_grace_expires(subscription)
    
    BillingMailer.urgent_payment_needed(
      user,
      days_remaining: days_left,
      update_payment_url: generate_management_url(user)
    ).deliver_later

    # Optional: Send push notification
    send_push_notification(user, "Payment issue - update within #{days_left} days to keep your subscription")
  end

  def send_final_notice(user, subscription)
    BillingMailer.final_payment_notice(
      user,
      update_payment_url: generate_management_url(user)
    ).deliver_later

    send_push_notification(user, "Last chance: Update payment now to avoid losing access")
  end

  # ============================================
  # Helpers
  # ============================================

  def days_until_grace_expires(subscription)
    return 0 unless subscription.grace_period_ends_at
    [(subscription.grace_period_ends_at.to_date - Date.current).to_i, 0].max
  end

  def generate_management_url(user)
    # RevenueCat provides customer-specific management URLs
    # Or generate your own deep link
    "https://yourapp.com/subscription/manage?token=#{user.subscription_management_token}"
  end

  def schedule_followup(user, subscription, current_stage)
    next_check_days = case current_stage
                      when :initial then 2
                      when :reminder then 3
                      when :urgent then 2
                      else return # No followup after final
                      end

    BillingFollowupJob.set(wait: next_check_days.days).perform_later(
      user_id: user.id,
      subscription_id: subscription.id
    )
  end

  def send_push_notification(user, message)
    # Integrate with your push notification service
    # PushService.send(user, message)
    Rails.logger.info("[Push] #{message} -> user #{user.id}")
  end

  def track_billing_issue(user, stage, event_data)
    Rails.logger.info(
      "[BillingIssue] User #{user.id} at stage #{stage}, " \
      "store: #{event_data['store']}, " \
      "product: #{event_data['product_id']}"
    )
  end
end
