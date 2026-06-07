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
        "communitySignal": "Community-backed feature set: reset countdowns, budget alerts, local discovery, and cross-provider totals.",
        "lastUpdated": "Last updated"
        ,"keyDiscovery": "Key Discovery"
        ,"scan": "Scan"
        ,"noKeysFound": "No keys found. TokenBar never displays secret values."
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
        "communitySignal": "来自社区需求的功能：重置倒计时、预算提醒、本地发现、跨平台汇总。",
        "lastUpdated": "上次更新"
        ,"keyDiscovery": "密钥发现"
        ,"scan": "扫描"
        ,"noKeysFound": "未发现密钥。TokenBar 永远不显示密钥值。"
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
    ]
}
