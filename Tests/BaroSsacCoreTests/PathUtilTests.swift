import XCTest
@testable import BaroSsacCore

internal final class PathUtilTests: XCTestCase {
	func testNormalizeCollapsesDotsAndParentReferences() {
		XCTAssertEqual(PathUtil.normalize("/u/Library/Caches/../../Documents"), "/u/Documents")
		XCTAssertEqual(PathUtil.normalize("/u//Library/./Caches/"), "/u/Library/Caches")
		XCTAssertEqual(PathUtil.normalize("/"), "/")
		XCTAssertEqual(PathUtil.normalize("/../x"), "/x")
	}

	func testStrictlyInside() {
		XCTAssertTrue(PathUtil.isStrictlyInside("/a/b/c", root: "/a/b"))
		XCTAssertFalse(PathUtil.isStrictlyInside("/a/b", root: "/a/b"))
		XCTAssertFalse(PathUtil.isStrictlyInside("/a/bc", root: "/a/b"))
		XCTAssertFalse(PathUtil.isStrictlyInside("/a/b/../c", root: "/a/b"))
	}

	func testRelativeAndBasename() {
		XCTAssertEqual(PathUtil.relative("/a/b/c/d", to: "/a/b"), "c/d")
		XCTAssertNil(PathUtil.relative("/x", to: "/a/b"))
		XCTAssertEqual(PathUtil.basename("/a/b/c.log"), "c.log")
	}

	func testGlobMatching() {
		XCTAssertTrue(PathUtil.matches("CloudKit*", "CloudKitMetadata"))
		XCTAssertTrue(PathUtil.matches("com.apple.bird", "com.apple.bird"))
		XCTAssertFalse(PathUtil.matches("com.apple.bird", "com.apple.birdy"))
	}
}
