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

	/// 하위 캐시를 `번들ID.이름` 폴더로 분리한 앱
	func testFolderPrefixedWithBundleIDAndDotIsOwned() {
		XCTAssertEqual(
			AppMatching.owner(of: "/u/Library/Caches/com.apple.Safari.SafeBrowsing", running: running),
			"com.apple.Safari"
		)
	}

	/// 유사 이름 앱 오인 방지
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
