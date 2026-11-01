import XCTest
@testable import BaroSsacCore

internal final class AppScanUseCaseTests: XCTestCase {
	let home = "/u"
	let now = epoch.addingTimeInterval(days(1000))

	private func app(
		_ name: String,
		_ bundleID: String?,
		size: Int64 = 100,
		lastUsed: Date? = nil
	) -> InstalledApp {
		InstalledApp(
			path: "/Applications/\(name).app",
			name: name,
			bundleID: bundleID,
			sizeBytes: size,
			lastUsedAt: lastUsed
		)
	}

	private func scan(_ apps: [InstalledApp], files: [String: Int64] = [:]) -> [AppItem] {
		AppScanUseCase(
			catalog: FakeCatalog(apps: apps),
			fs: InMemoryFileSystem(files),
			clock: FixedClock(fixed: now),
			home: home
		).execute()
	}

	// MARK: 관련 파일 후보

	func testLeftoverCandidatesByBundleIDAndByName() {
		let candidates = AppLeftovers.candidates(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", home: home)
		let byBundle = candidates.filter { $0.match == .bundleID }.map(\.path)
		let byName = candidates.filter { $0.match == .appName }.map(\.path)

		XCTAssertTrue(byBundle.contains("/u/Library/Application Support/com.tinyspeck.slackmacgap"))
		XCTAssertTrue(byBundle.contains("/u/Library/Preferences/com.tinyspeck.slackmacgap.plist"))
		XCTAssertTrue(byBundle.contains("/u/Library/Containers/com.tinyspeck.slackmacgap"))
		XCTAssertTrue(byName.contains("/u/Library/Application Support/Slack"))
	}

	/// 이름이 비었거나 경로를 벗어날 수 있는 이름이면 이름으로는 찾지 않는다.
	func testNoNameCandidatesForUnsafeNames() {
		for unsafe in ["", ".", "..", "a/b"] {
			let candidates = AppLeftovers.candidates(bundleID: nil, appName: unsafe, home: home)
			XCTAssertTrue(candidates.isEmpty, unsafe)
		}
	}

	func testEveryCandidateIsInsideTheAllowedRoots() {
		let roots = AppLeftovers.allowedRoots(home: home)
		let candidates = AppLeftovers.candidates(bundleID: "com.example.app", appName: "Example", home: home)

		XCTAssertFalse(candidates.isEmpty)
		for c in candidates {
			XCTAssertTrue(roots.contains { PathUtil.isStrictlyInside(c.path, root: $0) }, c.path)
		}
	}

	func testCandidatesAreUniqueAndBundleIDMatchWins() {
		// 번들 ID 와 이름이 같은 앱: 같은 경로가 두 번 나오면 안 된다.
		let candidates = AppLeftovers.candidates(bundleID: "Foo", appName: "Foo", home: home)
		let paths = candidates.map(\.path)

		XCTAssertEqual(paths.count, Set(paths).count)
		XCTAssertEqual(candidates.first { $0.path == "/u/Library/Application Support/Foo" }?.match, .bundleID)
	}

	// MARK: 스캔

	func testOnlyExistingLeftoversAreListedWithTheirSizes() {
		let items = scan(
			[app("Slack", "com.tinyspeck.slackmacgap")],
			files: [
				"/u/Library/Application Support/Slack/storage/a": 300,
				"/u/Library/Preferences/com.tinyspeck.slackmacgap.plist": 2,
			]
		)

		let leftovers = items.first?.leftovers ?? []
		XCTAssertEqual(Set(leftovers.map(\.path)), [
			"/u/Library/Application Support/Slack",
			"/u/Library/Preferences/com.tinyspeck.slackmacgap.plist",
		])
		XCTAssertEqual(items.first?.totalBytes, 100 + 300 + 2)
	}

	func testBuiltInAppsAreProtectedWithoutLeftovers() {
		let items = scan(
			[app("Safari", "com.apple.Safari")],
			files: ["/u/Library/Caches/com.apple.Safari/x": 10]
		)

		XCTAssertNotNil(items.first?.protectedReason)
		XCTAssertEqual(items.first?.leftovers, [])
	}

	func testAppNotOpenedForAYearIsStaleAndUnknownUsageIsNot() {
		let lastUsed = now.addingTimeInterval(-days(500))
		let items = scan([app("Old", "com.example.old", lastUsed: lastUsed), app("Unknown", "com.example.unknown")])
		let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.app.name, $0.suggestions) })

		XCTAssertEqual(byName["Old"], [.stale(since: lastUsed)])
		XCTAssertEqual(byName["Unknown"], [])
	}

	func testAppsAreSortedByTotalSizeIncludingLeftovers() {
		let items = scan(
			[app("Small", "com.example.small", size: 50), app("Big", "com.example.big", size: 10)],
			files: ["/u/Library/Containers/com.example.big/data": 500]
		)

		XCTAssertEqual(items.map(\.app.name), ["Big", "Small"])
	}
}
