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
        "demoData": "Demo data is active until real API templates are connected.",
        "liveUsageCaption": "OpenAI can use live organization usage. Other providers stay visible until their adapters exist.",
        "liveData": "Live data",
        "unsupportedProviders": "Unsupported",
        "openAILiveUsage": "OpenAI Live Usage",
        "openAIAdminKey": "OPENAI_ADMIN_KEY",
        "save": "Save",
        "clear": "Clear",
        "openAIKeySaved": "OpenAI admin key saved. Refreshing live usage.",
        "openAIKeyCleared": "OpenAI admin key removed.",
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
        ,"blockedModels": "Blocked models"
        ,"perRunCap": "Per-run cap"
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
        "demoData": "接入真实 API 模板前，当前使用演示数据。",
        "liveUsageCaption": "OpenAI 可读取组织级真实用量；其他平台会保留但标记为未支持。",
        "liveData": "实时数据",
        "unsupportedProviders": "未支持",
        "openAILiveUsage": "OpenAI 实时用量",
        "openAIAdminKey": "OPENAI_ADMIN_KEY",
        "save": "保存",
        "clear": "清除",
        "openAIKeySaved": "OpenAI 管理员密钥已保存，正在刷新实时用量。",
        "openAIKeyCleared": "OpenAI 管理员密钥已移除。",
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
        ,"blockedModels": "禁用模型"
        ,"perRunCap": "单次上限"
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
    ]
}
