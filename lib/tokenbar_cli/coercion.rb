# frozen_string_literal: true

module TokenBarCLI
  module Coercion
    module_function

    def integer(value, fallback)
      return fallback if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def numeric(value, fallback)
      return fallback if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
