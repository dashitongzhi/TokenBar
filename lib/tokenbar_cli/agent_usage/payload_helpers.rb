# frozen_string_literal: true

module TokenBarCLI
  module AgentUsage
    module PayloadHelpers
      def read_stdin_json
        return {} if STDIN.tty?

        raw = STDIN.read
        return {} if blank?(raw)

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def dig_path(value, keys)
        cursor = value
        keys.each do |key|
          return nil unless cursor.is_a?(Hash)

          cursor = cursor[key]
        end
        cursor.is_a?(String) && !cursor.empty? ? cursor : nil
      end

      def string_deep_find(value, keys)
        found = deep_find(value, keys)
        return nil if found.nil? || found.is_a?(Hash) || found.is_a?(Array)

        found.to_s.empty? ? nil : found.to_s
      end

      def numeric_deep_find(value, keys)
        found = deep_find(value, keys)
        return nil if found.nil?

        Float(found)
      rescue ArgumentError, TypeError
        nil
      end

      def integer_deep_find(value, keys)
        found = numeric_deep_find(value, keys)
        found.nil? ? nil : found.to_i
      end

      def iso8601_deep_find(value, keys)
        found = deep_find(value, keys)
        return nil if found.nil?
        return Time.at(found).utc.iso8601 if found.is_a?(Numeric)

        string = found.to_s
        return Time.at(Float(string)).utc.iso8601 if string.match?(/\A\d+(\.\d+)?\z/)

        Time.parse(string).utc.iso8601
      rescue ArgumentError
        nil
      end

      def deep_find(value, keys)
        if value.is_a?(Hash)
          keys.each { |key| return value[key] if value.key?(key) }
          value.each_value do |child|
            found = deep_find(child, keys)
            return found unless found.nil?
          end
        elsif value.is_a?(Array)
          value.each do |child|
            found = deep_find(child, keys)
            return found unless found.nil?
          end
        end
        nil
      end

      def compact_hash(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), memo|
            compacted = compact_hash(item)
            memo[key] = compacted unless compacted.nil?
          end
        when Array
          value.map { |item| compact_hash(item) }.compact
        else
          value
        end
      end
    end
  end
end
