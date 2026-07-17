import Foundation

struct LocalAPIRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    var origin: String? {
        headers["origin"]
    }
}

enum LocalAPIRequestReadResult {
    case incomplete
    case complete(LocalAPIRequest)
    case malformed
    case tooLarge
}

struct LocalAPIResponse {
    var statusCode: Int
    var reason: String
    var body: Data
    var headers: [String: String]

    static func json(
        _ body: Data,
        statusCode: Int = 200,
        reason: String = "OK",
        headers: [String: String] = [:]
    ) -> LocalAPIResponse {
        LocalAPIResponse(statusCode: statusCode, reason: reason, body: body, headers: headers)
    }

    static func empty(
        statusCode: Int,
        reason: String,
        headers: [String: String] = [:]
    ) -> LocalAPIResponse {
        LocalAPIResponse(statusCode: statusCode, reason: reason, body: Data(), headers: headers)
    }

    static func error(
        _ code: String,
        statusCode: Int,
        reason: String,
        headers: [String: String] = [:]
    ) -> LocalAPIResponse {
        let payload = ["error": code]
        let body = (try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data(#"{"error":"unknown"}"#.utf8)
        return LocalAPIResponse(statusCode: statusCode, reason: reason, body: body, headers: headers)
    }
}

enum LocalAPIHTTPCodec {
    private static let maximumHeaderBytes = 32 * 1024
    private static let maximumBodyBytes = 1_024 * 1_024

    static func readRequest(from data: Data) -> LocalAPIRequestReadResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else {
            return data.count > maximumHeaderBytes ? .tooLarge : .incomplete
        }
        let headerData = data[..<range.lowerBound]
        guard headerData.count <= maximumHeaderBytes,
              let headerText = String(data: headerData, encoding: .utf8) else {
            return .malformed
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return .malformed }
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              ["HTTP/1.0", "HTTP/1.1"].contains(parts[2]),
              parts[1].hasPrefix("/") else {
            return .malformed
        }

        var path = parts[1]
        if let queryStart = path.firstIndex(of: "?") {
            path = String(path[..<queryStart])
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard line.isEmpty == false, let separator = line.firstIndex(of: ":") else {
                return .malformed
            }
            let name = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false, headers[name] == nil else { return .malformed }
            headers[name] = value
        }

        guard headers["transfer-encoding"] == nil else { return .malformed }
        let declaredBodyLength: Int
        if let contentLength = headers["content-length"] {
            guard contentLength.isEmpty == false,
                  contentLength.allSatisfy({ $0.isNumber }),
                  let parsedLength = Int(contentLength),
                  parsedLength <= maximumBodyBytes else {
                return .tooLarge
            }
            declaredBodyLength = parsedLength
        } else {
            declaredBodyLength = 0
        }

        let body = Data(data[range.upperBound...])
        guard body.count <= declaredBodyLength else { return .malformed }
        guard body.count == declaredBodyLength else { return .incomplete }

        return .complete(LocalAPIRequest(
            method: parts[0].uppercased(),
            path: path,
            headers: headers,
            body: body
        ))
    }

    static func responseData(response: LocalAPIResponse, request: LocalAPIRequest?) -> Data {
        var headers: [String: String] = [
            "Content-Length": "\(response.body.count)",
            "Connection": "close"
        ]
        if response.body.isEmpty == false {
            headers["Content-Type"] = "application/json; charset=utf-8"
        }
        response.headers.forEach { headers[$0.key] = $0.value }

        if let origin = request?.origin, isAllowedOrigin(origin) {
            headers["Access-Control-Allow-Origin"] = origin
            headers["Vary"] = "Origin"
        }

        var headerLines = ["HTTP/1.1 \(response.statusCode) \(response.reason)"]
        headerLines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        headerLines.append("")
        headerLines.append("")

        var data = Data(headerLines.joined(separator: "\r\n").utf8)
        data.append(response.body)
        return data
    }

    static func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin, origin.isEmpty == false else { return true }
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return false
        }
        return (scheme == "http" || scheme == "https")
            && ["localhost", "127.0.0.1", "::1"].contains(host)
    }
}
