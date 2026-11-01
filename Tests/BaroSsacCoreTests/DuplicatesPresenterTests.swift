import XCTest
@testable import BaroSsacCore

/// 중복 파일 탭: 같은 내용의 파일을 묶음(원본 1 + 사본 N)으로 보여 준다.
internal final class DuplicatesPresenterTests: XCTestCase {
	let now = epoch.addingTimeInterval(days(1000))

	private func item(_ path: String, _ size: Int64, _ category: FileCategory, keep: String? = nil) -> FileItem {
		FileItem(
			record: fileRecord(path, size),
			category: category,
			suggestions: keep.map { [.duplicate(keep: $0)] } ?? [],
			protectedReason: nil
		)
	}

	/// 원본 report.pdf(4) + 사본 2개, 원본 movie.mov(9) + 사본 1개, 중복 아닌 notes.txt.
	private func loaded() -> FilesPresenter {
		var p = FilesPresenter(home: "/u")
		p.load(FileReport(summaries: [
			CategorySummary(category: .documents, totalBytes: 0, items: [
				item("/u/Documents/report.pdf", 4, .documents),
				item("/u/Documents/notes.txt", 7, .documents),
				item("/u/Documents/movie copy.mov", 9, .documents, keep: "/u/Movies/movie.mov"),
			]),
			CategorySummary(category: .downloads, totalBytes: 0, items: [
				item("/u/Downloads/report.pdf", 4, .downloads, keep: "/u/Documents/report.pdf"),
				item("/u/Downloads/report (1).pdf", 4, .downloads, keep: "/u/Documents/report.pdf"),
			]),
			CategorySummary(category: .movies, totalBytes: 0, items: [
				item("/u/Movies/movie.mov", 9, .movies),
			]),
		]))
		return p
	}

	func testGroupsPairEachKeeperWithItsCopiesSortedByReclaimableSpace() {
		let groups = loaded().duplicateGroups(now: now)

		XCTAssertEqual(groups.map(\.keeper.path), ["/u/Movies/movie.mov", "/u/Documents/report.pdf"])
		XCTAssertEqual(groups.map(\.reclaimableBytes), [9, 8])
		XCTAssertEqual(groups[1].copies.map(\.path), ["/u/Downloads/report (1).pdf", "/u/Downloads/report.pdf"])
		XCTAssertEqual(groups[1].keeper.folder, "~/Documents")
	}

	func testTotalReclaimableAndCounts() {
		let p = loaded()

		XCTAssertEqual(p.duplicateReclaimableBytes, 17)
		XCTAssertEqual(p.duplicateGroups(now: now).count, 2)
	}

	func testNothingIsPreselectedAndSelectAllCopiesLeavesKeepers() {
		var p = loaded()
		XCTAssertEqual(p.selectedDuplicateItems().count, 0)

		p.selectAllDuplicateCopies()

		XCTAssertEqual(Set(p.selectedDuplicateItems().map(\.path)), [
			"/u/Documents/movie copy.mov", "/u/Downloads/report.pdf", "/u/Downloads/report (1).pdf",
		])
		XCTAssertFalse(p.isSelected("/u/Documents/report.pdf"))
		XCTAssertEqual(p.fullySelectedDuplicateGroups(), 0)
	}

	/// 원본까지 모두 고르면 그 내용이 하나도 남지 않는다. 막지는 않고 경고한다.
	func testGroupsWithEveryCopySelectedAreCountedForAWarning() {
		var p = loaded()
		p.selectAllDuplicateCopies()
		p.setSelected("/u/Documents/report.pdf", true)

		XCTAssertEqual(p.fullySelectedDuplicateGroups(), 1)
	}

	/// 다른 카테고리를 지울 때 엉뚱하게 경고하지 않도록, 실제로 지울 경로만으로 판단한다.
	func testGroupIsEmptiedOnlyWhenEveryMemberIsInTheTrashedPaths() {
		let p = loaded()

		XCTAssertEqual(p.duplicateGroupsEmptied(by: ["/u/Movies/movie.mov"]), 0)
		XCTAssertEqual(p.duplicateGroupsEmptied(by: ["/u/Movies/movie.mov", "/u/Documents/movie copy.mov"]), 1)
	}

	func testTrashRequestsContainOnlySelectedGroupMembers() {
		var p = loaded()
		p.setSelected("/u/Documents/notes.txt", true)
		p.setSelected("/u/Downloads/report.pdf", true)

		XCTAssertEqual(p.duplicateTrashRequests(), [TrashRequest(path: "/u/Downloads/report.pdf", sizeBytes: 4)])
	}

	func testClearDuplicateSelectionKeepsOtherSelections() {
		var p = loaded()
		p.setSelected("/u/Documents/notes.txt", true)
		p.selectAllDuplicateCopies()

		p.clearDuplicateSelection()

		XCTAssertEqual(p.selectedDuplicateItems(), [])
		XCTAssertTrue(p.isSelected("/u/Documents/notes.txt"))
	}

	func testNoGroupsWithoutDuplicates() {
		var p = FilesPresenter(home: "/u")
		p.load(FileReport(summaries: [
			CategorySummary(category: .documents, totalBytes: 0, items: [item("/u/Documents/a.pdf", 1, .documents)]),
		]))

		XCTAssertEqual(p.duplicateGroups(now: now), [])
		XCTAssertEqual(p.duplicateReclaimableBytes, 0)
	}
}
