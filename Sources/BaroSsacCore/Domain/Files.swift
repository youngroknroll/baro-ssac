// 사용자 파일(문서·사진·음악·동영상·다운로드) 도메인. 캐시 규칙과 달리 위치는 '어디에 있는가'만 나타내고,
// 지워도 되는지는 사용 이력과 내용으로 '제안'만 한다. 결정은 항상 사용자가 한다.
import Foundation

public enum FileCategory: String, CaseIterable, Hashable, Sendable {
	case documents
	case pictures
	case music
	case movies
	case downloads

	public var title: String {
		switch self {
		case .documents: "문서"
		case .pictures: "사진"
		case .music: "음악"
		case .movies: "동영상"
		case .downloads: "다운로드"
		}
	}

	public func roots(home: String) -> [String] {
		switch self {
		case .documents: ["\(home)/Documents", "\(home)/Desktop"]
		case .pictures: ["\(home)/Pictures"]
		case .music: ["\(home)/Music"]
		case .movies: ["\(home)/Movies"]
		case .downloads: ["\(home)/Downloads"]
		}
	}

	public static func scopes(home: String, categories: [FileCategory] = FileCategory.allCases) -> [CategoryScope] {
		categories.map { CategoryScope(category: $0, roots: $0.roots(home: home)) }
	}

	/// 휴지통 유스케이스가 허용할 위치: 모든 카테고리의 폴더.
	public static func allRoots(home: String) -> [String] {
		allCases.flatMap { $0.roots(home: home) }
	}
}

public struct CategoryScope: Hashable, Sendable {
	public let category: FileCategory
	public let roots: [String]

	public init(category: FileCategory, roots: [String]) {
		self.category = category
		self.roots = roots
	}
}

public struct FileRecord: Hashable, Sendable {
	public let path: String
	public let sizeBytes: Int64
	public let modifiedAt: Date
	/// Spotlight 의 '마지막으로 연 날짜'. 한 번도 열지 않았으면 nil.
	public let lastUsedAt: Date?
	/// .app, .key, .photoslibrary 처럼 Finder 가 파일 하나로 보여 주는 디렉터리.
	public let isPackage: Bool

	public init(path: String, sizeBytes: Int64, modifiedAt: Date, lastUsedAt: Date?, isPackage: Bool) {
		self.path = path
		self.sizeBytes = sizeBytes
		self.modifiedAt = modifiedAt
		self.lastUsedAt = lastUsedAt
		self.isPackage = isPackage
	}

	public var name: String { PathUtil.basename(path) }

	/// 소문자 확장자. 없거나 숨김 파일 이름(.env)이면 빈 문자열.
	public var fileExtension: String {
		guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
		return String(name[name.index(after: dot)...]).lowercased()
	}

	/// 마지막으로 연 날짜, 연 적이 없으면 수정한 날짜.
	public var lastTouchedAt: Date { lastUsedAt ?? modifiedAt }
}

public enum Suggestion: Hashable, Sendable {
	/// 같은 내용의 다른 사본이 있다. `keep` 은 남기기로 한 사본의 경로.
	case duplicate(keep: String)
	/// 다운로드 폴더의 설치 파일(.dmg, .pkg 등). 설치가 끝났다면 필요 없다.
	case installer
	/// 크고 오랫동안 열지 않았다. `since` 는 마지막으로 연(없으면 수정한) 시각.
	case stale(since: Date)
}

public struct FileItem: Hashable, Sendable, Identifiable {
	public let record: FileRecord
	public let category: FileCategory
	public let suggestions: [Suggestion]
	/// 앱이 관리하는 라이브러리라 여기서 지우면 안 되는 이유. nil 이면 지울 수 있다.
	public let protectedReason: String?

	public init(record: FileRecord, category: FileCategory, suggestions: [Suggestion], protectedReason: String?) {
		self.record = record
		self.category = category
		self.suggestions = suggestions
		self.protectedReason = protectedReason
	}

	public var id: String { record.path }
	public var path: String { record.path }
	public var sizeBytes: Int64 { record.sizeBytes }
	public var isProtected: Bool { protectedReason != nil }
	public var isSuggested: Bool { !suggestions.isEmpty && !isProtected }
}

public struct CategorySummary: Hashable, Sendable {
	public let category: FileCategory
	/// 목록에 오르지 않은 작은 파일까지 포함한 폴더 전체 크기.
	public let totalBytes: Int64
	/// 목록에 오른 항목. 크기 내림차순.
	public let items: [FileItem]

	public init(category: FileCategory, totalBytes: Int64, items: [FileItem]) {
		self.category = category
		self.totalBytes = totalBytes
		self.items = items
	}

	public var suggestedBytes: Int64 {
		items.filter(\.isSuggested).reduce(0) { $0 + $1.sizeBytes }
	}
}

public struct FileReport: Sendable {
	public var summaries: [CategorySummary]
	public var skipped: [SkippedItem]

	public init(summaries: [CategorySummary] = [], skipped: [SkippedItem] = []) {
		self.summaries = summaries
		self.skipped = skipped
	}

	public func summary(for category: FileCategory) -> CategorySummary? {
		summaries.first { $0.category == category }
	}
}

public struct SuggestionPolicy: Hashable, Sendable {
	public var staleAfterDays: Int
	public var staleMinBytes: Int64
	public var duplicateMinBytes: Int64
	/// 이보다 작은 파일은 목록에 올리지 않고 합계에만 더한다 (수십만 개의 작은 파일로 목록이 무거워지지 않게).
	public var listMinBytes: Int64

	public init(staleAfterDays: Int, staleMinBytes: Int64, duplicateMinBytes: Int64, listMinBytes: Int64) {
		self.staleAfterDays = staleAfterDays
		self.staleMinBytes = staleMinBytes
		self.duplicateMinBytes = duplicateMinBytes
		self.listMinBytes = listMinBytes
	}

	public static let standard = SuggestionPolicy(
		staleAfterDays: 365,
		staleMinBytes: 100 * 1024 * 1024,
		duplicateMinBytes: 1024 * 1024,
		listMinBytes: 1024 * 1024
	)

	public static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
}

public enum ProtectedPackages {
	/// 앱이 내부 구조를 관리하는 라이브러리. 일부만 지우면 라이브러리가 깨지므로 그 앱에서 정리해야 한다.
	public static let reasons: [String: String] = [
		"photoslibrary": "사진 앱에서 정리하세요",
		"photolibrary": "사진 앱에서 정리하세요",
		"musiclibrary": "음악 앱에서 정리하세요",
		"tvlibrary": "TV 앱에서 정리하세요",
		"imovielibrary": "iMovie에서 정리하세요",
		"fcpbundle": "Final Cut Pro에서 정리하세요",
	]

	/// 경로 자체나 그 상위 폴더 중 하나가 보호 라이브러리면 그 이유.
	public static func reason(for path: String) -> String? {
		for component in PathUtil.normalize(path).split(separator: "/") {
			guard let dot = component.lastIndex(of: "."), dot != component.startIndex else { continue }
			let ext = component[component.index(after: dot)...].lowercased()
			if let reason = reasons[ext] { return reason }
		}
		return nil
	}
}
