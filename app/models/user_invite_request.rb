# frozen_string_literal: true

# == Schema Information
#
# Table name: user_invite_requests
#
#  id         :bigint(8)        not null, primary key
#  text       :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint(8)        not null
#

class UserInviteRequest < ApplicationRecord
  TEXT_SIZE_LIMIT = 420

  attr_accessor :require_url

  def self.includes_url?(text)
    Extractor.extract_urls_with_indices(text.to_s, extract_url_without_protocol: false).any?
  end

  belongs_to :user, inverse_of: :invite_request
  validates :text, length: { maximum: TEXT_SIZE_LIMIT }
  validates :text, presence: true, unless: :require_url?
  validate :text_must_include_url, if: :require_url?

  private

  def require_url?
    !!@require_url
  end

  def text_must_include_url
    return if self.class.includes_url?(text)

    errors.add(:text, :missing_url)
  end
end
