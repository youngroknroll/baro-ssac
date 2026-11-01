import XCTest
@testable import BaroSsacCore

internal final class FilesPresenterTests: XCTestCase {
	let now = epoch.addingTimeInterval(days(1000))

	private func fileItem(
		_ path: String,
		_ size: Int64,
		_ category: FileCategory = .downloads,
		suggestions: [Suggestion] = [],
		protectedReason: String? = nil
	) -> FileItem {
		FileItem(
			record: fileRecord(path, size),
			category: category,
			suggestions: suggestions,
			protectedReason: protectedReason
		)
	}

	private func loaded(_ items: [FileItem], total: Int64 = 0) -> FilesPresenter {
		var p = FilesPresenter(home: "/u")
		let byCategory = Dictionary(grouping: items, by: \.category)
		p.load(FileReport(summaries: FileCategory.allCases.map {
			CategorySummary(category: $0, totalBytes: total, items: byCategory[$0] ?? [])
		}))
		return p
	}

	// MARK: 이유 문구

	func testSuggestionTexts() {
		func text(_ suggestion: Suggestion) -> String { SuggestionText.describe(suggestion, now: now) }
		func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-days(n)) }

		XCTAssertEqual(text(.installer), "설치 파일")
		XCTAssertEqual(text(.duplicate(keep: "/u/Documents/report.pdf")), "중복 · 원본 report.pdf")
		XCTAssertEqual(text(.stale(since: daysAgo(800))), "2년 넘게 안 열었음")
		XCTAssertEqual(text(.stale(since: daysAgo(95))), "3개월 넘게 안 열었음")
		XCTAssertEqual(text(.stale(since: daysAgo(5))), "5일 동안 안 열었음")
	}

	// MARK: 목록

	/// 사용자 파일은 추천이 있어도 기본으로 고르지 않는다.
	func testNothingIsSelectedAfterLoading() {
		let p = loaded([fileItem("/u/Downloads/a.dmg", 10, suggestions: [.installer])])

		XCTAssertFalse(p.isSelected("/u/Downloads/a.dmg"))
		XCTAssertEqual(p.selectedBytes(in: .downloads), 0)
	}

	func testSuggestedModeShowsOnlySuggestedUnprotectedAndAllModeShowsEverythingBySize() {
		let p = loaded([
			fileItem("/u/Downloads/small.dmg", 1, suggestions: [.installer]),
			fileItem("/u/Downloads/big.mov", 50),
			fileItem("/u/Downloads/Lib.photoslibrary", 30, suggestions: [.installer], protectedReason: "사진 앱에서 정리하세요"),
		])

		XCTAssertEqual(p.rows(.downloads, mode: .suggested, now: now).map(\.name), ["small.dmg"])
		let all = p.rows(.downloads, mode: .all, now: now).map(\.name)
		XCTAssertEqual(all, ["big.mov", "Lib.photoslibrary", "small.dmg"])
	}

	func testRowShowsFolderRelativeToHomeAndReasons() {
		let p = loaded([fileItem("/u/Downloads/sub/a.dmg", 10, suggestions: [.installer])])

		let row = p.rows(.downloads, mode: .all, now: now).first
		XCTAssertEqual(row?.folder, "~/Downloads/sub")
		XCTAssertEqual(row?.reasons, ["설치 파일"])
	}

	func testCategoryTotalsAndSuggestedAmounts() {
		let p = loaded(
			[fileItem("/u/Downloads/a.dmg", 10, suggestions: [.installer]), fileItem("/u/Downloads/b.txt", 5)],
			total: 99
		)

		XCTAssertEqual(p.totalBytes(.downloads), 99)
		XCTAssertEqual(p.suggestedBytes(.downloads), 10)
		XCTAssertEqual(p.suggestedCount(.downloads), 1)
	}

	// MARK: 선택

	func testProtectedItemsCannotBeSelected() {
		var p = loaded([fileItem("/u/Pictures/P.photoslibrary", 10, .pictures, protectedReason: "사진 앱에서 정리하세요")])

		p.setSelected("/u/Pictures/P.photoslibrary", true)

		XCTAssertFalse(p.isSelected("/u/Pictures/P.photoslibrary"))
	}

	func testSelectAllSuggestedSelectsOnlySuggestedItemsInThatCategory() {
		var p = loaded([
			fileItem("/u/Downloads/a.dmg", 10, suggestions: [.installer]),
			fileItem("/u/Downloads/b.txt", 5),
			fileItem("/u/Movies/old.mov", 70, .movies, suggestions: [.stale(since: epoch)]),
		])

		p.selectAllSuggested(in: .downloads)

		XCTAssertEqual(p.selectedItems(in: .downloads).map(\.path), ["/u/Downloads/a.dmg"])
		XCTAssertEqual(p.selectedItems(in: .movies), [])
		XCTAssertEqual(p.trashRequests(in: .downloads), [TrashRequest(path: "/u/Downloads/a.dmg", sizeBytes: 10)])
	}

	func testClearSelectionOnlyAffectsThatCategory() {
		var p = loaded([
			fileItem("/u/Downloads/a.dmg", 10),
			fileItem("/u/Movies/m.mov", 70, .movies),
		])
		p.setSelected("/u/Downloads/a.dmg", true)
		p.setSelected("/u/Movies/m.mov", true)

		p.clearSelection(in: .downloads)

		XCTAssertEqual(p.selectedBytes(in: .downloads), 0)
		XCTAssertEqual(p.selectedBytes(in: .movies), 70)
	}

	func testUnknownPathsAreIgnored() {
		var p = loaded([])

		p.setSelected("/etc/passwd", true)

		XCTAssertFalse(p.isSelected("/etc/passwd"))
	}
}
