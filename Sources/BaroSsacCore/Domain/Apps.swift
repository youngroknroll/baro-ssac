// 응용 프로그램 · 관련 파일 도메인
import Foundation

public struct InstalledApp: Hashable, Sendable {
	public let path: String
	public let name: String
	public let bundleID: String?
	public let sizeBytes: Int64
	/// Spotlight 마지막 사용일 | 불명: nil
	public let lastUsedAt: Date?

	public init(path: String, name: String, bundleID: String?, sizeBytes: Int64, lastUsedAt: Date?) {
		self.path = path
		self.name = name
		self.bundleID = bundleID
		self.sizeBytes = sizeBytes
		self.lastUsedAt = lastUsedAt
	}

	/// macOS 기본 앱: 삭제 제외 (대부분 SIP 보호 · 삭제돼도 시스템이 재설치)
	public var isBuiltIn: Bool { bundleID?.hasPrefix("com.apple.") ?? false }
}

public enum LeftoverMatch: Hashable, Sendable {
	/// 번들 ID 일치 (해당 앱 소유 확실)
	case bundleID
	/// 앱 이름 일치 (동명 다른 앱 소유 가능)
	case appName
}

public struct Leftover: Hashable, Sendable, Identifiable {
	public let path: String
	public let sizeBytes: Int64
	public let match: LeftoverMatch

	public init(path: String, sizeBytes: Int64, match: LeftoverMatch) {
		self.path = path
		self.sizeBytes = sizeBytes
		self.match = match
	}

	public var id: String { path }
}

public struct AppItem: Hashable, Sendable, Identifiable {
	public let app: InstalledApp
	public let leftovers: [Leftover]
	public let suggestions: [Suggestion]
	public let protectedReason: String?

	public init(app: InstalledApp, leftovers: [Leftover], suggestions: [Suggestion], protectedReason: String?) {
		self.app = app
		self.leftovers = leftovers
		self.suggestions = suggestions
		self.protectedReason = protectedReason
	}

	public var id: String { app.path }
	public var leftoverBytes: Int64 { leftovers.reduce(0) { $0 + $1.sizeBytes } }
	public var totalBytes: Int64 { app.sizeBytes + leftoverBytes }
	public var isProtected: Bool { protectedReason != nil }
}

public struct LeftoverCandidate: Hashable, Sendable {
	public let path: String
	public let match: LeftoverMatch

	public init(path: String, match: LeftoverMatch) {
		self.path = path
		self.match = match
	}
}

public enum AppLeftovers {
	/// 관련 파일 탐색 위치 (~/Library 하위) | 휴지통 유스케이스 허용 범위
	public static func allowedRoots(home: String) -> [String] {
		let lib = "\(home)/Library"
		return [
			"\(lib)/Application Support",
			"\(lib)/Application Scripts",
			"\(lib)/Caches",
			"\(lib)/Containers",
			"\(lib)/Cookies",
			"\(lib)/HTTPStorages",
			"\(lib)/LaunchAgents",
			"\(lib)/Logs",
			"\(lib)/Preferences",
			"\(lib)/Saved Application State",
			"\(lib)/WebKit",
		]
	}

	/// 후보 경로 (존재 무관) | 번들 ID · 이름 중복 경로: 번들 ID 쪽만 유지
	/// 제외: Group Containers 등 여러 앱 공유 위치
	public static func candidates(
		bundleID: String?,
		appName: String,
		home: String
	) -> [LeftoverCandidate] {
		let lib = "\(home)/Library"
		var result: [LeftoverCandidate] = []

		if let id = bundleID, isSafeName(id) {
			let paths = [
				"\(lib)/Application Support/\(id)",
				"\(lib)/Application Scripts/\(id)",
				"\(lib)/Caches/\(id)",
				"\(lib)/Containers/\(id)",
				"\(lib)/Cookies/\(id).binarycookies",
				"\(lib)/HTTPStorages/\(id)",
				"\(lib)/HTTPStorages/\(id).binarycookies",
				"\(lib)/LaunchAgents/\(id).plist",
				"\(lib)/Preferences/\(id).plist",
				"\(lib)/Saved Application State/\(id).savedState",
				"\(lib)/WebKit/\(id)",
			]
			result += paths.map { LeftoverCandidate(path: $0, match: .bundleID) }
		}
		if isSafeName(appName) {
			let paths = [
				"\(lib)/Application Support/\(appName)",
				"\(lib)/Caches/\(appName)",
				"\(lib)/Logs/\(appName)",
			]
			let taken = Set(result.map(\.path))
			result += paths.filter { !taken.contains($0) }.map { LeftoverCandidate(path: $0, match: .appName) }
		}
		return result
	}

	/// 경로 한 칸 이름 여부 | 불가: 빈 값 · `.` · `..` · `/` 포함
	private static func isSafeName(_ name: String) -> Bool {
		!name.isEmpty && name != "." && name != ".." && !name.contains("/")
	}
}
