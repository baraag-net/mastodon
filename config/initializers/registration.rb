# frozen_string_literal: true

Rails.application.configure do
  config.x.disable_registration_reason_url_requirement = ENV['DISABLE_REGISTRATION_REASON_URL_REQUIREMENT'] == 'true'
  config.x.registration_art_submission_email = ENV.fetch('REGISTRATION_ART_SUBMISSION_EMAIL', nil)
end
