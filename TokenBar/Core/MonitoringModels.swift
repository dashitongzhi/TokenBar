import Foundation

enum APIMonitorCapability: String, Codable {
    case automatic
    case console
    case responseHeaders
    case manualSubscription

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.automatic, .english): "Automatic"
        case (.console, .english): "Console / Cloud metrics"
        case (.responseHeaders, .english): "Response headers"
        case (.manualSubscription, .english): "Manual subscription"
        case (.automatic, .chinese): "自动读取"
        case (.console, .chinese): "控制台 / 云监控"
        case (.responseHeaders, .chinese): "响应头"
        case (.manualSubscription, .chinese): "手动订阅"
        }
    }

    var status: UsageStatus {
        switch self {
        case .automatic: .healthy
        case .responseHeaders: .warning
        case .console, .manualSubscription: .warning
        }
    }
}
struct APIRequestTemplate: Codable, Equatable {
    var method: String
    var url: String
    var headers: [String]
    var body: String?
}

struct APIMonitorSpec: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var family: String
    var symbolName: String
    var models: [String]
    var capability: APIMonitorCapability
    var usageRequest: APIRequestTemplate?
    var costRequest: APIRequestTemplate?
    var subscriptionURL: String
    var docsURL: String
    var alertMetric: String
    var note: String
}

struct ProbeTemplate: Identifiable, Codable, Equatable {
    var id: String { platform }
    var platform: String
    var displayName: String
    var category: String
    var symbolName: String
    var unit: String
}
