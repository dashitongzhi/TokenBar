# frozen_string_literal: true

module TokenBarCLI
  module AgentUsage
    module CodexUsage
      def codex_session_usage_input(hook_payload, options, config)
        transcript_path = options[:transcript] ||
                          string_deep_find(hook_payload, %w[transcript_path transcriptPath transcript_file transcriptFile transcript])
        transcript = codex_transcript_summary(transcript_path)
        model = options[:model] ||
                string_deep_find(hook_payload, %w[model model_id modelId]) ||
                transcript["model"] ||
                "gpt-5"
        usage = transcript.fetch("usage", {})
        input_tokens = usage["input_tokens"].to_i
        output_tokens = usage["output_tokens"].to_i
        total_tokens = usage["total_tokens"].to_i
        total_tokens = input_tokens + output_tokens if total_tokens.zero? && (input_tokens + output_tokens).positive?
        pricing = codex_pricing_for(model, config)
        cost = numeric_deep_find(hook_payload, %w[cost_usd costUSD total_cost_usd totalCostUSD]) ||
               numeric_env("TOKENBAR_CODEX_COST_USD", nil) ||
               estimate_codex_cost(usage, pricing)
        cwd = options[:cwd] ||
              string_deep_find(hook_payload, %w[cwd current_dir currentDirectory]) ||
              transcript["cwd"] ||
              Dir.pwd
        session_id = options[:session_id] ||
                     string_deep_find(hook_payload, %w[session_id sessionId]) ||
                     transcript["sessionID"] ||
                     (transcript_path ? File.basename(transcript_path, ".jsonl") : nil)

        {
          "agent" => "codex",
          "providerID" => provider_from_model_or_agent(model, "codex") || "openai",
          "model" => model,
          "sessionID" => session_id,
          "source" => "Codex local transcript",
          "currentDirectory" => cwd,
          "workspacePath" => cwd,
          "transcriptPath" => transcript_path,
          "costUSD" => cost,
          "inputTokens" => input_tokens,
          "outputTokens" => output_tokens,
          "totalTokens" => total_tokens,
          "contextWindowSize" => transcript["contextWindowSize"],
          "requestCount" => transcript["requestCount"],
          "occurredAt" => transcript["occurredAt"] || Time.now.utc.iso8601,
          "cumulative" => true
        }
      end

      def apply_codex_prompt_payload!(input, options, payload)
        return if payload.empty?

        input["agent"] = "codex" if input["agent"] == "custom"
        input["model"] ||= dig_path(payload, %w[model id]) ||
                           dig_path(payload, %w[model name]) ||
                           string_deep_find(payload, %w[model model_id modelId])
        input["intent"] = string_deep_find(payload, %w[intent task_kind taskKind]) || input["intent"]
        input["keySource"] ||= string_deep_find(payload, %w[key_source keySource key_provenance keyProvenance])
        options[:prompt] ||= string_deep_find(payload, %w[prompt user_prompt userPrompt message input])
        options[:cwd] ||= string_deep_find(payload, %w[cwd current_dir currentDirectory workspace_path workspacePath])
      end

      def apply_codex_key_source_default!(input, options)
        return unless input["agent"] == "codex"
        return unless blank?(input["keySource"])

        input["keySource"] = if options[:codex_hook_json]
                               "codex_managed"
                             elsif input["providerID"] == "openai" && openai_key_env_present?
                               "env"
                             end
      end

      def openai_key_env_present?
        %w[OPENAI_API_KEY TOKENBAR_OPENAI_API_KEY OPENAI_KEY TOKENBAR_OPENAI_KEY].any? { |name| !blank?(ENV[name]) }
      end

      def apply_codex_preflight_estimate!(input, options, config)
        return nil unless input["agent"] == "codex"
        return nil if options[:cost_explicit] && options[:tokens_explicit]

        prompt = codex_preflight_prompt(options)
        return nil if blank?(prompt)

        model = input["model"] || default_model("openai")
        pricing = codex_pricing_for(model, config)
        estimate = estimate_codex_prompt_run(prompt, model, pricing, config)
        input["estimatedTokens"] = estimate["estimatedTokens"] unless options[:tokens_explicit]
        input["estimatedCost"] = estimate["estimatedCost"] unless options[:cost_explicit]
        estimate
      end

      def codex_preflight_prompt(options)
        return options[:prompt] unless blank?(options[:prompt])
        return nil if blank?(options[:prompt_file])

        Pathname.new(options[:prompt_file]).expand_path.read
      rescue SystemCallError => e
        raise Error, "could not read --prompt-file #{options[:prompt_file]}: #{e.message}"
      end

      def estimate_codex_prompt_run(prompt, model, pricing, config)
        prompt_tokens = approximate_token_count(prompt)
        size = codex_prompt_task_size(prompt, prompt_tokens, config)
        size_estimate = CODEX_TASK_SIZE_ESTIMATES.fetch(size)
        input_tokens = prompt_tokens + size_estimate[:base_input]
        output_tokens = size_estimate[:output]
        usage = {
          "input_tokens" => input_tokens,
          "cached_input_tokens" => 0,
          "output_tokens" => output_tokens,
          "total_tokens" => input_tokens + output_tokens
        }
        cost = estimate_codex_cost(usage, pricing)

        {
          "source" => "codex_prompt_heuristic",
          "model" => model,
          "taskSize" => size.to_s,
          "promptTokens" => prompt_tokens,
          "estimatedInputTokens" => input_tokens,
          "estimatedOutputTokens" => output_tokens,
          "estimatedTokens" => usage["total_tokens"],
          "estimatedCost" => cost.round(6),
          "pricingUSDPer1M" => {
            "input" => pricing[:input].to_f,
            "cachedInput" => pricing[:cached_input].to_f,
            "output" => pricing[:output].to_f
          }
        }
      end

      def approximate_token_count(text)
        normalized = text.to_s.gsub(/\s+/, " ").strip
        return 0 if normalized.empty?

        char_estimate = (normalized.length / CODEX_PROMPT_TOKEN_DIVISOR).ceil
        word_estimate = (normalized.scan(/[[:alnum:]_]+/).length * 1.3).ceil
        [char_estimate, word_estimate, 1].max
      end

      def codex_prompt_task_size(prompt, prompt_tokens, config)
        configured = config&.dig("codex", "preflight_size") || config&.dig("codex", "preflightSize")
        return configured.to_s.downcase.to_sym if CODEX_TASK_SIZE_ESTIMATES.key?(configured.to_s.downcase.to_sym)

        text = prompt.to_s.downcase
        return :xlarge if prompt_tokens >= 8_000 || text.match?(/\b(rewrite|rebuild|migrate|redesign|audit all|entire repo|full app|large refactor)\b/)
        return :large if prompt_tokens >= 2_000 || text.match?(/\b(implement|refactor|verify|test|debug|fix|wire|integrate|frontend|ui|deploy|docs|examples)\b/)
        return :small if prompt_tokens <= 80 && text.match?(/\b(explain|summarize|rename|format|translate|what is|show me)\b/)

        :medium
      end

      def codex_transcript_summary(path)
        raise Error, "missing Codex transcript path; pass --transcript or run from a Codex Stop hook" if blank?(path)

        expanded = Pathname.new(path).expand_path
        raise Error, "Codex transcript not found: #{expanded}" unless expanded.file?

        summary = { "usage" => {}, "requestCount" => 0, "transcriptPath" => expanded.to_s }
        File.foreach(expanded) do |line|
          entry = JSON.parse(line)
          payload = entry["payload"] || {}
          case entry["type"]
          when "session_meta"
            summary["sessionID"] ||= payload["id"]
            summary["cwd"] ||= payload["cwd"]
          when "turn_context"
            summary["cwd"] = payload["cwd"] if payload["cwd"]
            summary["model"] = payload["model"] if payload["model"]
          when "event_msg"
            next unless payload["type"] == "token_count"

            info = payload["info"] || {}
            summary["usage"] = normalize_codex_token_usage(info["total_token_usage"] || {})
            summary["contextWindowSize"] = info["model_context_window"]
            summary["occurredAt"] = entry["timestamp"]
            summary["requestCount"] += 1
          end
        rescue JSON::ParserError
          next
        end
        raise Error, "Codex transcript has no token_count events: #{expanded}" if summary["usage"].empty?

        summary
      end

      def normalize_codex_token_usage(usage)
        {
          "input_tokens" => usage["input_tokens"].to_i,
          "cached_input_tokens" => usage["cached_input_tokens"].to_i,
          "output_tokens" => usage["output_tokens"].to_i,
          "reasoning_output_tokens" => usage["reasoning_output_tokens"].to_i,
          "total_tokens" => usage["total_tokens"].to_i
        }
      end

      def codex_pricing_for(model, config)
        config_rate = codex_config_pricing(model, config)
        env_rate = {
          input: numeric_env("TOKENBAR_CODEX_INPUT_USD_PER_1M", nil),
          cached_input: numeric_env("TOKENBAR_CODEX_CACHED_INPUT_USD_PER_1M", nil),
          output: numeric_env("TOKENBAR_CODEX_OUTPUT_USD_PER_1M", nil)
        }.compact
        return config_rate.merge(env_rate) if config_rate
        return (DEFAULT_CODEX_PRICING.find { |pattern, _rate| model.to_s.match?(pattern) }&.last || {}).merge(env_rate) if env_rate.empty? == false

        DEFAULT_CODEX_PRICING.find { |pattern, _rate| model.to_s.match?(pattern) }&.last ||
          { input: 0.0, cached_input: 0.0, output: 0.0 }
      end

      def codex_config_pricing(model, config)
        pricing = config&.dig("codex", "pricing") || config&.dig("pricing", "codex")
        return nil unless pricing.is_a?(Hash)

        raw = pricing[model.to_s] || pricing[model.to_s.downcase] || pricing["default"]
        return nil unless raw.is_a?(Hash)

        {
          input: numeric_config(raw["input_per_million"] || raw["inputPerMillion"], 0),
          cached_input: numeric_config(raw["cached_input_per_million"] || raw["cachedInputPerMillion"], 0),
          output: numeric_config(raw["output_per_million"] || raw["outputPerMillion"], 0)
        }
      end

      def estimate_codex_cost(usage, pricing)
        input_tokens = usage["input_tokens"].to_i
        cached_input_tokens = [usage["cached_input_tokens"].to_i, input_tokens].min
        uncached_input_tokens = [input_tokens - cached_input_tokens, 0].max
        output_tokens = usage["output_tokens"].to_i

        (uncached_input_tokens * pricing[:input].to_f +
          cached_input_tokens * pricing[:cached_input].to_f +
          output_tokens * pricing[:output].to_f) / 1_000_000.0
      end
    end
  end
end
