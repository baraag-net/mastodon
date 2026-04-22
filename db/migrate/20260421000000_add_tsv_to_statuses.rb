# frozen_string_literal: true

class AddTsvToStatuses < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  GENERATED_EXPRESSION = <<~SQL.squish.freeze
    setweight(to_tsvector('simple', COALESCE(spoiler_text, '')), 'A')
    || setweight(to_tsvector('simple', COALESCE(text, '')), 'B')
  SQL

  def up
    unless column_exists?(:statuses, :tsv)
      safety_assured do
        add_column :statuses, :tsv, :virtual, type: :tsvector, as: GENERATED_EXPRESSION, stored: true
      end
    end

    add_index :statuses, :tsv, using: :gin, algorithm: :concurrently, name: :index_statuses_on_tsv, if_not_exists: true
  end

  def down
    remove_index :statuses, name: :index_statuses_on_tsv, if_exists: true
    remove_column :statuses, :tsv
  end
end
