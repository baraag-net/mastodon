# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchQueryTransformer do
  subject { described_class.new.apply(parser, current_account: account) }

  let(:account) { Fabricate(:account) }
  let(:parser) { SearchQueryParser.new.parse(query) }

  shared_examples 'date operator' do |operator|
    let(:statement_operations) { [] }

    [
      ['2022-01-01', '2022-01-01'],
      ['"2022-01-01"', '2022-01-01'],
      ['12345678', '12345678'],
      ['"12345678"', '12345678'],
      ['"2024-10-31T23:47:20Z"', '2024-10-31T23:47:20Z'],
    ].each do |value, parsed|
      context "with #{operator}:#{value}" do
        let(:query) { "#{operator}:#{value}" }

        it 'transforms clauses' do
          ops = statement_operations.index_with { |_op| parsed }

          expect(subject.send(:must_clauses)).to be_empty
          expect(subject.send(:must_not_clauses)).to be_empty
          expect(subject.send(:filter_clauses).map(&:term)).to contain_exactly(**ops, time_zone: 'UTC')
        end
      end
    end

    context "with #{operator}:\"abc\"" do
      let(:query) { "#{operator}:\"abc\"" }

      it 'raises an exception' do
        expect { subject }.to raise_error(Date::Error)
      end
    end
  end

  context 'with "hello world"' do
    let(:query) { 'hello world' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(hello world)
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with "hello -world"' do
    let(:query) { 'hello -world' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(hello)
      expect(subject.send(:must_not_clauses).map(&:term)).to match_array %w(world)
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with "hello is:reply"' do
    let(:query) { 'hello is:reply' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(hello)
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:term)).to match_array %w(reply)
    end
  end

  context 'with "foo: bar"' do
    let(:query) { 'foo: bar' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(foo bar)
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with "foo:bar"' do
    let(:query) { 'foo:bar' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to contain_exactly('foo bar')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with \'"hello world"\'' do
    let(:query) { '"hello world"' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:phrase)).to contain_exactly('hello world')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with \'is:"foo bar"\'' do
    let(:query) { 'is:"foo bar"' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses)).to be_empty
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:term)).to contain_exactly('foo bar')
    end
  end

  context 'with date operators' do
    context 'with "before"' do
      it_behaves_like 'date operator', 'before' do
        let(:statement_operations) { [:lt] }
      end
    end

    context 'with "after"' do
      it_behaves_like 'date operator', 'after' do
        let(:statement_operations) { [:gt] }
      end
    end

    context 'with "during"' do
      it_behaves_like 'date operator', 'during' do
        let(:statement_operations) { [:gte, :lte] }
      end
    end
  end

  context 'with multiple prefix clauses before a search term' do
    let(:query) { 'from:me has:media foo' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to contain_exactly('foo')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:prefix)).to contain_exactly('from', 'has')
    end
  end

  context 'with a search term between two prefix clauses' do
    let(:query) { 'from:me foo has:media' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to contain_exactly('foo')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:prefix)).to contain_exactly('from', 'has')
    end
  end

  describe '#database_scope' do
    subject(:database_scope) { described_class.new.apply(parser, current_account: account).database_scope }

    let(:public_account) { Fabricate(:account, indexable: true) }

    context 'when the query only uses in:library' do
      let(:query) { 'in:library' }
      let!(:own_status) { Fabricate(:status, account: account, visibility: :public, text: 'Own searchable status') }
      let!(:reblogged_status) { Fabricate(:status, account: public_account, visibility: :public, text: 'Reblogged searchable status') }
      let!(:reblog) { Fabricate(:status, account: account, visibility: :public, reblog: reblogged_status) }

      it 'returns searchable results without surfacing boost rows' do
        expect(database_scope.pluck(:id)).to contain_exactly(own_status.id, reblogged_status.id)
        expect(database_scope.pluck(:id)).to_not include(reblog.id)
      end
    end

    context 'when filtering by embeds' do
      let(:query) { 'has:embed in:public' }
      let!(:embedded_status) { Fabricate(:status, account: public_account, visibility: :public, text: 'Embedded status') }
      let!(:linked_status) { Fabricate(:status, account: public_account, visibility: :public, text: 'Linked status') }

      before do
        PreviewCardsStatus.create!(status: embedded_status, preview_card: Fabricate(:preview_card, type: :video), url: 'https://example.com/video')
        PreviewCardsStatus.create!(status: linked_status, preview_card: Fabricate(:preview_card, type: :link), url: 'https://example.com/link')
      end

      it 'matches the embed searchable property' do
        expect(database_scope.pluck(:id)).to contain_exactly(embedded_status.id)
      end
    end

    context 'when filtering by an unknown property' do
      let(:query) { 'has:not-a-real-property in:public' }

      before do
        Fabricate(:status, account: public_account, visibility: :public, text: 'Still searchable otherwise')
      end

      it 'returns no rows instead of ignoring the filter' do
        expect(database_scope).to be_empty
      end
    end

    context 'when searching poll options' do
      let(:query) { 'borealis in:public' }
      let!(:matching_status) do
        Fabricate(
          :status,
          account: public_account,
          visibility: :public,
          text: 'Plain status body',
          poll: Fabricate.build(:poll, account: public_account, options: ['Aurora Borealis', 'Other option'])
        )
      end

      it 'matches text stored on the related poll' do
        expect(database_scope.pluck(:id)).to contain_exactly(matching_status.id)
      end
    end

    context 'when searching media descriptions' do
      let(:query) { 'cerulean in:public' }
      let!(:matching_status) do
        Fabricate(
          :status,
          account: public_account,
          visibility: :public,
          text: 'Plain status body',
          media_attachments: [Fabricate.build(:media_attachment, account: public_account, description: 'Cerulean skyline')]
        )
      end

      it 'matches text stored on related media attachments' do
        expect(database_scope.pluck(:id)).to contain_exactly(matching_status.id)
      end
    end

    context 'when the current account voted in a poll' do
      let(:query) { 'ballot in:library' }
      let(:remote_account) { Fabricate(:account, domain: 'example.com', indexable: false) }
      let!(:matching_status) do
        Fabricate(
          :status,
          account: remote_account,
          visibility: :public,
          text: 'Ballot status body',
          poll: Fabricate.build(:poll, account: remote_account, options: ['Yes', 'No'])
        )
      end

      before do
        Fabricate(:poll_vote, account: account, poll: matching_status.poll, choice: 0)
      end

      it 'treats the vote as a searchable library interaction' do
        expect(database_scope.pluck(:id)).to contain_exactly(matching_status.id)
      end
    end
  end
end
