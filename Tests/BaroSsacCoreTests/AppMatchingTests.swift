import XCTest
@testable import BaroSsacCore

internal final class AppMatchingTests: XCTestCase {
	let running: Set<String> = ["com.spotify.client", "com.apple.Safari", "com.tinyspeck.slackmacgap"]

	func testFolderNamedExactlyAfterRunningBundleIDIsOwned() {
		let owner = AppMatching.owner(of: "/u/Library/Caches/com.spotify.client", running: running)
		XCTAssertEqual(owner, "com.spotify.client")
	}

	func testMatchingIgnoresCase() {
		let owner = AppMatching.owner(of: "/u/Library/Caches/com.Spotify.Client", running: running)
		XCTAssertEqual(owner, "com.spotify.client")
	}

	/// 앱이 하위 캐시를 `번들ID.무엇` 폴더로 따로 두는 경우.
	func testFolderPrefixedWithBundleIDAndDotIsOwned() {
		XCTAssertEqual(
			AppMatching.owner(of: "/u/Library/Caches/com.apple.Safari.SafeBrowsing", running: running),
			"com.apple.Safari"
		)
	}

	/// 이름이 비슷할 뿐인 다른 앱을 실행 중으로 착각하지 않는다.
	func testPrefixWithoutDotIsNotOwned() {
		XCTAssertNil(AppMatching.owner(of: "/u/Library/Caches/com.spotify.client2", running: running))
	}

	func testUnrelatedFolderIsNotOwned() {
		XCTAssertNil(AppMatching.owner(of: "/u/Library/Caches/Homebrew", running: running))
	}

	func testNothingRunningMeansNothingOwned() {
		XCTAssertNil(AppMatching.owner(of: "/u/Library/Caches/com.spotify.client", running: []))
	}
}
