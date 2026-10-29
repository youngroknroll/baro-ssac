import XCTest
@testable import BaroSsacCore

internal final class PresenterTests: XCTestCase {
	let caches = CleanupRule(name: "app-caches", root: "/u/Library/Caches", risk: .low, title: "앱 캐시", description: "앱이 다시 만듦")
	let logs = CleanupRule(name: "user-logs", root: "/u/Library/Logs", risk: .low, title: "오래된 로그")
	let backups = CleanupRule(name: "ios-backups", root: "/u/B", risk: .high, title: "iPhone 백업")
	var rules: [CleanupRule] { [caches, logs, backups] }

	private func report(_ items: ScanItem...) -> ScanReport { ScanReport(items: items) }

	func testFormatSizeIsHumanReadable() {
		XCTAssertEqual(formatSize(0), "0 B")
		XCTAssertEqual(formatSize(900), "900 B")
		XCTAssertEqual(formatSize(1536), "1.5 KB")
		XCTAssertEqual(formatSize(3 * 1024 * 1024), "3.0 MB")
		XCTAssertEqual(formatSize(Int64(2.25 * 1024 * 1024 * 1024)), "2.25 GB")
	}

	func testGroupsItemsByRuleSortedBySizeDescAndHidesEmptyGroups() {
		var p = Presenter(rules: rules)
		p.load(report(
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/small", sizeBytes: 10, risk: .low),
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/big", sizeBytes: 500, risk: .low),
			ScanItem(ruleName: "user-logs", path: "/u/Library/Logs/a.log", sizeBytes: 1000, risk: .low)
		))

		let groups = p.groups()

		XCTAssertEqual(groups.map { $0.name }, ["user-logs", "app-caches"])
		XCTAssertEqual(groups.map { $0.title }, ["오래된 로그", "앱 캐시"])
		XCTAssertEqual(groups.map { $0.sizeBytes }, [1000, 510])
		XCTAssertEqual(groups[1].children.map { $0.label }, ["big", "small"])
		XCTAssertEqual(groups[1].description, "앱이 다시 만듦")
	}

	func testGroupExposesRiskAndTotalForDisplay() {
		var p = Presenter(rules: rules)
		p.load(report(ScanItem(ruleName: "ios-backups", path: "/u/B/x", sizeBytes: 2048, risk: .high)))

		let g = p.groups()[0]

		XCTAssertEqual(g.risk, .high)
		XCTAssertEqual(g.sizeText, "2.0 KB")
		XCTAssertEqual(p.totalText, "2.0 KB")
	}

	func testLowAndMediumGroupsArePreselectedHighIsNot() {
		var p = Presenter(rules: rules)
		p.load(report(
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/a", sizeBytes: 100, risk: .low),
			ScanItem(ruleName: "ios-backups", path: "/u/B/x", sizeBytes: 1000, risk: .high)
		))

		XCTAssertTrue(p.isSelected("/u/Library/Caches/a"))
		XCTAssertFalse(p.isSelected("/u/B/x"))
		XCTAssertEqual(p.selectedBytes, 100)
	}

	func testTogglingAGroupTogglesAllItsChildren() {
		var p = Presenter(rules: rules)
		p.load(report(
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/a", sizeBytes: 100, risk: .low),
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/b", sizeBytes: 50, risk: .low)
		))

		p.setGroupSelected("app-caches", false)
		XCTAssertEqual(p.selectedBytes, 0)

		p.setItemSelected("/u/Library/Caches/b", true)
		XCTAssertEqual(p.selectedBytes, 50)
		XCTAssertEqual(p.groupState("app-caches"), .partial)
	}

	func testSelectedItemsAndHighRiskPathsNeedingConfirmation() {
		var p = Presenter(rules: rules)
		p.load(report(
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/a", sizeBytes: 100, risk: .low),
			ScanItem(ruleName: "ios-backups", path: "/u/B/x", sizeBytes: 1000, risk: .high)
		))
		p.setItemSelected("/u/B/x", true)

		XCTAssertEqual(p.selectedItems().map { $0.path }, ["/u/Library/Caches/a", "/u/B/x"])
		XCTAssertEqual(p.highRiskSelectedPaths(), ["/u/B/x"])
	}

	/// 조각 순서: 종류별(용량순) → 그 외 사용 중 → 여유 공간. 합은 디스크 총 용량.
	func testChartSegmentsFillTheWholeDiskInDisplayOrder() {
		var p = Presenter(rules: rules)
		p.load(report(
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/a", sizeBytes: 100, risk: .low),
			ScanItem(ruleName: "user-logs", path: "/u/Library/Logs/a.log", sizeBytes: 300, risk: .low)
		))
		p.setDisk(DiskUsage(totalBytes: 1000, freeBytes: 200))

		let segs = p.chartSegments()

		XCTAssertEqual(segs.map { $0.key }, ["user-logs", "app-caches", "other", "free"])
		XCTAssertEqual(segs.map { $0.label }, ["오래된 로그", "앱 캐시", "그 외 사용 중", "여유 공간"])
		XCTAssertEqual(segs.map { $0.bytes }, [300, 100, 400, 200])
		XCTAssertEqual(segs.reduce(0) { $0 + $1.bytes }, 1000)
	}

	func testGroupColorsMatchChartSegmentColors() {
		var p = Presenter(rules: rules)
		p.load(report(
			ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/a", sizeBytes: 100, risk: .low),
			ScanItem(ruleName: "user-logs", path: "/u/Library/Logs/a.log", sizeBytes: 300, risk: .low)
		))
		p.setDisk(DiskUsage(totalBytes: 1000, freeBytes: 200))

		let colors = Dictionary(uniqueKeysWithValues: p.chartSegments().map { ($0.key, $0.color) })
		for g in p.groups() {
			XCTAssertEqual(g.color, colors[g.name])
		}
		XCTAssertNotEqual(colors["user-logs"], colors["app-caches"])
	}

	/// APFS 클론 등으로 정리 가능 용량이 사용량보다 크게 잡혀도 차트가 깨지지 않는다.
	func testOtherSegmentNeverGoesNegativeWhenSizesOverstate() {
		var p = Presenter(rules: rules)
		p.load(report(ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/a", sizeBytes: 900, risk: .low)))
		p.setDisk(DiskUsage(totalBytes: 1000, freeBytes: 500))

		let segs = Dictionary(uniqueKeysWithValues: p.chartSegments().map { ($0.key, $0.bytes) })

		XCTAssertEqual(segs["other"], 0)
		XCTAssertEqual(segs["free"], 500)
	}

	func testWithoutDiskInfoChartShowsOnlyCleanableGroups() {
		var p = Presenter(rules: rules)
		p.load(report(ScanItem(ruleName: "app-caches", path: "/u/Library/Caches/a", sizeBytes: 100, risk: .low)))

		XCTAssertEqual(p.chartSegments().map { $0.key }, ["app-caches"])
	}

	func testEmptyReportGivesNoGroupsAndZeroTotal() {
		var p = Presenter(rules: rules)
		p.load(report())

		XCTAssertTrue(p.groups().isEmpty)
		XCTAssertEqual(p.totalText, "0 B")
	}
}
