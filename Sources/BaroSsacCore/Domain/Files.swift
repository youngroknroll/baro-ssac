// 사용자 파일 도메인 (문서 · 사진 · 음악 · 동영상 · 다운로드) | 위치 = 소재지만 의미
// 삭제 여부: 사용 이력 · 내용 기반 제안만 | 결정: 사용자
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

	/// 휴지통 유스케이스 허용 위치: 전 카테고리 폴더
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
	/// Spotlight 마지막 사용일 | 열어 본 적 없음: nil
	public let lastUsedAt: Date?
	/// 패키지 여부 (Finder 가 파일 1개로 표시하는 디렉터리 · 예: .app · .key · .photoslibrary)
	public let isPackage: Bool

	public init(path: String, sizeBytes: Int64, modifiedAt: Date, lastUsedAt: Date?, isPackage: Bool) {
		self.path = path
		self.sizeBytes = sizeBytes
		self.modifiedAt = modifiedAt
		self.lastUsedAt = lastUsedAt
		self.isPackage = isPackage
	}

	public var name: String { PathUtil.basename(path) }

	/// 소문자 확장자 | 없음 · 숨김 파일 이름(.env): 빈 문자열
	public var fileExtension: String {
		guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
		return String(name[name.index(after: dot)...]).lowercased()
	}

	/// 마지막 사용일 · 없으면 수정일
	public var lastTouchedAt: Date { lastUsedAt ?? modifiedAt }
}

public enum Suggestion: Hashable, Sendable {
	/// 내용 동일 사본 존재 | `keep`: 원본(유지) 경로
	case duplicate(keep: String)
	/// 다운로드 폴더 설치 파일 (.dmg · .pkg 등) | 설치 후 불필요
	case installer
	/// 대용량 · 장기 미사용 | `since`: 마지막 사용(없으면 수정) 시각
	case stale(since: Date)
}

public struct FileItem: Hashable, Sendable, Identifiable {
	public let record: FileRecord
	public let category: FileCategory
	public let suggestions: [Suggestion]
	/// 삭제 불가 사유 (앱 관리 라이브러리) | nil: 삭제 가능
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
	/// 폴더 전체 크기 (목록 제외 작은 파일 포함)
	public let totalBytes: Int64
	/// 목록 항목 | 정렬: 크기 내림차순
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
	/// 목록 최소 크기 | 미만: 합계에만 합산 (작은 파일 대량 시 목록 부하 방지)
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
	/// 앱 관리 라이브러리 → 사유 | 일부 삭제 시 라이브러리 손상 · 해당 앱에서 정리
	public static let reasons: [String: String] = [
		"photoslibrary": "사진 앱에서 관리",
		"photolibrary": "사진 앱에서 관리",
		"musiclibrary": "음악 앱에서 관리",
		"tvlibrary": "TV 앱에서 관리",
		"imovielibrary": "iMovie에서 관리",
		"fcpbundle": "Final Cut Pro에서 관리",
	]

	/// 반환: 경로 자체 또는 상위 폴더가 보호 라이브러리면 사유
	public static func reason(for path: String) -> String? {
		for component in PathUtil.normalize(path).split(separator: "/") {
			guard let dot = component.lastIndex(of: "."), dot != component.startIndex else { continue }
			let ext = component[component.index(after: dot)...].lowercased()
			if let reason = reasons[ext] { return reason }
		}
		return nil
	}
}
