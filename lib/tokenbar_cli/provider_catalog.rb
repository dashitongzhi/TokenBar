# frozen_string_literal: true

module TokenBarCLI
  module ProviderCatalog
    PROVIDER_MARKERS = [
      ["anthropic", %w[anthropic claude]],
      ["openai", %w[openai gpt o1 o3 o4]],
      ["openrouter", %w[openrouter]],
      ["minimax", %w[minimax]],
      ["deepseek", %w[deepseek]],
      ["google", %w[gemini google]],
      ["mistral", %w[mistral]],
      ["kimi", %w[kimi]],
      ["xiaomi-mimo", %w[mimo xiaomi]],
      ["glm", %w[glm]],
      ["qwen", %w[qwen]]
    ].freeze

    DEFAULT_MODELS = {
      "anthropic" => "claude-sonnet",
      "openai" => "gpt-5",
      "openrouter" => "openrouter/auto",
      "minimax" => "minimax-m1",
      "deepseek" => "deepseek-chat",
      "google" => "gemini-2.5-pro",
      "mistral" => "mistral-large-latest",
      "kimi" => "kimi-k2",
      "xiaomi-mimo" => "mimo-v2",
      "glm" => "glm-4.5",
      "qwen" => "qwen-max"
    }.freeze

    module_function

    def provider_for(hint: nil, model: nil, fallback: nil)
      haystack = [hint, model].compact.join(" ").downcase
      entry = PROVIDER_MARKERS.find do |_provider, markers|
        markers.any? { |marker| marker_match?(haystack, marker) }
      end
      entry&.first || fallback
    end

    def default_model(provider)
      DEFAULT_MODELS.fetch(provider.to_s, "unspecified")
    end

    def looks_like_model?(value)
      normalized = value.to_s.strip.downcase
      return false if normalized.length < 2 || normalized.length > 120

      PROVIDER_MARKERS.any? do |_provider, markers|
        markers.any? { |marker| marker_match?(normalized, marker) }
      end
    end

    def marker_match?(haystack, marker)
      marker.match?(/\Ao\d\z/) ? haystack.match?(/\b#{Regexp.escape(marker)}\b/) : haystack.include?(marker)
    end
    private_class_method :marker_match?
  end
end
