# frozen_string_literal: true

module Ai
  # Shared helpers for pulling a JSON object out of a free-form model response.
  # A naive /\{[^}]+\}/ match breaks as soon as the JSON contains a nested
  # object or a "}" inside a string value, so everything here counts braces and
  # skips string literals instead.
  module JsonExtraction
    module_function

    # Returns the first balanced {...} substring, or nil when there is none.
    def extract_json_object(text)
      return nil if text.blank?

      start_idx = text.index("{")
      return nil if start_idx.nil?

      extract_balanced_json(text, start_idx)
    end

    # Scans forward from start_idx (which must point at "{") and returns the
    # substring up to the matching closing brace, ignoring braces inside strings.
    def extract_balanced_json(text, start_idx)
      depth = 0
      i = start_idx

      while i < text.length
        char = text[i]
        if char == "{"
          depth += 1
        elsif char == "}"
          depth -= 1
          if depth == 0
            return text[start_idx..i]
          end
        elsif char == '"'
          # Skip string contents (handle escaped quotes)
          i += 1
          while i < text.length
            if text[i] == '\\'
              i += 1 # skip escaped character
            elsif text[i] == '"'
              break
            end
            i += 1
          end
        end
        i += 1
      end

      nil
    end
  end
end
