import XCTest
@testable import BaroSsacCore

internal final class CleanUseCaseTests: XCTestCase {
	let caches = CleanupRule(name: "app-caches", root: "/u/Library/Caches", risk: .low)
	let backups = CleanupRule(
		name: "ios-backups",
		root: "/u/Library/Application Support/MobileSync/Backup",
		risk: .high
	)
	let npm = CleanupRule(name: "npm-cache", root: "/u/.npm/_cacache", risk: .low, granularity: .root)
	var rules: [CleanupRule] { [caches, backups, npm] }

	private func item(_ path: String, _ size: Int64 = 100, rule: CleanupRule? = nil) -> ScanItem {
		let r = rule ?? caches
		return ScanItem(ruleName: r.name, path: path, sizeBytes: size, risk: r.risk)
	}

	private func clean(
		_ trash: SpyTrash,
		_ items: [ScanItem],
		fs: FileSystemPort? = nil,
		dryRun: Bool = true,
		confirmedPaths: Set<String> = []
	) -> CleanResult {
		// 기본 fs: 요청된 항목이 모두 실제로 존재하는 상태
		let fs: FileSystemPort = fs
			?? InMemoryFileSystem(Dictionary(uniqueKeysWithValues: items.map { ($0.path + "/f", $0.sizeBytes) }))
		return CleanUseCase(trash: trash, fs: fs, rules: rules)
			.execute(items, dryRun: dryRun, confirmedPaths: confirmedPaths)
	}

	func testDryRunIsTheDefaultAndNeverTouchesTrash() {
		let trash = SpyTrash()

		let result = clean(trash, [item("/u/Library/Caches/a")])

		XCTAssertEqual(trash.trashed, [])
		XCTAssertTrue(result.dryRun)
		XCTAssertEqual(result.entries.first?.outcome, .wouldTrash)
		XCTAssertEqual(result.freedBytes, 100)
	}

	func testRealRunMovesItemsToTrash() {
		let trash = SpyTrash()

		let result = clean(trash, [item("/u/Library/Caches/a", 100), item("/u/Library/Caches/b", 50)], dryRun: false)

		XCTAssertEqual(trash.trashed, ["/u/Library/Caches/a", "/u/Library/Caches/b"])
		XCTAssertEqual(result.freedBytes, 150)
	}

	func testPathOutsideAnyRuleIsRejectedEvenIfRequested() {
		let trash = SpyTrash()

		let result = clean(trash, [item("/u/Documents/thesis")], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .rejectedOutsideRules)
		XCTAssertEqual(result.freedBytes, 0)
	}

	func testPathTraversalCannotEscapeRuleRoot() {
		let trash = SpyTrash()

		let result = clean(trash, [item("/u/Library/Caches/../../Documents")], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .rejectedOutsideRules)
	}

	func testRuleRootItselfCannotBeTrashedForChildrenGranularity() {
		let trash = SpyTrash()

		let result = clean(trash, [item("/u/Library/Caches")], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .rejectedOutsideRules)
	}

	func testRuleRootCanBeTrashedOnlyForRootGranularity() {
		let trash = SpyTrash()

		_ = clean(trash, [item("/u/.npm/_cacache", rule: npm)], dryRun: false)

		XCTAssertEqual(trash.trashed, ["/u/.npm/_cacache"])
	}

	/// 캐시 DB의 일부만 지워 일관성을 깨는 것을 막는다.
	func testRootGranularityRejectsPartialChildren() {
		let trash = SpyTrash()

		let result = clean(trash, [item("/u/.npm/_cacache/index-v5", rule: npm)], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .rejectedOutsideRules)
	}

	/// 다른 규칙 이름을 붙여 위험도를 낮춰 우회하는 것을 막는다.
	func testItemMustBelongToTheRuleItClaims() {
		let trash = SpyTrash()
		let forged = ScanItem(
			ruleName: "app-caches",
			path: "/u/Library/Application Support/MobileSync/Backup/x",
			sizeBytes: 1,
			risk: .low
		)

		let result = clean(trash, [forged], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .rejectedOutsideRules)
	}

	func testHighRiskRequiresExplicitPerItemConfirmation() {
		let trash = SpyTrash()
		let a = item("/u/Library/Application Support/MobileSync/Backup/a", rule: backups)
		let b = item("/u/Library/Application Support/MobileSync/Backup/b", rule: backups)

		let result = clean(trash, [a, b], dryRun: false, confirmedPaths: [a.path])

		XCTAssertEqual(trash.trashed, [a.path])
		XCTAssertEqual(result.entries.map { $0.outcome }, [.trashed, .needsConfirmation])
	}

	func testItemThatVanishedSinceScanIsReportedStale() {
		let trash = SpyTrash()
		let fs = InMemoryFileSystem(["/u/Library/Caches/still-here/f": 1])

		let result = clean(
			trash,
			[item("/u/Library/Caches/gone"), item("/u/Library/Caches/still-here")],
			fs: fs,
			dryRun: false
		)

		XCTAssertEqual(trash.trashed, ["/u/Library/Caches/still-here"])
		XCTAssertEqual(result.entries.first?.outcome, .stale)
		XCTAssertEqual(result.freedBytes, 100)
	}

	func testItemThatBecameASymlinkSinceScanIsNotTrashed() {
		let trash = SpyTrash()
		let fs = InMemoryFileSystem([:], symlinks: ["/u/Library/Caches/a"])

		let result = clean(trash, [item("/u/Library/Caches/a")], fs: fs, dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .stale)
	}

	/// 실행 중인 앱의 캐시를 지우면 앱이 오작동할 수 있으므로, 사용자가 골랐어도 보내지 않는다.
	func testItemOfAppRunningAtCleanTimeIsNotTrashed() {
		let trash = SpyTrash()
		let items = [item("/u/Library/Caches/com.spotify.client"), item("/u/Library/Caches/Homebrew", 40)]
		let fs = InMemoryFileSystem(Dictionary(uniqueKeysWithValues: items.map { ($0.path + "/f", $0.sizeBytes) }))
		let useCase = CleanUseCase(
			trash: trash, fs: fs, rules: rules,
			runningApps: FakeRunningApps(ids: ["com.spotify.client"])
		)

		let result = useCase.execute(items, dryRun: false)

		XCTAssertEqual(trash.trashed, ["/u/Library/Caches/Homebrew"])
		XCTAssertEqual(result.entries.map { $0.outcome }, [.inUse, .trashed])
		XCTAssertEqual(result.freedBytes, 40)
	}

	/// 스캔 때는 실행 중이었어도 정리 시점에 앱을 껐다면 보낸다. 판단 기준은 '지금'이다.
	func testItemOfAppThatQuitSinceScanIsTrashed() {
		let trash = SpyTrash()
		let scanned = ScanItem(
			ruleName: "app-caches",
			path: "/u/Library/Caches/com.spotify.client",
			sizeBytes: 100,
			risk: .low,
			inUseBy: "com.spotify.client"
		)
		let fs = InMemoryFileSystem([scanned.path + "/f": 100])
		let useCase = CleanUseCase(trash: trash, fs: fs, rules: rules, runningApps: FakeRunningApps(ids: []))

		_ = useCase.execute([scanned], dryRun: false)

		XCTAssertEqual(trash.trashed, [scanned.path])
	}

	func testDryRunAlsoReportsInUse() {
		let items = [item("/u/Library/Caches/com.spotify.client")]
		let fs = InMemoryFileSystem([items[0].path + "/f": 100])
		let useCase = CleanUseCase(
			trash: SpyTrash(), fs: fs, rules: rules,
			runningApps: FakeRunningApps(ids: ["com.spotify.client"])
		)

		let result = useCase.execute(items)

		XCTAssertEqual(result.entries.first?.outcome, .inUse)
		XCTAssertEqual(result.freedBytes, 0)
	}

	func testTrashFailureIsRecordedAndOthersContinue() {
		let trash = SpyTrash(failOn: ["/u/Library/Caches/a"])

		let result = clean(trash, [item("/u/Library/Caches/a"), item("/u/Library/Caches/b", 40)], dryRun: false)

		XCTAssertEqual(result.entries.map { $0.outcome }, [.failed, .trashed])
		XCTAssertTrue(result.entries[0].error.contains("cannot trash"))
		XCTAssertEqual(result.freedBytes, 40)
	}
}
