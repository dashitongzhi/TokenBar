# frozen_string_literal: true

module TokenBarCLI
  module AgentUsage
    module ClaudeStatusline
      def claude_statusline_usage_input(payload)
        input_tokens = integer_deep_find(payload, %w[input_tokens inputTokens])
        output_tokens = integer_deep_find(payload, %w[output_tokens outputTokens])
        cache_creation_tokens = integer_deep_find(payload, %w[cache_creation_input_tokens cacheCreationInputTokens]).to_i
        cache_read_tokens = integer_deep_find(payload, %w[cache_read_input_tokens cacheReadInputTokens]).to_i
        explicit_total = integer_deep_find(payload, %w[total_tokens totalTokens tokens_used tokensUsed])
        computed_total = [input_tokens, output_tokens].compact.sum + cache_creation_tokens + cache_read_tokens
        current_directory = dig_path(payload, %w[workspace current_dir]) ||
                            dig_path(payload, %w[workspace currentDirectory]) ||
                            string_deep_find(payload, %w[current_dir currentDirectory cwd])
        model = dig_path(payload, %w[model id]) || dig_path(payload, %w[model name]) || string_deep_find(payload, %w[model_id modelId model])
        {
          "agent" => "claudeCode",
          "providerID" => provider_from_model_or_agent(model, "claudeCode"),
          "model" => model,
          "sessionID" => string_deep_find(payload, %w[session_id sessionId]),
          "source" => "Claude Code statusline",
          "currentDirectory" => current_directory,
          "workspacePath" => current_directory,
          "transcriptPath" => string_deep_find(payload, %w[transcript_path transcriptPath]),
          "costUSD" => numeric_deep_find(payload, %w[total_cost_usd totalCostUSD cost_usd costUSD]),
          "inputTokens" => input_tokens,
          "outputTokens" => output_tokens,
          "totalTokens" => explicit_total || (computed_total.positive? ? computed_total : nil),
          "contextWindowSize" => integer_deep_find(payload, %w[context_window_size contextWindowSize]),
          "requestCount" => integer_deep_find(payload, %w[request_count requestCount]),
          "occurredAt" => iso8601_deep_find(payload, %w[timestamp occurred_at occurredAt]),
          "rateLimitUsedPercentage" => numeric_deep_find(payload, %w[used_percentage usedPercentage rate_limit_used_percentage rateLimitUsedPercentage]),
          "rateLimitResetAt" => iso8601_deep_find(payload, %w[reset_at resetAt rate_limit_reset_at rateLimitResetAt]),
          "cumulative" => true
        }
      end
    end
  end
end
