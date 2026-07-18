import Foundation

@main
struct PolicyContractVerifierMain {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: verify_policy_contract <fixture-path>\n", stderr)
            exit(2)
        }

        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let result = try PolicyContractFixtureVerifier.verify(fixtureURL: fixtureURL)
        guard result.failures.isEmpty else {
            result.failures.forEach { fputs("\($0)\n", stderr) }
            exit(1)
        }

        print("Verified \(result.verifiedCases) shared policy contract decisions in Swift.")
    }
}
