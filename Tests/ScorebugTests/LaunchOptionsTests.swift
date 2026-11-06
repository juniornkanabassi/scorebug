import XCTest
@testable import Scorebug

final class LaunchOptionsTests: XCTestCase {
    func testAgentLaunchFlagsStayInvisible() {
        XCTAssertTrue(LaunchOptions.parse(["--agent-screen"]).invisible)
        XCTAssertTrue(LaunchOptions.parse(["--screen", "Retired agent display"]).invisible)
        XCTAssertFalse(LaunchOptions.parse([]).invisible)
    }
}
