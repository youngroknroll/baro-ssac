import XCTest
@testable import BaroSsacCore

internal final class AppsPresenterTests: XCTestCase {
	let now = epoch.addingTimeInterval(days(1000))
	let slackPath = "/Applications/Slack.app"

	private var slack: AppItem {
		AppItem(
			app: InstalledApp(
				path: slackPath,
				name: "Slack",
				bundleID: "com.tinyspeck.slackmacgap",
				sizeBytes: 100,
				lastUsedAt: nil
			),
			leftovers: [
				Leftover(path: "/u/Library/Containers/com.tinyspeck.slackmacgap", sizeBytes: 40, match: .bundleID),
				Leftover(path: "/u/Library/Application Support/Slack", sizeBytes: 300, match: .appName),
			],
			suggestions: [.stale(since: now.addingTimeInterval(-days(400)))],
			protectedReason: nil
		)
	}

	private var safari: AppItem {
		AppItem(
			app: InstalledApp(
				path: "/Applications/Safari.app",
				name: "Safari",
				bundleID: "com.apple.Safari",
				sizeBytes: 900,
				lastUsedAt: nil
			),
			leftovers: [],
			suggestions: [],
			protectedReason: "macOS 기본 앱"
		)
	}

	private func loaded(_ items: [AppItem]) -> AppsPresenter {
		var p = AppsPresenter(home: "/u")
		p.load(items)
		return p
	}

	func testNotLoadedUntilFirstLoad() {
		var p = AppsPresenter(home: "/u")
		XCTAssertFalse(p.isLoaded)

		p.load([])

		XCTAssertTrue(p.isLoaded)
	}

	/// 번들 ID 로 찾은 파일은 그 앱의 것이 확실해 기본으로 고르고, 이름으로 찾은 파일은 사용자가 확인하게 둔다.
	func testLeftoversFoundByBundleIDArePreselectedButNameMatchesAreNot() {
		let p = loaded([slack])

		let rows = p.leftoverRows(for: slackPath)
		XCTAssertEqual(rows.map(\.isSelected), [true, false])
		XCTAssertEqual(rows.map(\.display), [
			"~/Library/Containers/com.tinyspeck.slackmacgap",
			"~/Library/Application Support/Slack",
		])
	}

	func testUninstallRequestsIncludeTheAppWithBundleIDAndSelectedLeftovers() {
		var p = loaded([slack])
		p.setLeftover("/u/Library/Application Support/Slack", of: slackPath, true)

		XCTAssertEqual(p.uninstallRequests(for: slackPath), [
			TrashRequest(path: slackPath, sizeBytes: 100, bundleID: "com.tinyspeck.slackmacgap"),
			TrashRequest(path: "/u/Library/Containers/com.tinyspeck.slackmacgap", sizeBytes: 40),
			TrashRequest(path: "/u/Library/Application Support/Slack", sizeBytes: 300),
		])
		XCTAssertEqual(p.uninstallBytes(for: slackPath), 440)
	}

	func testUncheckingALeftoverRemovesItFromTheRequest() {
		var p = loaded([slack])
		p.setLeftover("/u/Library/Containers/com.tinyspeck.slackmacgap", of: slackPath, false)

		XCTAssertEqual(p.uninstallRequests(for: slackPath).map(\.path), [slackPath])
	}

	func testProtectedAppsProduceNoRequests() {
		let p = loaded([safari])

		XCTAssertEqual(p.uninstallRequests(for: "/Applications/Safari.app"), [])
	}

	func testRowsShowTotalsReasonsAndSuggestedFilter() {
		let p = loaded([safari, slack])

		let all = p.rows(mode: .all, now: now)
		XCTAssertEqual(all.map(\.name), ["Safari", "Slack"])
		XCTAssertEqual(all.last?.totalBytes, 440)
		XCTAssertEqual(all.last?.leftoverCount, 2)
		XCTAssertEqual(all.last?.reasons, ["1년 넘게 안 열었음"])
		XCTAssertEqual(p.rows(mode: .suggested, now: now).map(\.name), ["Slack"])
		XCTAssertEqual(p.totalBytes, 900 + 440)
	}
}
