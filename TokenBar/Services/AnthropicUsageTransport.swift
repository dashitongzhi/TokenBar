import Foundation

struct AnthropicUsageTransport {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func paginatedRequest<T: AnthropicPageResponse>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem],
        adminKey: String
    ) async throws -> T {
        var items = queryItems
        var response = try await request(type, path: path, queryItems: items, adminKey: adminKey)
        var pagesSeen = 1

        while response.hasMore == true, let nextPage = response.nextPage, nextPage.isEmpty == false, pagesSeen < 20 {
            items.removeAll { $0.name == "page" }
            items.append(URLQueryItem(name: "page", value: nextPage))
            let nextResponse = try await request(type, path: path, queryItems: items, adminKey: adminKey)
            response.data.append(contentsOf: nextResponse.data)
            response.hasMore = nextResponse.hasMore
            response.nextPage = nextResponse.nextPage
            pagesSeen += 1
        }

        return response
    }

    private func request<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem],
        adminKey: String
    ) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.anthropic.com"
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw AnthropicUsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicUsageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicUsageError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeAPIDate)
        return try decoder.decode(type, from: data)
    }

    private nonisolated static func decodeAPIDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let internetDateFormatter = ISO8601DateFormatter()
        internetDateFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetDateFormatter.date(from: value) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Anthropic date: \(value)")
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Anthropic returned an error without a JSON message."
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = object["message"] as? String {
            return message
        }
        return "Anthropic returned an error without a JSON message."
    }
}

enum AnthropicUsageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Anthropic usage refresh failed: invalid endpoint URL."
        case .invalidResponse:
            "Anthropic usage refresh failed: invalid HTTP response."
        case .httpStatus(let status, let message):
            "Anthropic usage refresh failed with HTTP \(status): \(message)"
        }
    }
}
