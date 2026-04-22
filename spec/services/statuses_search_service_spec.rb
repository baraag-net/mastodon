# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusesSearchService do
  describe '.backend_available?' do
    before do
      allow(Chewy).to receive(:enabled?).and_return(false)
    end

    it 'returns false when the generated tsv column is unavailable' do
      allow(Status).to receive(:columns_hash).and_return(Status.columns_hash.except('tsv'))

      ClimateControl.modify DB_SEARCH_ENABLED: 'true' do
        expect(described_class.backend_available?).to be(false)
      end
    end

    it 'returns true when the generated tsv column is available' do
      allow(Status).to receive(:columns_hash).and_call_original

      ClimateControl.modify DB_SEARCH_ENABLED: 'true' do
        expect(described_class.backend_available?).to be(true)
      end
    end
  end
end
