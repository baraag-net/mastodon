# frozen_string_literal: true

class AddPostgresFtsIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  STATUSES_TSV_EXPRESSION = <<~SQL.squish.freeze
    setweight(to_tsvector('simple', COALESCE(spoiler_text, '')), 'A')
    || setweight(to_tsvector('simple', COALESCE(text, '')), 'B')
  SQL

  MEDIA_ATTACHMENTS_DESCRIPTION_TSV_EXPRESSION = "to_tsvector('simple'::regconfig, COALESCE(description, ''::text))"

  def up
    unless column_exists?(:statuses, :tsv)
      safety_assured do
        add_column :statuses, :tsv, :virtual, type: :tsvector, as: STATUSES_TSV_EXPRESSION, stored: true
      end
    end

    add_index :statuses, :tsv, using: :gin, algorithm: :concurrently, name: :index_statuses_on_tsv, if_not_exists: true
    add_index :media_attachments, MEDIA_ATTACHMENTS_DESCRIPTION_TSV_EXPRESSION, using: :gin, algorithm: :concurrently, name: :index_media_attachments_on_description_tsv, if_not_exists: true
  end

  def down
    remove_index :media_attachments, name: :index_media_attachments_on_description_tsv, if_exists: true
    remove_index :statuses, name: :index_statuses_on_tsv, if_exists: true
    remove_column :statuses, :tsv
  end
end
