# frozen_string_literal: true

# Production is MariaDB, where `t.text` is TEXT — capped at 64 KB. Kind-30023
# long-form articles and RSS `content:encoded` bodies routinely exceed that, and
# a single oversized row makes every subsequent ingestion run fail with
# "Data too long for column". MEDIUMTEXT raises the cap to 16 MB.
#
# SQLite (development) has no such distinction — TEXT is unbounded — so the
# column changes are a no-op there and are skipped entirely.
class ChangeLongTextColumnsToMediumtext < ActiveRecord::Migration[8.1]
  MEDIUMTEXT_COLUMNS = {
    events: %i[content raw_data metadata],
    linked_contents: %i[content]
  }.freeze

  def up
    widen_columns

    # REL-H5: kind-30023 articles were looked up with
    # `json_extract(metadata, '$.d_tag') = ?`. On MariaDB JSON_EXTRACT returns
    # the *quoted* JSON fragment (`"slug"`), so that comparison never matched and
    # every refresh inserted a duplicate article. JSON_UNQUOTE would fix MariaDB
    # but does not exist in SQLite, so the portable answer is a real column.
    add_column :events, :d_tag, :string unless column_exists?(:events, :d_tag)
    add_index :events, [ :source_id, :d_tag ] unless index_exists?(:events, [ :source_id, :d_tag ])

    backfill_d_tags
  end

  def down
    remove_index :events, [ :source_id, :d_tag ] if index_exists?(:events, [ :source_id, :d_tag ])
    remove_column :events, :d_tag if column_exists?(:events, :d_tag)

    return unless mysql?

    MEDIUMTEXT_COLUMNS.each do |table, columns|
      columns.each do |column|
        next unless mediumtext_column?(table, column)

        change_column table, column, :text
      end
    end
  end

  private

  def mysql?
    connection.adapter_name.match?(/mysql|maria/i)
  end

  def widen_columns
    return unless mysql?

    MEDIUMTEXT_COLUMNS.each do |table, columns|
      columns.each do |column|
        # raw_data/metadata are declared as `t.json`, which MariaDB implements as
        # LONGTEXT — nothing to widen there, so only real TEXT columns are touched.
        next unless column_sql_type(table, column)&.match?(/\Atext\z/i)

        change_column table, column, :mediumtext
      end
    end
  end

  def mediumtext_column?(table, column)
    column_sql_type(table, column)&.match?(/\Amediumtext\z/i)
  end

  def column_sql_type(table, column)
    connection.columns(table).find { |c| c.name == column.to_s }&.sql_type
  end

  def backfill_d_tags
    event_class = Class.new(ActiveRecord::Base) { self.table_name = "events" }
    event_class.reset_column_information

    event_class.where(d_tag: nil).find_each do |event|
      metadata = event.metadata
      metadata = (JSON.parse(metadata) rescue nil) if metadata.is_a?(String)
      d_tag = metadata.is_a?(Hash) ? metadata["d_tag"] : nil
      next if d_tag.blank?

      event.update_columns(d_tag: d_tag.to_s[0, 255])
    end
  end
end
