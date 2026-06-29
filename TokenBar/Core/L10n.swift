import Foundation

enum L10n {
    static func t(_ key: String, _ language: AppLanguage) -> String {
        switch language {
        case .english:
            english[key] ?? key
        case .chinese:
            chinese[key] ?? english[key] ?? key
        }
    }

    private static let english: [String: String] = [
        "app.title": "TokenBar",
        "dashboard": "Dashboard",
        "settings": "Settings",
        "refresh": "Refresh",
        "quit": "Quit",
        "healthy": "Healthy",
        "warning": "Warning",
        "critical": "Critical",
        "today": "Today",
        "month": "Month",
        "remaining": "Remaining",
        "burnRate": "Burn rate",
        "reset": "Reset",
        "prediction": "Prediction",
        "focusMode": "Focus Mode",
        "sessionBudget": "Session Budget",
        "sessionSpend": "Session Spend",
        "start": "Start",
        "stop": "Stop",
        "privacyAudit": "Privacy Audit",
        "smartInsights": "Smart Insights",
        "statusBar": "Menu Bar",
        "content": "Content",
        "routingMode": "Routing Mode",
        "smartRouting": "Smart Routing",
        "confidence": "Confidence",
        "evidence": "Evidence",
        "winRate": "Win rate",
        "provider": "Provider",
        "customText": "Custom Text",
        "appIcon": "App Icon",
        "language": "Language",
        "platforms": "Platforms",
        "localFirst": "Local-first. Keys stay in Keychain.",
        "mcp": "Local API",
        "mcpCaption": "AI agents can read quota signals from localhost when enabled.",
        "openSettings": "Open Settings",
        "noProvider": "No provider selected",
        "allProviders": "All Providers",
        "budgetAtRisk": "Budget at risk",
        "budgetSafe": "Budget safe",
        "recommendation": "Recommendation",
        "addProvider": "Add Provider",
        "keychain": "Keychain",
        "liveUsageCaption": "OpenAI, Anthropic, and OpenRouter can use live provider APIs with keys. Providers without adapters stay visible with honest source states.",
        "liveData": "Live data",
        "unsupportedProviders": "Not live",
        "openAILiveUsage": "OpenAI Live Usage",
        "openAIAdminKey": "OPENAI_ADMIN_KEY",
        "anthropicLiveUsage": "Anthropic Live Usage",
        "anthropicAdminKey": "ANTHROPIC_ADMIN_KEY",
        "openRouterLiveUsage": "OpenRouter Live Credits",
        "openRouterAPIKey": "OPENROUTER_API_KEY",
        "miniMaxLiveUsage": "MiniMax Access",
        "miniMaxAPIKey": "MINIMAX_API_KEY",
        "save": "Save",
        "clear": "Clear",
        "openAIKeySaved": "OpenAI admin key saved. Refreshing live usage.",
        "openAIKeyCleared": "OpenAI admin key removed.",
        "anthropicKeySaved": "Anthropic Admin API key saved. Refreshing live usage.",
        "anthropicKeyCleared": "Anthropic Admin API key removed.",
        "openRouterKeySaved": "OpenRouter API key saved. Refreshing live credits.",
        "openRouterKeyCleared": "OpenRouter API key removed.",
        "miniMaxKeySaved": "MiniMax API key saved. Refreshing access status.",
        "miniMaxKeyCleared": "MiniMax API key removed.",
        "communitySignal": "Community-backed feature set: reset countdowns, budget alerts, local discovery, and cross-provider totals.",
        "lastUpdated": "Last updated"
        ,"keyDiscovery": "Key Discovery"
        ,"scan": "Scan"
        ,"noKeysFound": "No keys found. TokenBar never displays secret values."
        ,"keyDiscoveryTitle": "Find provider keys locally"
        ,"keyDiscoveryCaption": "Choose exactly where TokenBar should look. Scans run only when you press Scan, secret values are never shown, and results use shortened locations."
        ,"scanTargets": "Scan targets"
        ,"scanShellProfiles": "Shell profiles (~/.zshrc, ~/.zprofile, ~/.bashrc)"
        ,"scanHomeEnv": "Home .env file"
        ,"addFiles": "Add Files"
        ,"addFolderEnv": "Add Folder .env"
        ,"selectedLocations": "Selected locations"
        ,"removeLocation": "Remove location"
        ,"scanSelected": "Scan Selected Locations"
        ,"keyDiscoveryPrivacyNote": "No project-wide crawl."
        ,"chooseScanTargets": "Choose scan targets"
        ,"chooseScanTargetsDescription": "TokenBar waits for an explicit scope before reading local files."
        ,"noKeysFoundDescription": "Try a shell profile, ~/.env, or one selected project folder's .env."
        ,"addFilesPanelMessage": "Select shell, env, or config files to scan for supported provider key names."
        ,"addFolderPanelMessage": "Select folders whose direct .env file should be checked. TokenBar does not scan recursively."
        ,"importKey": "Import"
        ,"keyDiscoveryImporting": "Importing to Keychain and refreshing provider state."
        ,"keyDiscoveryImportedFormat": "%@ key imported from %@. Provider state is refreshing."
        ,"keyDiscoveryImportFailedFormat": "Import failed: %@"
        ,"keyDiscoveryImportHelpFormat": "Import %@ into TokenBar Keychain as %@."
        ,"keyDiscoveryImportUnsupported": "This provider cannot be imported into live settings yet."
        ,"notifications": "Notifications"
        ,"runway": "Runway"
        ,"api": "API"
        ,"summary": "Summary"
        ,"daily": "Daily"
        ,"weekly": "Weekly"
        ,"monthly": "Monthly"
        ,"automaticMonitoring": "Automatic monitoring"
        ,"needsConsole": "Needs console or manual budget"
        ,"realRequest": "Real request"
        ,"models": "Models"
        ,"subscriptionAlert": "Subscription alert"
        ,"source": "Source"
        ,"spend": "Spend"
        ,"tokens": "Tokens"
        ,"requests": "Requests"
        ,"projected": "Projected"
        ,"productTagline": "Local policy guard for AI coding agents."
        ,"guard": "Guard"
        ,"workspaces": "Workspaces"
        ,"integrations": "Integrations"
        ,"preflight": "Agent Preflight"
        ,"checkPolicy": "Check Policy"
        ,"agent": "Agent"
        ,"workspace": "Workspace"
        ,"model": "Model"
        ,"estimatedRun": "Estimated run"
        ,"estimatedTokens": "Estimated tokens"
        ,"workspaceBudget": "Workspace budget"
        ,"projectedToday": "Projected today"
        ,"fallback": "Fallback"
        ,"decisionAllow": "Allowed to run"
        ,"decisionWarn": "Run with caution"
        ,"decisionBlock": "Blocked by policy"
        ,"recentDecisions": "Recent decisions"
        ,"dailyBudget": "Daily budget"
        ,"monthlyBudget": "Monthly budget"
        ,"allowedProviders": "Allowed providers"
        ,"preferredProvider": "Preferred provider"
        ,"defaultModel": "Default model"
        ,"blockedModels": "Blocked models"
        ,"perRunCap": "Per-run cap"
        ,"perRunCapHelp": "Blocks runs when estimated cost exceeds this workspace cap. Editable here; no fixed upper limit."
        ,"decreasePerRunCap": "Decrease per-run cap"
        ,"increasePerRunCap": "Increase per-run cap"
        ,"companyKey": "Company key"
        ,"required": "Required"
        ,"optional": "Optional"
        ,"localAPI": "Local API"
        ,"off": "Off"
        ,"stopped": "Stopped"
        ,"failed": "Failed"
        ,"localAPIDisabled": "Disabled"
        ,"localAPIStarting": "Starting"
        ,"localAPIRunning": "Listening"
        ,"localAPIStopped": "Stopped"
        ,"localAPIFailed": "Failed"
        ,"localAPIDisabledDetail": "The localhost API is off."
        ,"localAPIStartingDetail": "Opening localhost:%d."
        ,"localAPIRunningDetail": "Serving requests on localhost:%d."
        ,"localAPIStoppedDetail": "The listener is not running."
        ,"localAPIFailedDetail": "The localhost API could not start."
        ,"modelUsage": "Model Usage"
        ,"modelUsageEmpty": "No local model usage yet. Claude Code and Codex hooks will fill this after their next run."
        ,"configuredModel": "Configured model"
        ,"localUsage": "Local usage"
        ,"configured": "Configured"
        ,"quotaWindows": "Quota Windows"
        ,"quotaWindowsEmpty": "No live quota windows yet. Codex, MiniMax, and CC Switch providers appear here after refresh."
        ,"noLiveQuotaYet": "No live quota detail has been reported yet."
        ,"noBudgetSet": "No budget set"
        ,"noSessionBudget": "No session budget"
        ,"baseURL": "Base URL"
        ,"pullModels": "Pull Models"
        ,"modelCatalog": "Model Catalog"
        ,"modelCatalogRefreshing": "Pulling provider models..."
        ,"modelCatalogEmpty": "No models were returned."
        ,"modelCatalogLoadedFormat": "%d models loaded."
        ,"modelCatalogHelp": "Models are pulled from provider APIs, CC Switch config, and local Codex/Claude config."
        ,"manualModelEntry": "Manual model"
    ]

    private static let chinese: [String: String] = [
        "app.title": "TokenBar",
        "dashboard": "仪表盘",
        "settings": "设置",
        "refresh": "刷新",
        "quit": "退出",
        "healthy": "正常",
        "warning": "警告",
        "critical": "严重",
        "today": "今日",
        "month": "本月",
        "remaining": "剩余",
        "burnRate": "燃烧率",
        "reset": "重置",
        "prediction": "预测",
        "focusMode": "专注模式",
        "sessionBudget": "会话预算",
        "sessionSpend": "会话花费",
        "start": "开始",
        "stop": "停止",
        "privacyAudit": "隐私审计",
        "smartInsights": "智能建议",
        "statusBar": "菜单栏",
        "content": "显示内容",
        "routingMode": "路由模式",
        "smartRouting": "智能路由",
        "confidence": "置信度",
        "evidence": "证据",
        "winRate": "胜率",
        "provider": "平台",
        "customText": "自定义文本",
        "appIcon": "App 图标",
        "language": "语言",
        "platforms": "平台",
        "localFirst": "本地优先，密钥只进 Keychain。",
        "mcp": "本地 API",
        "mcpCaption": "启用后，AI Agent 可从 localhost 读取额度信号。",
        "openSettings": "打开设置",
        "noProvider": "未选择平台",
        "allProviders": "所有平台",
        "budgetAtRisk": "预算有风险",
        "budgetSafe": "预算安全",
        "recommendation": "建议",
        "addProvider": "添加平台",
        "keychain": "钥匙串",
        "liveUsageCaption": "OpenAI、Anthropic 和 OpenRouter 可通过密钥读取真实平台数据；未接入的平台会保留并显示真实来源状态。",
        "liveData": "实时数据",
        "unsupportedProviders": "未实时",
        "openAILiveUsage": "OpenAI 实时用量",
        "openAIAdminKey": "OPENAI_ADMIN_KEY",
        "anthropicLiveUsage": "Anthropic 实时用量",
        "anthropicAdminKey": "ANTHROPIC_ADMIN_KEY",
        "openRouterLiveUsage": "OpenRouter 实时额度",
        "openRouterAPIKey": "OPENROUTER_API_KEY",
        "miniMaxLiveUsage": "MiniMax 访问检测",
        "miniMaxAPIKey": "MINIMAX_API_KEY",
        "save": "保存",
        "clear": "清除",
        "openAIKeySaved": "OpenAI 管理员密钥已保存，正在刷新实时用量。",
        "openAIKeyCleared": "OpenAI 管理员密钥已移除。",
        "anthropicKeySaved": "Anthropic Admin API 密钥已保存，正在刷新实时用量。",
        "anthropicKeyCleared": "Anthropic Admin API 密钥已移除。",
        "openRouterKeySaved": "OpenRouter API 密钥已保存，正在刷新实时额度。",
        "openRouterKeyCleared": "OpenRouter API 密钥已移除。",
        "miniMaxKeySaved": "MiniMax API 密钥已保存，正在刷新访问状态。",
        "miniMaxKeyCleared": "MiniMax API 密钥已移除。",
        "communitySignal": "来自社区需求的功能：重置倒计时、预算提醒、本地发现、跨平台汇总。",
        "lastUpdated": "上次更新"
        ,"keyDiscovery": "密钥发现"
        ,"scan": "扫描"
        ,"noKeysFound": "未发现密钥。TokenBar 永远不显示密钥值。"
        ,"keyDiscoveryTitle": "在本机查找平台密钥"
        ,"keyDiscoveryCaption": "选择 TokenBar 可以查看的位置。只有点击扫描后才会读取文件，不显示密钥值，结果只展示简化位置。"
        ,"scanTargets": "扫描范围"
        ,"scanShellProfiles": "Shell 配置文件（~/.zshrc、~/.zprofile、~/.bashrc）"
        ,"scanHomeEnv": "主目录 .env 文件"
        ,"addFiles": "添加文件"
        ,"addFolderEnv": "添加文件夹 .env"
        ,"selectedLocations": "已选位置"
        ,"removeLocation": "移除位置"
        ,"scanSelected": "扫描已选位置"
        ,"keyDiscoveryPrivacyNote": "不全项目爬取。"
        ,"chooseScanTargets": "选择扫描范围"
        ,"chooseScanTargetsDescription": "TokenBar 会等待你明确选择范围后再读取本地文件。"
        ,"noKeysFoundDescription": "可以尝试 Shell 配置、~/.env，或某个项目文件夹下的直接 .env。"
        ,"addFilesPanelMessage": "选择要扫描的平台密钥名称所在的 shell、env 或配置文件。"
        ,"addFolderPanelMessage": "选择要检查直接 .env 文件的文件夹。TokenBar 不会递归扫描。"
        ,"importKey": "导入"
        ,"keyDiscoveryImporting": "正在导入钥匙串并刷新平台状态。"
        ,"keyDiscoveryImportedFormat": "%@ 密钥已从 %@ 导入，平台状态正在刷新。"
        ,"keyDiscoveryImportFailedFormat": "导入失败：%@"
        ,"keyDiscoveryImportHelpFormat": "将 %@ 作为 %@ 导入 TokenBar 钥匙串。"
        ,"keyDiscoveryImportUnsupported": "这个平台暂不能导入到实时设置。"
        ,"notifications": "通知"
        ,"runway": "可用时间"
        ,"api": "API"
        ,"summary": "Summary"
        ,"daily": "每日"
        ,"weekly": "每周"
        ,"monthly": "每月"
        ,"automaticMonitoring": "自动监控"
        ,"needsConsole": "需要控制台或手动预算"
        ,"realRequest": "真实请求"
        ,"models": "模型"
        ,"subscriptionAlert": "订阅预警"
        ,"source": "来源"
        ,"spend": "花费"
        ,"tokens": "Token"
        ,"requests": "请求"
        ,"projected": "预测"
        ,"productTagline": "给 AI 编程 Agent 用的本地策略守卫。"
        ,"guard": "守卫"
        ,"workspaces": "工作区"
        ,"integrations": "集成"
        ,"preflight": "Agent 预检"
        ,"checkPolicy": "检查策略"
        ,"agent": "Agent"
        ,"workspace": "工作区"
        ,"model": "模型"
        ,"estimatedRun": "预计运行"
        ,"estimatedTokens": "预计 Token"
        ,"workspaceBudget": "工作区预算"
        ,"projectedToday": "今日预测"
        ,"fallback": "备用"
        ,"decisionAllow": "允许运行"
        ,"decisionWarn": "谨慎运行"
        ,"decisionBlock": "策略阻止"
        ,"recentDecisions": "最近决策"
        ,"dailyBudget": "每日预算"
        ,"monthlyBudget": "每月预算"
        ,"allowedProviders": "允许平台"
        ,"preferredProvider": "首选平台"
        ,"defaultModel": "默认模型"
        ,"blockedModels": "禁用模型"
        ,"perRunCap": "单次上限"
        ,"perRunCapHelp": "估算成本超过该工作区上限时会阻止运行。可在这里编辑，没有固定上限。"
        ,"decreasePerRunCap": "降低单次上限"
        ,"increasePerRunCap": "提高单次上限"
        ,"companyKey": "公司密钥"
        ,"required": "必需"
        ,"optional": "可选"
        ,"localAPI": "本地 API"
        ,"off": "关闭"
        ,"stopped": "已停止"
        ,"failed": "失败"
        ,"localAPIDisabled": "已关闭"
        ,"localAPIStarting": "正在启动"
        ,"localAPIRunning": "正在监听"
        ,"localAPIStopped": "已停止"
        ,"localAPIFailed": "启动失败"
        ,"localAPIDisabledDetail": "localhost API 已关闭。"
        ,"localAPIStartingDetail": "正在打开 localhost:%d。"
        ,"localAPIRunningDetail": "正在通过 localhost:%d 提供请求。"
        ,"localAPIStoppedDetail": "监听器未运行。"
        ,"localAPIFailedDetail": "localhost API 无法启动。"
        ,"modelUsage": "模型用量"
        ,"modelUsageEmpty": "还没有本地模型用量。Claude Code 和 Codex hook 下一次运行后会写入这里。"
        ,"configuredModel": "配置模型"
        ,"localUsage": "本地用量"
        ,"configured": "已配置"
        ,"quotaWindows": "额度窗口"
        ,"quotaWindowsEmpty": "还没有实时额度窗口。刷新后会显示 Codex、MiniMax 和 CC Switch 供应商。"
        ,"noLiveQuotaYet": "还没有上报实时额度详情。"
        ,"noBudgetSet": "未设置预算"
        ,"noSessionBudget": "未设置会话预算"
        ,"baseURL": "Base URL"
        ,"pullModels": "拉取模型"
        ,"modelCatalog": "模型目录"
        ,"modelCatalogRefreshing": "正在拉取供应商模型..."
        ,"modelCatalogEmpty": "没有返回模型。"
        ,"modelCatalogLoadedFormat": "已加载 %d 个模型。"
        ,"modelCatalogHelp": "模型会从供应商 API、CC Switch 配置、本机 Codex/Claude 配置中读取。"
        ,"manualModelEntry": "手动模型"
    ]
}
