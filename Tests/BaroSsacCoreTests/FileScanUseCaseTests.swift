import XCTest
@testable import BaroSsacCore

internal final class FileScanUseCaseTests: XCTestCase {
	let now = epoch.addingTimeInterval(days(1000))
	let home = "/u"
	let policy = SuggestionPolicy(
		staleAfterDays: 365,
		staleMinBytes: 100 * megabyte,
		duplicateMinBytes: megabyte,
		listMinBytes: megabyte
	)

	private func scan(
		_ listings: [String: FileListing],
		hasher: FakeHasher = FakeHasher([:]),
		existing: Set<String>? = nil,
		categories: [FileCategory] = FileCategory.allCases
	) -> FileReport {
		let roots = existing ?? Set(listings.keys)
		let fs = InMemoryFileSystem(Dictionary(uniqueKeysWithValues: roots.map { ($0 + "/.keep", 0) }))
		let useCase = FileScanUseCase(
			walker: FakeWalker(listings: listings),
			hasher: hasher,
			fs: fs,
			clock: FixedClock(fixed: now),
			policy: policy
		)
		return useCase.execute(FileCategory.scopes(home: home, categories: categories))
	}

	func testDocumentsCoverDocumentsAndDesktop() {
		XCTAssertEqual(FileCategory.documents.roots(home: home), ["/u/Documents", "/u/Desktop"])
	}

	func testCategoryTotalIncludesSmallFilesButListOnlyLargeOnesSortedBySize() {
		let report = scan([
			"/u/Documents": FileListing(
				records: [
					fileRecord("/u/Documents/a.pdf", 2 * megabyte),
					fileRecord("/u/Documents/b.mov", 5 * megabyte),
				],
				totalBytes: 7 * megabyte + 500
			),
			"/u/Desktop": FileListing(
				records: [fileRecord("/u/Desktop/c.zip", 3 * megabyte)],
				totalBytes: 3 * megabyte
			),
		])

		let docs = report.summary(for: .documents)
		XCTAssertEqual(docs?.totalBytes, 10 * megabyte + 500)
		XCTAssertEqual(docs?.items.map(\.path), ["/u/Documents/b.mov", "/u/Desktop/c.zip", "/u/Documents/a.pdf"])
	}

	func testMissingFolderIsSkippedAsNotFoundAndUnreadableAsPermissionDenied() {
		let report = scan(
			["/u/Pictures": FileListing()],
			existing: ["/u/Pictures", "/u/Music"],
			categories: [.pictures, .music, .movies]
		)

		XCTAssertTrue(report.skipped.contains(SkippedItem(path: "/u/Music", reason: .permissionDenied)))
		XCTAssertTrue(report.skipped.contains(SkippedItem(path: "/u/Movies", reason: .notFound)))
		XCTAssertEqual(report.summary(for: .pictures)?.totalBytes, 0)
	}

	func testInstallersInDownloadsAreSuggestedButNotElsewhere() {
		let report = scan([
			"/u/Downloads": FileListing(records: [fileRecord("/u/Downloads/Slack.dmg", 2 * megabyte)], totalBytes: 0),
			"/u/Documents": FileListing(records: [fileRecord("/u/Documents/backup.dmg", 2 * megabyte)], totalBytes: 0),
		])

		XCTAssertEqual(report.summary(for: .downloads)?.items.first?.suggestions, [.installer])
		XCTAssertEqual(report.summary(for: .documents)?.items.first?.suggestions, [])
	}

	func testLargeFileNotOpenedForAYearIsStale() {
		let lastUsed = now.addingTimeInterval(-days(400))
		let report = scan([
			"/u/Movies": FileListing(
				records: [fileRecord("/u/Movies/old.mov", 200 * megabyte, modified: now, lastUsed: lastUsed)],
				totalBytes: 0
			),
		])

		XCTAssertEqual(report.summary(for: .movies)?.items.first?.suggestions, [.stale(since: lastUsed)])
	}

	/// 한 번도 열지 않은 파일은 Spotlight 의 마지막 사용일이 없다. 그때는 수정일로 판단한다.
	func testStaleFallsBackToModifiedDateWhenNeverOpened() {
		let modified = now.addingTimeInterval(-days(500))
		let report = scan([
			"/u/Movies": FileListing(
				records: [fileRecord("/u/Movies/never.mov", 200 * megabyte, modified: modified)],
				totalBytes: 0
			),
		])

		XCTAssertEqual(report.summary(for: .movies)?.items.first?.suggestions, [.stale(since: modified)])
	}

	func testSmallOrRecentFilesAreNotStale() {
		let old = now.addingTimeInterval(-days(800))
		let recent = now.addingTimeInterval(-days(10))
		let report = scan([
			"/u/Movies": FileListing(
				records: [
					fileRecord("/u/Movies/small.mov", 50 * megabyte, modified: old),
					fileRecord("/u/Movies/recent.mov", 500 * megabyte, modified: old, lastUsed: recent),
				],
				totalBytes: 0
			),
		])

		XCTAssertEqual(report.summary(for: .movies)?.items.map(\.suggestions), [[], []])
	}

	/// 같은 내용이면 하나만 남긴다. 다운로드 폴더에 있는 사본을 지우자고 제안한다.
	func testDuplicatesKeepTheCopyOutsideDownloads() {
		let hasher = FakeHasher([
			"/u/Documents/report.pdf": "same-content",
			"/u/Downloads/report (1).pdf": "same-content",
		])
		let report = scan(
			[
				"/u/Documents": FileListing(
					records: [fileRecord("/u/Documents/report.pdf", 4 * megabyte)],
					totalBytes: 0
				),
				"/u/Downloads": FileListing(
					records: [fileRecord("/u/Downloads/report (1).pdf", 4 * megabyte)],
					totalBytes: 0
				),
			],
			hasher: hasher
		)

		XCTAssertEqual(report.summary(for: .documents)?.items.first?.suggestions, [])
		XCTAssertEqual(
			report.summary(for: .downloads)?.items.first?.suggestions,
			[.duplicate(keep: "/u/Documents/report.pdf")]
		)
	}

	func testAmongDuplicatesOutsideDownloadsTheOldestIsKept() {
		let monthAgo = now.addingTimeInterval(-days(30))
		let hasher = FakeHasher(["/u/Documents/new.mov": "abcdef", "/u/Movies/old.mov": "abcdef"])
		let report = scan(
			[
				"/u/Documents": FileListing(
					records: [fileRecord("/u/Documents/new.mov", 9 * megabyte, modified: now)],
					totalBytes: 0
				),
				"/u/Movies": FileListing(
					records: [fileRecord("/u/Movies/old.mov", 9 * megabyte, modified: monthAgo)],
					totalBytes: 0
				),
			],
			hasher: hasher
		)

		XCTAssertEqual(
			report.summary(for: .documents)?.items.first?.suggestions,
			[.duplicate(keep: "/u/Movies/old.mov")]
		)
		XCTAssertEqual(report.summary(for: .movies)?.items.first?.suggestions, [])
	}

	/// 크기와 앞부분이 같아도 전체 내용이 다르면 중복이 아니다.
	func testSameSizeAndSamePrefixButDifferentContentIsNotDuplicate() {
		let hasher = FakeHasher(["/u/Movies/a.mov": "abc-1", "/u/Movies/b.mov": "abc-2"])
		let report = scan(
			["/u/Movies": FileListing(
				records: [fileRecord("/u/Movies/a.mov", 9 * megabyte), fileRecord("/u/Movies/b.mov", 9 * megabyte)],
				totalBytes: 0
			)],
			hasher: hasher
		)

		XCTAssertEqual(report.summary(for: .movies)?.items.map(\.suggestions), [[], []])
	}

	/// 크기가 다르면 내용을 읽지 않는다. 표본이 다르면 전체를 읽지 않는다.
	func testContentIsReadOnlyWhenCheaperChecksMatch() {
		let hasher = FakeHasher([
			"/u/Movies/a.mov": "xyz-1", "/u/Movies/b.mov": "qrs-1", "/u/Movies/c.mov": "zzz",
		])
		_ = scan(
			["/u/Movies": FileListing(
				records: [
					fileRecord("/u/Movies/a.mov", 9 * megabyte),
					fileRecord("/u/Movies/b.mov", 9 * megabyte),
					fileRecord("/u/Movies/c.mov", 7 * megabyte),
				],
				totalBytes: 0
			)],
			hasher: hasher
		)

		XCTAssertEqual(hasher.fullHashCount, 0)
	}

	func testProtectedLibrariesHaveAReasonAndNoSuggestions() {
		let old = now.addingTimeInterval(-days(900))
		let report = scan([
			"/u/Pictures": FileListing(
				records: [
					fileRecord(
						"/u/Pictures/Photos Library.photoslibrary",
						900 * megabyte,
						modified: old,
						isPackage: true
					),
				],
				totalBytes: 0
			),
		])

		let item = report.summary(for: .pictures)?.items.first
		XCTAssertNotNil(item?.protectedReason)
		XCTAssertEqual(item?.suggestions, [])
	}

	/// 패키지(.app, .key 등)는 내용을 해시하지 않는다 (디렉터리라 읽을 수 없고, 크기가 같아도 의미가 없다).
	func testPackagesAreNotCheckedForDuplicates() {
		let hasher = FakeHasher([:])
		let report = scan(
			["/u/Downloads": FileListing(
				records: [
					fileRecord("/u/Downloads/A.app", 9 * megabyte, isPackage: true),
					fileRecord("/u/Downloads/B.app", 9 * megabyte, isPackage: true),
				],
				totalBytes: 0
			)],
			hasher: hasher
		)

		XCTAssertEqual(report.summary(for: .downloads)?.items.map(\.suggestions), [[], []])
	}

	func testSuggestedBytesCountsOnlySuggestedUnprotectedItems() {
		let report = scan([
			"/u/Downloads": FileListing(
				records: [
					fileRecord("/u/Downloads/a.dmg", 2 * megabyte),
					fileRecord("/u/Downloads/notes.txt", 3 * megabyte),
				],
				totalBytes: 0
			),
		])

		XCTAssertEqual(report.summary(for: .downloads)?.suggestedBytes, 2 * megabyte)
	}
}
