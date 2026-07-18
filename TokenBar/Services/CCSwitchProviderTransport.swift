import Foundation

struct CCSwitchProviderTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func deepSeekBalance(from providers: [CCSwitchProviderRecord]) async -> DeepSeekBalance? {
        guard let apiKey = providers
            .compactMap({ record -> String? in
                guard CCSwitchProviderNormalizer.normalize(record: record) == .deepSeek else { return nil }
                return record.apiKey
            })
            .first(where: { $0.isEmpty == false }),
            let url = URL(string: "https://api.deepseek.com/user/balance")
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            guard let primary = decoded.balanceInfos.first else { return nil }
            return DeepSeekBalance(
                isAvailable: decoded.isAvailable,
                currency: primary.currency,
                totalBalance: Double(primary.totalBalance) ?? 0,
                toppedUpBalance: Double(primary.toppedUpBalance) ?? 0,
                grantedBalance: Double(primary.grantedBalance) ?? 0
            )
        } catch {
            return nil
        }
    }

    func liveQuotaWindows(from providers: [CCSwitchProviderRecord]) async -> [CCSwitchKnownProvider: [CCSwitchQuotaWindow]] {
        var windowsByProvider: [CCSwitchKnownProvider: [CCSwitchQuotaWindow]] = [:]
        var seenKeys = Set<String>()

        for record in providers {
            guard CCSwitchProviderNormalizer.normalize(record: record) == .miniMax,
                  let apiKey = record.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  apiKey.isEmpty == false,
                  seenKeys.insert(apiKey).inserted
            else {
                continue
            }

            guard let windows = await miniMaxQuotaWindows(apiKey: apiKey, record: record), windows.isEmpty == false else {
                continue
            }
            windowsByProvider[.miniMax, default: []].append(contentsOf: windows)
        }

        return windowsByProvider
    }

    private func miniMaxQuotaWindows(apiKey: String, record: CCSwitchProviderRecord) async -> [CCSwitchQuotaWindow]? {
        guard let url = URL(string: "https://api.minimaxi.com/v1/token_plan/remains") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenBar", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(CCSwitchMiniMaxQuotaResponse.self, from: data)
            guard decoded.baseResp?.statusCode ?? 0 == 0 else { return nil }
            return decoded.modelRemains.map { item in
                CCSwitchQuotaWindow(
                    providerID: CCSwitchKnownProvider.miniMax.providerID,
                    providerDisplayName: record.name.isEmpty ? CCSwitchKnownProvider.miniMax.displayName : record.name,
                    modelName: item.modelName,
                    intervalUsedCount: item.currentIntervalUsageCount,
                    intervalTotalCount: item.currentIntervalTotalCount,
                    intervalUsedPercent: Self.usedPercent(
                        used: item.currentIntervalUsageCount,
                        total: item.currentIntervalTotalCount,
                        remainingPercent: item.currentIntervalRemainingPercent
                    ),
                    intervalRemainingPercent: item.currentIntervalRemainingPercent,
                    intervalStartAt: Self.date(milliseconds: item.startTime),
                    intervalResetAt: Self.date(milliseconds: item.endTime),
                    weeklyUsedCount: item.currentWeeklyUsageCount,
                    weeklyTotalCount: item.currentWeeklyTotalCount,
                    weeklyUsedPercent: Self.usedPercent(
                        used: item.currentWeeklyUsageCount,
                        total: item.currentWeeklyTotalCount,
                        remainingPercent: item.currentWeeklyRemainingPercent
                    ),
                    weeklyRemainingPercent: item.currentWeeklyRemainingPercent,
                    weeklyStartAt: Self.date(milliseconds: item.weeklyStartTime),
                    weeklyResetAt: Self.date(milliseconds: item.weeklyEndTime)
                )
            }
        } catch {
            return nil
        }
    }

    private static func usedPercent(used: Double, total: Double, remainingPercent: Double?) -> Double {
        if total > 0 {
            return min(max((used / total) * 100, 0), 100)
        }
        if let remainingPercent {
            return min(max(100 - remainingPercent, 0), 100)
        }
        return 0
    }

    private static func date(milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
