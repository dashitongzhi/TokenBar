# frozen_string_literal: true

module TokenBarCLI
  module PolicyConfiguration
    def load_config(explicit_path)
      path = explicit_path ? Pathname.new(explicit_path).expand_path : find_config(Pathname.pwd)
      return nil unless path&.file?

      data = YAML.safe_load(path.read, permitted_classes: [Date, Time], aliases: false) || {}
      normalize_keys(data).merge("path" => path.to_s)
    rescue Psych::SyntaxError => e
      raise Error, "invalid YAML in #{path}: #{e.message}"
    end

    def find_config(start)
      cursor = start.expand_path
      loop do
        CONFIG_NAMES.each do |name|
          candidate = cursor.join(name)
          return candidate if candidate.file?
        end
        parent = cursor.parent
        return nil if parent == cursor

        cursor = parent
      end
    end

    def normalize_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), memo| memo[key.to_s] = normalize_keys(item) }
      when Array
        value.map { |item| normalize_keys(item) }
      else
        value
      end
    end

    def apply_config_defaults!(input, config)
      workspace = config&.fetch("workspace", {}) || {}
      providers = config&.fetch("providers", {}) || {}
      allowed = Array(providers["allowed"]).compact

      input["workspaceID"] ||= workspace["id"] || File.basename(Dir.pwd)
      input["providerID"] ||= providers["preferred"] || allowed.first
      input["model"] ||= config&.dig("models", "default") || default_model(input["providerID"])
    end

    def attach_config_policy!(input, config)
      return input unless config

      workspace = offline_workspace(config, input["workspaceID"] || config.dig("workspace", "id"))
      input["workspaceID"] ||= workspace["id"]
      input["workspaceName"] = workspace["name"]
      input["workspacePath"] = workspace["pathHint"]
      input["workspaceClient"] = workspace["client"]
      input["dailyBudget"] = workspace["dailyBudget"]
      input["monthlyBudget"] = workspace["monthlyBudget"]
      input["maxEstimatedRunCost"] = workspace["maxEstimatedRunCost"]
      input["maxEstimatedTokens"] = workspace["maxEstimatedTokens"]
      input["allowedProviderIDs"] = workspace["allowedProviderIDs"]
      input["blockedModels"] = workspace["blockedModels"]
      input["requireCompanyKey"] = workspace["requireCompanyKey"]
      input["providerID"] ||= config.dig("providers", "preferred") || workspace["allowedProviderIDs"].first
      input["model"] ||= config.dig("models", "default") || default_model(input["providerID"])
      input["preferredProviderID"] = config.dig("providers", "preferred")
      input["preferredModel"] = config.dig("models", "default")
      input
    end

    def attach_routing_config!(input, config)
      return input unless config

      workspace = offline_workspace(config, input["workspaceID"] || config.dig("workspace", "id"))
      input["workspaceID"] ||= workspace["id"]
      input["workspaceName"] ||= workspace["name"]
      input["workspacePath"] ||= workspace["pathHint"]
      input["providerID"] ||= config.dig("providers", "preferred") || workspace["allowedProviderIDs"].first
      input
    end
  end
end
