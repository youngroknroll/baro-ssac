import XCTest
@testable import BaroSsacCore

internal final class DefaultRulesTests: XCTestCase {
	let home = "/Users/tester"
	var rules: [CleanupRule] { DefaultRules.rules(home: home) }

	private func rule(_ name: String) throws -> CleanupRule {
		try XCTUnwrap(rules.first { $0.name == name }, "rule \(name) not found")
	}

	func testRuleNamesAreUnique() {
		let names = rules.map { $0.name }
		XCTAssertEqual(names.count, Set(names).count)
	}

	/// 1단계에서는 관리자 권한이 필요한 시스템 경로를 대상으로 삼지 않는다.
	func testEveryRuleLivesInsideTheUserHome() {
		for r in rules {
			XCTAssertTrue(r.root.hasPrefix(home + "/"), r.name)
		}
	}

	func testNoRuleTouchesForbiddenLocations() {
		for r in rules {
			let root = PathUtil.normalize(r.root)
			for forbidden in DefaultRules.forbiddenRoots {
				XCTAssertFalse(root == forbidden || root.hasPrefix(forbidden + "/"), r.name)
				XCTAssertFalse(forbidden.hasPrefix(root + "/"), r.name)
			}
		}
	}

	func testHomeItselfAndDocumentsAreNeverRuleRoots() {
		let roots = Set(rules.map { $0.root })
		for unsafe in [home, "\(home)/Library", "\(home)/Documents", "\(home)/Desktop"] {
			XCTAssertFalse(roots.contains(unsafe), unsafe)
		}
	}

	func testRuleRootsDoNotOverlapSoNothingIsCountedTwice() {
		let roots = rules.map { $0.root }
		for a in roots {
			for b in roots where a != b {
				XCTAssertFalse(b.hasPrefix(a + "/"), "\(a) contains \(b)")
			}
		}
	}

	func testEveryRuleHasAShortTitleForTheList() {
		for r in rules {
			XCTAssertFalse(r.title.isEmpty, r.name)
			XCTAssertLessThanOrEqual(r.title.count, 14, r.name)
			XCTAssertFalse(r.description.isEmpty, r.name)
		}
	}

	func testIOSBackupsAreHighRisk() throws {
		XCTAssertEqual(try rule("ios-backups").risk, .high)
	}

	/// 폴더 단위로 나이를 재면 활성 앱의 로그 폴더는 전부 '최근'이 되어 버린다.
	func testRulesWithAgeConditionJudgePerFile() {
		for r in rules where r.minAgeDays > 0 {
			XCTAssertEqual(r.granularity, .files, r.name)
		}
	}

	func testAppCachesExcludeICloudAndSyncState() throws {
		let excl = try rule("app-caches").exclude
		XCTAssertTrue(excl.contains("com.apple.bird"))
		XCTAssertTrue(excl.contains { $0.hasPrefix("CloudKit") })
	}

	func testNpmCacacheIsCleanedAsAWhole() throws {
		XCTAssertEqual(try rule("npm-cache").granularity, .root)
	}

	func testCachesThatAreSlowToRebuildAreNotLowRisk() throws {
		XCTAssertEqual(try rule("xdg-cache").risk, .medium)
	}
}
