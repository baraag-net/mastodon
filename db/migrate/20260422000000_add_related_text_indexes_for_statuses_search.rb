# frozen_string_literal: true

class AddRelatedTextIndexesForStatusesSearch < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  MEDIA_ATTACHMENTS_DESCRIPTION_TSV_EXPRESSION = "to_tsvector('simple'::regconfig, COALESCE(description, ''::text))"

  def up
    add_index :media_attachments, MEDIA_ATTACHMENTS_DESCRIPTION_TSV_EXPRESSION, using: :gin, algorithm: :concurrently, name: :index_media_attachments_on_description_tsv, if_not_exists: true
  end

  def down
    remove_index :media_attachments, name: :index_media_attachments_on_description_tsv, if_exists: true
  end
end
