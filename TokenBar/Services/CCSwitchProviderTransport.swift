import Foundation

struct CCSwitchProviderTransport {
    private let session: URLSession
    private let miniMaxClient: MiniMaxQuotaClient

    init(session: URLSession = .shared) {
        self.session = session
        miniMaxClient = MiniMaxQuotaClient(session: session)
    }

    func deepSeekBalance(from providers: [CCSwitchProviderRecord]) async -> DeepSeekBalance? {
        guard let apiKey = providers
            .compactMap({ record -> String? in
                guard CCSwitchProviderNormalizer.normalize(record: record) == .deepSeek,
                      Self.hasOfficialBaseURL(record, allowedHosts: ["api.deepseek.com"]) else { return nil }
                return record.apiKey(forProviderID: CCSwitchKnownProvider.deepSeek.providerID)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            })
            .first(where: { $0.isEmpty == false }),
            let url = URL(string: "https://api.deepseek.com/user/balance")
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
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
                  Self.hasOfficialBaseURL(record, allowedHosts: ["api.minimaxi.com", "api.minimax.io"]),
                  let apiKey = record.apiKey(forProviderID: CCSwitchKnownProvider.miniMax.providerID)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
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
        do {
            let decoded = try await miniMaxClient.fetch(apiKey: apiKey)
            guard decoded.baseResp?.statusCode ?? 0 == 0 else { return nil }
            return decoded.modelRemains.map {
                $0.quotaWindow(
                    providerID: CCSwitchKnownProvider.miniMax.providerID,
                    providerDisplayName: record.name.isEmpty
                        ? CCSwitchKnownProvider.miniMax.displayName
                        : record.name
                )
            }
        } catch {
            return nil
        }
    }

    private static func hasOfficialBaseURL(_ record: CCSwitchProviderRecord, allowedHosts: Set<String>) -> Bool {
        guard let rawURL = record.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil else {
            return false
        }
        return allowedHosts.contains(host)
    }
}
