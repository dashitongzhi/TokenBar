import XCTest
@testable import TokenBar

final class PolicyContractTests: XCTestCase {
    func testSwiftPolicyEngineMatchesSharedRubyContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot.appendingPathComponent("script/fixtures/policy_contract.json")

        let result = try PolicyContractFixtureVerifier.verify(fixtureURL: fixtureURL)

        XCTAssertEqual(result.verifiedCases, 20)
        XCTAssertTrue(result.failures.isEmpty, result.failures.joined(separator: "\n"))
    }
}
