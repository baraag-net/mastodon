# frozen_string_literal: true

Rails.application.configure do
  config.x.disable_email_notifications_toggle = ENV['DISABLE_EMAIL_NOTIFICATIONS_TOGGLE'] == 'true'
end
