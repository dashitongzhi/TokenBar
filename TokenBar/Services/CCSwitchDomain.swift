import Foundation

nonisolated enum CCSwitchKnownProvider: Hashable {
    case miniMax
    case deepSeek
    case xiaomiMiMo
    case ccSwitchCodex
    case glm
    case openAI
    case anthropic

    var providerID: String {
        switch self {
        case .miniMax: "minimax"
        case .deepSeek: "deepseek"
        case .xiaomiMiMo: "xiaomi-mimo"
        case .ccSwitchCodex: "ccswitch-codex"
        case .glm: "glm"
        case .openAI: "openai"
        case .anthropic: "anthropic"
        }
    }

    var displayName: String {
        switch self {
        case .miniMax: "MiniMax"
        case .deepSeek: "DeepSeek"
        case .xiaomiMiMo: "Xiaomi MiMo"
        case .ccSwitchCodex: "CC Switch Codex"
        case .glm: "GLM"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    var symbolName: String {
        switch self {
        case .miniMax: "bolt.horizontal.circle.fill"
        case .deepSeek: "scope"
        case .xiaomiMiMo: "waveform.path.ecg"
        case .ccSwitchCodex: "terminal.fill"
        case .glm: "sparkle.magnifyingglass"
        case .openAI: "sparkles"
        case .anthropic: "text.bubble.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .miniMax: 0
        case .deepSeek: 1
        case .xiaomiMiMo: 2
        case .ccSwitchCodex: 3
        case .glm: 4
        case .openAI: 5
        case .anthropic: 6
        }
    }
}

struct CCSwitchAggregate {
    var provider: CCSwitchKnownProvider
    var tokenTotalToday = 0.0
    var tokenTotalMonth = 0.0
    var requestCountToday = 0
    var requestCountMonth = 0
    var spendToday = 0.0
    var spendMonth = 0.0
    var models: [String] = []
    private var dailyTokens: [String: Double] = [:]

    init(provider: CCSwitchKnownProvider) {
        self.provider = provider
    }

    mutating func add(rollup: CCSwitchDailyRollup, isToday: Bool) {
        tokenTotalMonth += rollup.tokenTotal
        requestCountMonth += rollup.requestCount
        spendMonth += rollup.totalCostUSD
        dailyTokens[rollup.date, default: 0] += rollup.tokenTotal
        if models.contains(rollup.model) == false, rollup.model.isEmpty == false {
            models.append(rollup.model)
        }
        if isToday {
            tokenTotalToday += rollup.tokenTotal
            requestCountToday += rollup.requestCount
            spendToday += rollup.totalCostUSD
        }
    }

    func history() -> [UsagePoint] {
        dailyTokens.keys.sorted().compactMap { day in
            guard let date = Self.dateFormatter.date(from: day),
                  let value = dailyTokens[day] else {
                return nil
            }
            return UsagePoint(timestamp: date, value: value)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
