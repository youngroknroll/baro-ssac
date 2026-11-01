// 응용 프로그램과 그 앱이 남긴 파일.
import Foundation

public struct InstalledApp: Hashable, Sendable {
	public let path: String
	public let name: String
	public let bundleID: String?
	public let sizeBytes: Int64
	/// Spotlight 의 '마지막으로 연 날짜'. 모르면 nil.
	public let lastUsedAt: Date?

	public init(path: String, name: String, bundleID: String?, sizeBytes: Int64, lastUsedAt: Date?) {
		self.path = path
		self.name = name
		self.bundleID = bundleID
		self.sizeBytes = sizeBytes
		self.lastUsedAt = lastUsedAt
	}

	/// macOS 기본 앱은 지우지 않는다 (대부분 SIP 로 보호되고, 지워지더라도 시스템이 다시 설치한다).
	public var isBuiltIn: Bool { bundleID?.hasPrefix("com.apple.") ?? false }
}

public enum LeftoverMatch: Hashable, Sendable {
	/// 번들 ID 로 찾음. 그 앱의 것이 거의 확실하다.
	case bundleID
	/// 앱 이름으로 찾음. 이름이 같은 다른 앱의 것일 수도 있다.
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
	/// 앱이 남긴 파일을 찾는 ~/Library 하위 폴더. 휴지통 유스케이스는 이 안만 허용한다.
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

	/// 존재 여부와 상관없이 찾아볼 경로. 같은 경로가 번들 ID 와 이름 양쪽에서 나오면 번들 ID 쪽만 남긴다.
	/// Group Containers 처럼 여러 앱이 함께 쓰는 곳은 넣지 않는다.
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

	/// 경로 한 칸으로만 쓰일 수 있는 이름인지. 비었거나 `.`/`..` 이거나 `/` 가 있으면 안 된다.
	private static func isSafeName(_ name: String) -> Bool {
		!name.isEmpty && name != "." && name != ".." && !name.contains("/")
	}
}
