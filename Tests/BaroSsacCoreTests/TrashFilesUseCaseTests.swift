import XCTest
@testable import BaroSsacCore

internal final class TrashFilesUseCaseTests: XCTestCase {
	let roots = ["/u/Documents", "/u/Downloads", "/Applications"]

	private func useCase(
		_ trash: SpyTrash,
		existing: [String],
		running: Set<String> = []
	) -> TrashFilesUseCase {
		let fs = InMemoryFileSystem(Dictionary(uniqueKeysWithValues: existing.map { ($0, 1) }))
		return TrashFilesUseCase(trash: trash, fs: fs, allowedRoots: roots, runningApps: FakeRunningApps(ids: running))
	}

	func testDryRunIsTheDefaultAndNeverTouchesTrash() {
		let trash = SpyTrash()

		let result = useCase(trash, existing: ["/u/Documents/a.pdf"])
			.execute([TrashRequest(path: "/u/Documents/a.pdf", sizeBytes: 10)])

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.map(\.outcome), [.wouldTrash])
		XCTAssertEqual(result.freedBytes, 10)
	}

	func testRealRunTrashesAndCountsFreedBytes() {
		let trash = SpyTrash()

		let result = useCase(trash, existing: ["/u/Documents/a.pdf", "/u/Downloads/b.dmg"]).execute(
			[
				TrashRequest(path: "/u/Documents/a.pdf", sizeBytes: 10),
				TrashRequest(path: "/u/Downloads/b.dmg", sizeBytes: 5),
			],
			dryRun: false
		)

		XCTAssertEqual(trash.trashed, ["/u/Documents/a.pdf", "/u/Downloads/b.dmg"])
		XCTAssertEqual(result.freedBytes, 15)
	}

	func testPathsOutsideAllowedRootsAreRejected() {
		let trash = SpyTrash()
		let requests = [
			TrashRequest(path: "/u/Library/Keychains/login.keychain-db", sizeBytes: 1),
			TrashRequest(path: "/u/Documents/../Library/x", sizeBytes: 1),
			TrashRequest(path: "/u/Documents", sizeBytes: 1),
		]

		let result = useCase(trash, existing: requests.map(\.path)).execute(requests, dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.map(\.outcome), Array(repeating: .rejectedOutsideRules, count: 3))
	}

	func testProtectedLibrariesAndAnythingInsideThemAreRefused() {
		let trash = SpyTrash()
		let requests = [
			TrashRequest(path: "/u/Documents/Photos Library.photoslibrary", sizeBytes: 1),
			TrashRequest(path: "/u/Documents/Photos Library.photoslibrary/originals/x.heic", sizeBytes: 1),
		]

		let result = useCase(trash, existing: requests.map(\.path)).execute(requests, dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.map(\.outcome), [.protected, .protected])
	}

	func testMacOSBuiltInAppsAreRefused() {
		let trash = SpyTrash()
		let request = TrashRequest(path: "/Applications/Safari.app", sizeBytes: 1, bundleID: "com.apple.Safari")

		let result = useCase(trash, existing: [request.path]).execute([request], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .protected)
	}

	func testRunningAppIsNotTrashed() {
		let trash = SpyTrash()
		let request = TrashRequest(path: "/Applications/Slack.app", sizeBytes: 1, bundleID: "com.tinyspeck.slackmacgap")

		let result = useCase(trash, existing: [request.path], running: ["com.tinyspeck.slackmacgap"])
			.execute([request], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .inUse)
	}

	func testVanishedFileIsReportedStale() {
		let trash = SpyTrash()

		let request = TrashRequest(path: "/u/Documents/gone.pdf", sizeBytes: 1)

		let result = useCase(trash, existing: []).execute([request], dryRun: false)

		XCTAssertEqual(trash.trashed, [])
		XCTAssertEqual(result.entries.first?.outcome, .stale)
	}

	func testTrashFailureIsRecordedAndOthersContinue() {
		let trash = SpyTrash(failOn: ["/u/Documents/a.pdf"])

		let result = useCase(trash, existing: ["/u/Documents/a.pdf", "/u/Documents/b.pdf"]).execute(
			[
				TrashRequest(path: "/u/Documents/a.pdf", sizeBytes: 1),
				TrashRequest(path: "/u/Documents/b.pdf", sizeBytes: 2),
			],
			dryRun: false
		)

		XCTAssertEqual(result.entries.map(\.outcome), [.failed, .trashed])
		XCTAssertTrue(result.entries[0].error.contains("cannot trash"))
		XCTAssertEqual(result.freedBytes, 2)
	}
}
