import XCTest
@testable import BaroSsacCore

internal final class ScanUseCaseTests: XCTestCase {
	let now = epoch.addingTimeInterval(days(100))
	let caches = CleanupRule(name: "app-caches", root: "/u/Library/Caches", risk: .low)

	private func scan(_ fs: FileSystemPort, _ rules: [CleanupRule]) -> ScanReport {
		ScanUseCase(fs: fs, clock: FixedClock(fixed: now)).execute(rules)
	}

	func testSumsSizesOfPathsMatchingRule() {
		let fs = InMemoryFileSystem([
			"/u/Library/Caches/a/x.bin": 300,
			"/u/Library/Caches/b/y.bin": 200,
			"/u/Documents/keep.txt": 999,
		])

		let report = scan(fs, [caches])

		XCTAssertEqual(report.totalBytes, 500)
	}

	func testEachDirectChildOfRootBecomesOneItem() {
		let fs = InMemoryFileSystem([
			"/u/Library/Caches/com.app.a/1": 100,
			"/u/Library/Caches/com.app.a/2": 50,
			"/u/Library/Caches/com.app.b/1": 10,
		])

		let report = scan(fs, [caches])

		XCTAssertEqual(report.items.map { $0.path }, ["/u/Library/Caches/com.app.a", "/u/Library/Caches/com.app.b"])
		XCTAssertEqual(report.items.map { $0.sizeBytes }, [150, 10])
		XCTAssertTrue(report.items.allSatisfy { $0.ruleName == "app-caches" && $0.risk == .low })
	}

	func testMissingRootIsReportedAsSkippedNotError() {
		let report = scan(InMemoryFileSystem([:]), [caches])

		XCTAssertTrue(report.items.isEmpty)
		XCTAssertEqual(report.skipped, [SkippedItem(path: "/u/Library/Caches", reason: .notFound)])
	}

	func testSymlinksAreNotFollowed() {
		let fs = InMemoryFileSystem(
			["/u/Library/Caches/real/f": 10],
			symlinks: ["/u/Library/Caches/link-to-documents"]
		)

		let report = scan(fs, [caches])

		XCTAssertEqual(report.items.map { $0.path }, ["/u/Library/Caches/real"])
		XCTAssertEqual(report.skipped.first?.reason, .symlink)
	}

	func testEntriesNewerThanMinAgeAreExcluded() {
		let rule = CleanupRule(name: "logs", root: "/u/Library/Logs", risk: .low, minAgeDays: 7)
		let fs = InMemoryFileSystem(
			["/u/Library/Logs/old.log": 10, "/u/Library/Logs/fresh.log": 20],
			mtimes: [
				"/u/Library/Logs/old.log": now.addingTimeInterval(-days(30)),
				"/u/Library/Logs/fresh.log": now.addingTimeInterval(-days(1)),
			]
		)

		let report = scan(fs, [rule])

		XCTAssertEqual(report.items.map { $0.path }, ["/u/Library/Logs/old.log"])
		XCTAssertEqual(report.skipped.first?.reason, .tooRecent)
	}

	func testPermissionDeniedIsReportedAsSkipped() {
		let fs = InMemoryFileSystem(
			["/u/Library/Caches/ok/f": 5, "/u/Library/Caches/locked/f": 7],
			denied: ["/u/Library/Caches/locked"]
		)

		let report = scan(fs, [caches])

		XCTAssertEqual(report.items.map { $0.path }, ["/u/Library/Caches/ok"])
		XCTAssertEqual(report.skipped.first?.reason, .permissionDenied)
	}

	func testPermissionDeniedOnRootSkipsWholeRule() {
		let fs = InMemoryFileSystem(["/u/Library/Caches/a/f": 5], denied: ["/u/Library/Caches"])

		let report = scan(fs, [caches])

		XCTAssertTrue(report.items.isEmpty)
		XCTAssertEqual(report.skipped.first?.reason, .permissionDenied)
	}

	func testReportGroupsTotalsByRule() {
		let logs = CleanupRule(name: "logs", root: "/u/Library/Logs", risk: .low)
		let fs = InMemoryFileSystem([
			"/u/Library/Caches/a/f": 100,
			"/u/Library/Logs/b.log": 30,
		])

		let report = scan(fs, [caches, logs])

		XCTAssertEqual(report.bytesByRule(), ["app-caches": 100, "logs": 30])
	}

	func testLargestReturnsItemsSortedBySizeDescending() {
		let fs = InMemoryFileSystem([
			"/u/Library/Caches/small/f": 1,
			"/u/Library/Caches/big/f": 999,
		])

		let report = scan(fs, [caches])

		XCTAssertEqual(report.largest(1).map { $0.path }, ["/u/Library/Caches/big"])
	}

	/// 앱 로그 폴더에 오늘 로그가 하나 있어도, 오래된 로그 파일들은 잡아야 한다.
	func testFilesGranularityAppliesAgePerFileNotPerFolder() {
		let rule = CleanupRule(name: "logs", root: "/u/Library/Logs", risk: .low, minAgeDays: 7, granularity: .files)
		let fs = InMemoryFileSystem(
			[
				"/u/Library/Logs/App/old.log": 10,
				"/u/Library/Logs/App/deeper/older.log": 5,
				"/u/Library/Logs/App/today.log": 20,
			],
			mtimes: [
				"/u/Library/Logs/App/old.log": now.addingTimeInterval(-days(30)),
				"/u/Library/Logs/App/deeper/older.log": now.addingTimeInterval(-days(60)),
				"/u/Library/Logs/App/today.log": now,
			]
		)

		let report = scan(fs, [rule])

		XCTAssertEqual(report.items.map { $0.path }.sorted(), [
			"/u/Library/Logs/App/deeper/older.log",
			"/u/Library/Logs/App/old.log",
		])
		XCTAssertEqual(report.totalBytes, 15)
		XCTAssertEqual(report.skipped.map { $0.path }, ["/u/Library/Logs/App/today.log"])
	}

	func testRootGranularityYieldsTheRootAsASingleItem() {
		let rule = CleanupRule(name: "npm-cache", root: "/u/.npm/_cacache", risk: .low, granularity: .root)
		let fs = InMemoryFileSystem(["/u/.npm/_cacache/index-v5/a": 10, "/u/.npm/_cacache/content-v2/b": 30])

		let report = scan(fs, [rule])

		XCTAssertEqual(report.items.map { $0.path }, ["/u/.npm/_cacache"])
		XCTAssertEqual(report.items.map { $0.sizeBytes }, [40])
	}

	func testExcludedChildrenAreSkippedWithReason() {
		let rule = CleanupRule(
			name: "app-caches", root: "/u/Library/Caches", risk: .low,
			exclude: ["com.apple.bird", "CloudKit*"]
		)
		let fs = InMemoryFileSystem([
			"/u/Library/Caches/com.apple.bird/x": 1,
			"/u/Library/Caches/CloudKitMetadata/x": 1,
			"/u/Library/Caches/com.spotify.client/x": 1,
		])

		let report = scan(fs, [rule])

		XCTAssertEqual(report.items.map { $0.path }, ["/u/Library/Caches/com.spotify.client"])
		XCTAssertEqual(Set(report.skipped.map { $0.reason }), [.excluded])
	}

	func testProgressCallbackReportsEachRuleAsItFinishes() {
		let logs = CleanupRule(name: "logs", root: "/u/Library/Logs", risk: .low)
		let fs = InMemoryFileSystem(["/u/Library/Caches/a/f": 1])
		var seen: [String] = []

		_ = ScanUseCase(fs: fs, clock: FixedClock(fixed: now)).execute([caches, logs]) { done, total, rule in
			seen.append("\(done)/\(total) \(rule.name)")
		}

		XCTAssertEqual(seen, ["1/2 app-caches", "2/2 logs"])
	}
}
