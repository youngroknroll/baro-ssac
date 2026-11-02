import XCTest
@testable import BaroSsacCore

internal final class ProtectedPackagesTests: XCTestCase {
	func testPhotosLibraryItselfIsProtected() {
		XCTAssertNotNil(ProtectedPackages.reason(for: "/u/Pictures/Photos Library.photoslibrary"))
	}

	/// 라이브러리 내부 파일 1개 삭제만으로도 사진 앱 DB 불일치
	func testFilesInsideALibraryAreProtected() {
		XCTAssertNotNil(ProtectedPackages.reason(for: "/u/Pictures/Photos Library.photoslibrary/originals/A/x.heic"))
	}

	func testExtensionMatchIgnoresCase() {
		XCTAssertNotNil(ProtectedPackages.reason(for: "/u/Music/Music/Music Library.MusicLibrary"))
	}

	func testOrdinaryFilesAreNotProtected() {
		XCTAssertNil(ProtectedPackages.reason(for: "/u/Pictures/trip/IMG_0001.jpg"))
		XCTAssertNil(ProtectedPackages.reason(for: "/u/Downloads/Slack.dmg"))
	}

	func testFileExtensionIsLowercasedAndEmptyWhenMissing() {
		XCTAssertEqual(fileRecord("/u/Downloads/Setup.DMG", 1).fileExtension, "dmg")
		XCTAssertEqual(fileRecord("/u/Documents/README", 1).fileExtension, "")
		XCTAssertEqual(fileRecord("/u/Documents/.env", 1).fileExtension, "")
	}
}
