# frozen_string_literal: true

require "rails_helper"

# Every area under config/locales/<area>/ ships en, sk, cs and es with the same
# keys, so a string added in English can't silently fall back to English in
# the other three.
RSpec.describe "Locale files" do
  # Plural forms differ by language (sk/cs have :few, es/en don't), so they
  # are compared as one "pluralized key" rather than leaf by leaf.
  PLURAL_KEYS = %w[zero one two few many other].freeze

  def flatten(hash, prefix = nil)
    hash.each_with_object([]) do |(key, value), keys|
      path = [prefix, key].compact.join(".")
      if value.is_a?(Hash) && (value.keys.map(&:to_s) - PLURAL_KEYS).empty? && value.key?("other")
        keys << "#{path}(plural)"
      elsif value.is_a?(Hash)
        keys.concat(flatten(value, path))
      else
        keys << path
      end
    end
  end

  Dir[Rails.root.join("config/locales/*/")].sort.each do |dir|
    area = File.basename(dir)

    it "#{area}: sk, cs and es have exactly the English keys" do
      english = flatten(YAML.load_file(File.join(dir, "en.yml")).fetch("en"))

      %w[sk cs es].each do |locale|
        path = File.join(dir, "#{locale}.yml")
        expect(File).to exist(path), "missing #{path}"

        keys = flatten(YAML.load_file(path).fetch(locale))
        expect(keys - english).to be_empty, "#{area}/#{locale}.yml has extra keys: #{(keys - english).first(10)}"
        expect(english - keys).to be_empty, "#{area}/#{locale}.yml is missing keys: #{(english - keys).first(10)}"
      end
    end
  end

  it "sk and cs plurals define :few" do
    Dir[Rails.root.join("config/locales/*/{sk,cs}.yml")].each do |path|
      locale = File.basename(path, ".yml")
      walk = lambda do |node, trail|
        next unless node.is_a?(Hash)

        if node.key?("one") && node.key?("other")
          expect(node).to have_key("few"), "#{path}: #{trail.join('.')} has no :few form"
        else
          node.each { |k, v| walk.call(v, trail + [k]) }
        end
      end
      walk.call(YAML.load_file(path).fetch(locale), [])
    end
  end
end
