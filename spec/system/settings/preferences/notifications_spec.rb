# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings preferences notifications page' do
  let(:user) { Fabricate :user }

  before { sign_in user }

  it 'Views and updates user prefs' do
    visit settings_preferences_notifications_path

    expect(page)
      .to have_private_cache_control

    check notifications_follow_field

    expect { click_on submit_button }
      .to change { user.reload.settings['notification_emails.follow'] }.to(true)
    expect(page)
      .to have_title(I18n.t('settings.notifications'))
  end

  def notifications_follow_field
    form_label('notification_emails.follow')
  end
end
