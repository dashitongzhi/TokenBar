import Foundation

enum APIMonitorCatalog {
    static let all: [APIMonitorSpec] = [
        APIMonitorSpec(
            id: "openai",
            name: "OpenAI / ChatGPT API",
            family: "OpenAI",
            symbolName: "brain.head.profile",
            models: ["GPT-5.2", "GPT-5.1", "GPT-4.1", "o-series", "DALL-E / Images"],
            capability: .automatic,
            usageRequest: APIRequestTemplate(
                method: "GET",
                url: "https://api.openai.com/v1/organization/usage/completions?start_time={unix_start}&end_time={unix_end}&bucket_width=1d&limit=31",
                headers: ["Authorization: Bearer {OPENAI_ADMIN_KEY}", "Content-Type: application/json"],
                body: nil
            ),
            costRequest: APIRequestTemplate(
                method: "GET",
                url: "https://api.openai.com/v1/organization/costs?start_time={unix_start}&end_time={unix_end}&bucket_width=1d&limit=31",
                headers: ["Authorization: Bearer {OPENAI_ADMIN_KEY}", "Content-Type: application/json"],
                body: nil
            ),
            subscriptionURL: "https://platform.openai.com/settings/organization/limits",
            docsURL: "https://platform.openai.com/docs/api-reference/usage",
            alertMetric: "Daily cost, monthly cost, project cost, completions token buckets",
            note: "Requires an OpenAI admin key for organization usage and cost APIs. ChatGPT consumer subscription limits do not expose a public quota API."
        ),
        APIMonitorSpec(
            id: "anthropic",
            name: "Anthropic Claude",
            family: "Claude",
            symbolName: "sparkles",
            models: ["Claude Opus", "Claude Sonnet", "Claude Haiku"],
            capability: .automatic,
            usageRequest: APIRequestTemplate(
                method: "GET",
                url: "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at={iso_start}&ending_at={iso_end}&bucket_width=1d&limit=31",
                headers: ["x-api-key: {ANTHROPIC_ADMIN_KEY}", "anthropic-version: 2023-06-01"],
                body: nil
            ),
            costRequest: APIRequestTemplate(
                method: "GET",
                url: "https://api.anthropic.com/v1/organizations/cost_report?starting_at={iso_start}&ending_at={iso_end}&bucket_width=1d&limit=31",
                headers: ["x-api-key: {ANTHROPIC_ADMIN_KEY}", "anthropic-version: 2023-06-01"],
                body: nil
            ),
            subscriptionURL: "https://console.anthropic.com/settings/limits",
            docsURL: "https://platform.claude.com/docs/en/manage-claude/usage-cost-api",
            alertMetric: "Message token usage, daily cost, workspace cost, code execution cost",
            note: "Requires an Anthropic Admin API key that starts with sk-ant-admin. TokenBar normalizes USD minor-unit cost amounts. Individual Claude plans and Claude subscription quotas do not expose this organization API."
        ),
        APIMonitorSpec(
            id: "gemini",
            name: "Google Gemini",
            family: "Google",
            symbolName: "diamond.fill",
            models: ["Gemini 3", "Gemini 2.5 Pro", "Gemini 2.5 Flash", "Imagen", "Veo"],
            capability: .console,
            usageRequest: APIRequestTemplate(
                method: "GET",
                url: "https://monitoring.googleapis.com/v3/projects/{project_id}/timeSeries?filter=metric.type=\"serviceruntime.googleapis.com/quota/allocation/usage\" resource.type=\"consumer_quota\"",
                headers: ["Authorization: Bearer {GOOGLE_OAUTH_ACCESS_TOKEN}"],
                body: nil
            ),
            costRequest: nil,
            subscriptionURL: "https://aistudio.google.com/app/apikey",
            docsURL: "https://ai.google.dev/gemini-api/docs/rate-limits",
            alertMetric: "RPM, TPM, RPD quota usage from AI Studio or Cloud Monitoring quota metrics",
            note: "Gemini rate limits are per project and visible in AI Studio. Cloud Monitoring quota metrics require Google Cloud OAuth, not a simple Gemini API key."
        ),
        APIMonitorSpec(
            id: "deepseek",
            name: "DeepSeek",
            family: "DeepSeek",
            symbolName: "magnifyingglass",
            models: ["deepseek-chat", "deepseek-reasoner"],
            capability: .automatic,
            usageRequest: APIRequestTemplate(
                method: "GET",
                url: "https://api.deepseek.com/user/balance",
                headers: ["Authorization: Bearer {DEEPSEEK_API_KEY}", "Accept: application/json"],
                body: nil
            ),
            costRequest: nil,
            subscriptionURL: "https://platform.deepseek.com/usage",
            docsURL: "https://api-docs.deepseek.com/api/get-user-balance/",
            alertMetric: "Available balance and availability flag",
            note: "Balance API returns total, granted, and topped-up balances."
        ),
        APIMonitorSpec(
            id: "openrouter",
            name: "OpenRouter",
            family: "Aggregator",
            symbolName: "point.3.connected.trianglepath.dotted",
            models: ["OpenAI", "Anthropic", "Google", "Meta", "Mistral", "DeepSeek"],
            capability: .automatic,
            usageRequest: APIRequestTemplate(
                method: "GET",
                url: "https://openrouter.ai/api/v1/credits",
                headers: ["Authorization: Bearer {OPENROUTER_API_KEY}", "Accept: application/json"],
                body: nil
            ),
            costRequest: nil,
            subscriptionURL: "https://openrouter.ai/settings/credits",
            docsURL: "https://openrouter.ai/docs/api/api-reference/credits/get-credits",
            alertMetric: "Total credits purchased versus total usage",
            note: "Credits API returns total credits purchased and total usage. TokenBar uses this for live balance state; per-period tokens and request counts are not exposed here. Use a management-capable key when required by the account."
        ),
        APIMonitorSpec(
            id: "mistral",
            name: "Mistral AI",
            family: "Mistral",
            symbolName: "wind",
            models: ["mistral-large", "mistral-medium", "mistral-small", "Codestral"],
            capability: .console,
            usageRequest: nil,
            costRequest: nil,
            subscriptionURL: "https://admin.mistral.ai/plateforme/limits",
            docsURL: "https://docs.mistral.ai/admin/user-management-finops/tier",
            alertMetric: "RPS, tokens per minute, tokens per month",
            note: "Official docs direct users to Admin > Limits for current workspace usage tiers; no public usage REST endpoint is documented."
        ),
        APIMonitorSpec(
            id: "xai",
            name: "xAI",
            family: "Grok",
            symbolName: "xmark.circle",
            models: ["Grok"],
            capability: .console,
            usageRequest: nil,
            costRequest: nil,
            subscriptionURL: "https://console.x.ai/team/default/billing",
            docsURL: "https://docs.x.ai/console/billing",
            alertMetric: "Prepaid credits and usage explorer",
            note: "Billing docs describe prepaid credits and Usage explorer; no public quota REST endpoint is documented."
        ),
        APIMonitorSpec(
            id: "groq",
            name: "Groq",
            family: "GroqCloud",
            symbolName: "bolt.fill",
            models: ["Llama", "Mixtral", "Whisper", "OpenAI-compatible chat"],
            capability: .responseHeaders,
            usageRequest: APIRequestTemplate(
                method: "POST",
                url: "https://api.groq.com/openai/v1/chat/completions",
                headers: ["Authorization: Bearer {GROQ_API_KEY}", "Content-Type: application/json"],
                body: #"{"model":"{model}","messages":[{"role":"user","content":"ping"}],"max_completion_tokens":1}"#
            ),
            costRequest: nil,
            subscriptionURL: "https://console.groq.com/settings/billing",
            docsURL: "https://console.groq.com/docs/api-reference",
            alertMetric: "Rate-limit headers and locally accumulated token usage",
            note: "Groq publishes OpenAI-compatible inference endpoints. Use response headers plus local accounting for quota warnings."
        ),
        APIMonitorSpec(
            id: "perplexity",
            name: "Perplexity API",
            family: "Search AI",
            symbolName: "questionmark.circle",
            models: ["Sonar", "Sonar Pro", "Reasoning models"],
            capability: .console,
            usageRequest: nil,
            costRequest: nil,
            subscriptionURL: "https://www.perplexity.ai/settings/api",
            docsURL: "https://docs.perplexity.ai/docs/getting-started/api-groups",
            alertMetric: "Credit balance, API billing dashboard usage chart",
            note: "Perplexity documents credit balance in the billing dashboard; no public quota REST endpoint is documented."
        ),
        APIMonitorSpec(
            id: "together",
            name: "Together AI",
            family: "Open models",
            symbolName: "square.stack.3d.up",
            models: ["Llama", "Qwen", "DeepSeek", "Mistral", "FLUX"],
            capability: .responseHeaders,
            usageRequest: nil,
            costRequest: nil,
            subscriptionURL: "https://api.together.ai/settings/organization/~current/billing",
            docsURL: "https://docs.together.ai/docs/billing-usage-limits",
            alertMetric: "Dynamic rate-limit response headers and billing dashboard costs",
            note: "Together recommends planning against latest rate limits returned in serverless response headers."
        ),
        APIMonitorSpec(
            id: "fireworks",
            name: "Fireworks AI",
            family: "Open models",
            symbolName: "flame.fill",
            models: ["Llama", "Qwen", "DeepSeek", "FLUX", "OpenAI-compatible chat"],
            capability: .manualSubscription,
            usageRequest: nil,
            costRequest: nil,
            subscriptionURL: "https://app.fireworks.ai/settings/billing",
            docsURL: "https://docs.fireworks.ai/faq-new/billing-pricing/how-does-billing-and-credit-usage-work",
            alertMetric: "Monthly tier limit and credit depletion",
            note: "Fireworks documents monthly tier limits and credit behavior, but no public usage REST endpoint is documented."
        ),
        APIMonitorSpec(
            id: "azure-openai",
            name: "Azure OpenAI",
            family: "Microsoft",
            symbolName: "cloud.bolt.fill",
            models: ["Azure OpenAI deployments"],
            capability: .console,
            usageRequest: APIRequestTemplate(
                method: "GET",
                url: "https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.Consumption/usageDetails?api-version=2023-05-01",
                headers: ["Authorization: Bearer {AZURE_OAUTH_ACCESS_TOKEN}"],
                body: nil
            ),
            costRequest: nil,
            subscriptionURL: "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview",
            docsURL: "https://learn.microsoft.com/azure/cost-management-billing/",
            alertMetric: "Azure consumption usage details and budget alerts",
            note: "Uses Azure Resource Manager OAuth and Cost Management, not the Azure OpenAI inference key."
        ),
        APIMonitorSpec(
            id: "bedrock",
            name: "Amazon Bedrock",
            family: "AWS",
            symbolName: "server.rack",
            models: ["Claude", "Llama", "Nova", "Titan", "Mistral"],
            capability: .console,
            usageRequest: APIRequestTemplate(
                method: "POST",
                url: "https://ce.us-east-1.amazonaws.com/",
                headers: ["Authorization: AWS4-HMAC-SHA256 ...", "X-Amz-Target: AWSInsightsIndexService.GetCostAndUsage", "Content-Type: application/x-amz-json-1.1"],
                body: #"{"TimePeriod":{"Start":"{yyyy-mm-dd}","End":"{yyyy-mm-dd}"},"Granularity":"DAILY","Metrics":["UnblendedCost"],"Filter":{"Dimensions":{"Key":"SERVICE","Values":["Amazon Bedrock"]}}}"#
            ),
            costRequest: nil,
            subscriptionURL: "https://console.aws.amazon.com/costmanagement/home",
            docsURL: "https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_GetCostAndUsage.html",
            alertMetric: "AWS Cost Explorer daily unblended cost for Amazon Bedrock",
            note: "Requires AWS SigV4 credentials with Cost Explorer permissions."
        ),
        APIMonitorSpec(
            id: "dashscope",
            name: "Alibaba Cloud DashScope / Qwen",
            family: "Qwen",
            symbolName: "cloud.fill",
            models: ["Qwen", "Qwen VL", "Qwen Audio"],
            capability: .manualSubscription,
            usageRequest: nil,
            costRequest: nil,
            subscriptionURL: "https://bailian.console.aliyun.com/",
            docsURL: "https://help.aliyun.com/zh/model-studio/",
            alertMetric: "Console quota and prepaid balance",
            note: "No stable public quota REST endpoint is documented for direct API-key polling."
        ),
        APIMonitorSpec(
            id: "siliconflow",
            name: "SiliconFlow",
            family: "Open models",
            symbolName: "cpu",
            models: ["DeepSeek", "Qwen", "GLM", "Llama"],
            capability: .manualSubscription,
            usageRequest: nil,
            costRequest: nil,
            subscriptionURL: "https://cloud.siliconflow.cn/account/bill",
            docsURL: "https://docs.siliconflow.cn/",
            alertMetric: "Account balance and local request accounting",
            note: "Use console balance plus local token accounting until a documented quota endpoint is available."
        )
    ]
}
