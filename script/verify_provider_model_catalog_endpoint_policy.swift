import Foundation

@main
private enum VerifyProviderModelCatalogEndpointPolicy {
    static func main() throws {
        try expect(
            ProviderModelCatalogEndpointPolicy.validatedBaseURL(providerID: "openai", requestedBaseURL: nil) == "https://api.openai.com/v1",
            "OpenAI should use its official default endpoint."
        )
        try expect(
            ProviderModelCatalogEndpointPolicy.validatedBaseURL(providerID: "openai", requestedBaseURL: " https://api.openai.com/v1 ") == "https://api.openai.com/v1",
            "An official HTTPS endpoint should be accepted after trimming."
        )
        try expect(
            ProviderModelCatalogEndpointPolicy.validatedBaseURL(providerID: "custom", requestedBaseURL: "https://models.example.test/v1") == "https://models.example.test/v1",
            "Custom providers may use a dedicated HTTPS endpoint without inheriting a provider key."
        )

        for value in [
            "http://api.openai.com/v1",
            "https://api.openai.com.evil.test/v1",
            "https://api.openai.com@evil.test/v1",
            "https://api.openai.com:443/v1",
            "https://api.openai.com/v1?relay=evil",
            "https://api.openai.com/v1#relay"
        ] {
            do {
                _ = try ProviderModelCatalogEndpointPolicy.validatedBaseURL(providerID: "openai", requestedBaseURL: value)
                throw VerificationFailure("untrusted endpoint was accepted: \(value)")
            } catch ProviderModelCatalogEndpointError.untrustedBaseURL {
                continue
            }
        }
        print("Verified provider model catalog endpoints reject untrusted credential destinations.")
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw VerificationFailure(message) }
    }
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
