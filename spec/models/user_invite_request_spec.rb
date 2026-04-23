# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserInviteRequest do
  subject(:invite_request) { described_class.new(user: Fabricate.build(:user), text: text, require_url: require_url) }

  let(:require_url) { false }

  describe 'validations' do
    context 'when a URL is required' do
      let(:require_url) { true }

      context 'when the text is blank' do
        let(:text) { '' }

        it 'adds a missing URL error' do
          expect(invite_request).to_not be_valid
          expect(invite_request.errors.of_kind?(:text, :missing_url)).to be(true)
        end
      end

      context 'when the text does not include a full URL' do
        let(:text) { 'I post photos and follow art communities.' }

        it 'adds a missing URL error' do
          expect(invite_request).to_not be_valid
          expect(invite_request.errors.of_kind?(:text, :missing_url)).to be(true)
        end
      end

      context 'when the text includes a full URL' do
        let(:text) { 'Portfolio: https://example.com/@test' }

        it 'is valid' do
          expect(invite_request).to be_valid
        end
      end
    end
  end
end
