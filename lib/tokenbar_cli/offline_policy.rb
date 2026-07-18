# frozen_string_literal: true

require "time"

module TokenBarCLI
  module OfflinePolicy
    COMPANY_MANAGED_KEY_SOURCES = %w[
      company
      company_managed
      managed
      codex_managed
      tokenbar_keychain
      tokenbar
      api_proxy
      org
      workspace
    ].freeze

    module_function

    def evaluate(input, config, agent_display:, now: Time.now.utc)
      policy = workspace(config, input["workspaceID"])
      projected_daily_spend = policy["spendToday"].to_f + input["estimatedCost"].to_f
      projected_monthly_spend = policy["spendMonth"].to_f + input["estimatedCost"].to_f
      status = "allow"
      reasons = []

      unless policy["allowedProviderIDs"].include?(input["providerID"])
        status = "block"
        reasons << "Provider is not allowed for this workspace."
      end

      if policy["blockedModels"].any? { |blocked| input["model"].to_s.downcase.include?(blocked.to_s.downcase) }
        status = "block"
        reasons << "Model is blocked by the workspace policy."
      end

      per_run_cap = policy["maxEstimatedRunCost"].to_f
      if per_run_cap.positive? && input["estimatedCost"].to_f > per_run_cap
        status = "block"
        reasons << "Estimated run cost is above the per-run cap."
      end

      if policy["maxEstimatedTokens"].to_i.positive? && input["estimatedTokens"].to_i > policy["maxEstimatedTokens"].to_i
        status = "block"
        reasons << "Estimated run tokens are above the workspace token cap."
      end

      if policy["requireCompanyKey"] && company_key_required_but_unsatisfied?(input)
        status = "block"
        reasons << "Workspace requires a company-managed key."
      end

      status = apply_budget_rule(
        status,
        reasons,
        projected_spend: projected_daily_spend,
        budget: policy["dailyBudget"],
        period: "daily"
      )
      status = apply_budget_rule(
        status,
        reasons,
        projected_spend: projected_monthly_spend,
        budget: policy["monthlyBudget"],
        period: "monthly"
      )

      reasons << "Workspace, provider, model, and budget are inside policy." if reasons.empty?
      fallback = policy["allowedProviderIDs"].find { |provider| provider != input["providerID"] }
      timestamp = now.utc.iso8601

      {
        "version" => "1.0",
        "timestamp" => timestamp,
        "localOnly" => true,
        "offline" => true,
        "decision" => {
          "status" => status,
          "agent" => agent_display.fetch(input["agent"], input["agent"]),
          "workspace" => {
            "id" => policy["id"],
            "name" => policy["name"]
          },
          "provider" => input["providerID"],
          "model" => input["model"],
          "keySource" => input["keySource"],
          "estimatedCost" => input["estimatedCost"].to_f,
          "projectedDailySpend" => projected_daily_spend,
          "projectedMonthlySpend" => projected_monthly_spend,
          "reasons" => reasons,
          "recommendation" => recommendation(status, input["model"], fallback),
          "fallbackProvider" => fallback,
          "timestamp" => timestamp
        }
      }
    end

    def workspace(config, workspace_id)
      workspace = config.fetch("workspace", {})
      budgets = config.fetch("budgets", {})
      providers = config.fetch("providers", {})
      models = config.fetch("models", {})
      rules = config.fetch("rules", {})

      {
        "id" => workspace["id"] || workspace_id,
        "name" => workspace["name"] || workspace["id"] || workspace_id,
        "pathHint" => workspace["path"] || workspace["pathHint"] || Dir.pwd,
        "client" => workspace["client"] || "local",
        "dailyBudget" => numeric_config(budgets["daily"], 0),
        "monthlyBudget" => numeric_config(budgets["monthly"], 0),
        "spendToday" => numeric_config(budgets["spend_today"] || budgets["spendToday"], 0),
        "spendMonth" => numeric_config(budgets["spend_month"] || budgets["spendMonth"], 0),
        "allowedProviderIDs" => Array(providers["allowed"]).map(&:to_s),
        "blockedModels" => Array(models["blocked"]).map(&:to_s),
        "maxEstimatedRunCost" => numeric_config(budgets["max_run"] || budgets["maxEstimatedRunCost"], Float::INFINITY),
        "maxEstimatedTokens" => integer_config(rules["max_estimated_tokens"] || rules["maxEstimatedTokens"], 0),
        "requireCompanyKey" => providers["require_company_key"] == true || providers["requireCompanyKey"] == true,
        "preferredProviderID" => providers["preferred"],
        "preferredModel" => models["default"]
      }
    end

    def apply_budget_rule(status, reasons, projected_spend:, budget:, period:)
      numeric_budget = budget.to_f
      return status unless numeric_budget.positive?

      if projected_spend >= numeric_budget
        reasons << "Projected #{period} spend would exceed the workspace budget."
        "block"
      elsif projected_spend >= numeric_budget * 0.8 && status != "block"
        reasons << "Projected #{period} spend is close to the workspace budget."
        "warn"
      else
        status
      end
    end

    def company_key_required_but_unsatisfied?(input)
      return false unless input["providerID"] == "openai"

      !company_managed_key_source?(input["keySource"])
    end

    def company_managed_key_source?(source)
      normalized = source.to_s.downcase.tr("-", "_")
      COMPANY_MANAGED_KEY_SOURCES.include?(normalized)
    end

    def recommendation(status, model, fallback)
      case status
      when "allow"
        "Continue with #{model}. Keep the agent on this workspace policy."
      when "warn"
        "Continue only if this run is necessary, or switch to #{fallback || "a cheaper allowed provider"} first."
      else
        "Stop this run. Switch provider/model or raise the workspace budget after review."
      end
    end

    def integer_config(value, fallback)
      return fallback if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def numeric_config(value, fallback)
      return fallback if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      fallback
    end

    private_class_method :apply_budget_rule,
                         :company_key_required_but_unsatisfied?,
                         :company_managed_key_source?,
                         :recommendation,
                         :integer_config,
                         :numeric_config
  end
end
