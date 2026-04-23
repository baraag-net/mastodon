# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::InstanceSerializer do
  let(:serialization) { serialized_record_json(record, described_class) }
  let(:record) { InstancePresenter.new }

  describe 'usage' do
    it 'returns recent usage data' do
      expect(serialization['usage']).to eq({ 'users' => { 'active_month' => 0 } })
    end
  end

  describe 'configuration' do
    it 'returns the VAPID public key' do
      expect(serialization['configuration']['vapid']).to eq({
        'public_key' => Rails.configuration.x.vapid.public_key,
      })
    end

    it 'returns the max pinned statuses limit' do
      expect(serialization.deep_symbolize_keys)
        .to include(
          configuration: include(
            accounts: include(max_pinned_statuses: StatusPinValidator::PIN_LIMIT)
          )
        )
    end
  end

  describe 'registrations' do
    before do
      Setting.registrations_mode = 'approved'
      Setting.require_invite_text = false
    end

    it 'reports the URL requirement when enabled' do
      allow(Rails.configuration.x).to receive(:disable_registration_reason_url_requirement).and_return(false)

      expect(serialization['registrations']).to include('reason_required' => true)
    end

    it 'falls back to the invite text setting when the URL requirement is disabled' do
      allow(Rails.configuration.x).to receive(:disable_registration_reason_url_requirement).and_return(true)

      expect(serialization['registrations']).to include('reason_required' => false)
    end

    it 'still reports a required reason when invite text is required' do
      allow(Rails.configuration.x).to receive(:disable_registration_reason_url_requirement).and_return(true)
      Setting.require_invite_text = true

      expect(serialization['registrations']).to include('reason_required' => true)
    end
  end
end
