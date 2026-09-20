# frozen_string_literal: true

require "rails_helper"

# MariaDB (production) has no native JSON type: `t.json` becomes a longtext with
# a CHECK (json_valid(...)) constraint, and the adapter reports the column back
# as `longtext`. ActiveRecord then types the attribute as Text and serializes a
# Hash with `to_s` — `{"engine" => "chat"}` — which is not JSON, so the write
# fails the constraint. An explicit `attribute :col, :json` pins the type on
# both adapters.
#
# This has to be a *static* check. At runtime under SQLite the column really is
# json, so `type_for_attribute` returns Type::Json whether or not the model
# declares anything — a runtime assertion passes vacuously and catches nothing.
RSpec.describe "json columns" do
  it "are declared as :json attributes in their model source" do
    schema = Rails.root.join("db/schema.rb").read
    table = nil
    missing = []

    schema.each_line do |line|
      table = Regexp.last_match(1) if line =~ /create_table "([^"]+)"/
      next unless line =~ /t\.json "([^"]+)"/

      column = Regexp.last_match(1)
      model = begin
        table.classify.constantize
      rescue NameError
        next
      end
      source = Rails.root.join("app/models/#{table.singularize}.rb")
      next unless source.exist?

      declared = source.read.match?(/^\s*(attribute :#{column}\b.*:json|serialize :#{column}\b)/)
      missing << "#{model.name}##{column}" unless declared
    end

    expect(missing).to be_empty,
      "these json columns serialize as text on MariaDB and will fail " \
      "json_valid() in production — add `attribute :<col>, :json` to the " \
      "model: #{missing.join(', ')}"
  end
end
