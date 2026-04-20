# frozen_string_literal: true

class Settings::Preferences::NotificationsController < Settings::Preferences::BaseController
  USER_EMAIL_TOGGLE_KEYS = %w(
    notification_emails.follow
    notification_emails.follow_request
    notification_emails.reblog
    notification_emails.favourite
    notification_emails.mention
    notification_emails.quote
    always_send_emails
  ).freeze

  private

  def after_update_redirect_path
    settings_preferences_notifications_path
  end

  def user_params
    permitted = super
    permitted[:settings_attributes] = permitted[:settings_attributes].except(*USER_EMAIL_TOGGLE_KEYS) if Rails.configuration.x.disable_email_notifications_toggle && permitted[:settings_attributes].present?
    permitted
  end
end
