// 도메인 모델: IO 비의존 순수 값 타입
import Foundation

public enum RiskLevel: String, Hashable, Sendable {
	case low      // 앱이 자동 재생성하는 데이터
	case medium   // 재생성 시간 소요 · 재다운로드 필요
	case high     // 사용자 데이터 가능성 (명시적 확인 필요)
}

public enum SkipReason: String, Hashable, Sendable {
	case notFound, symlink, tooRecent, permissionDenied, excluded
}

public enum Granularity: String, Hashable, Sendable {
	case root       // 루트 전체 = 항목 1개 (일관성 필요 캐시 DB)
	case children   // 루트 직계 자식 = 항목 1개씩 (앱별 캐시 폴더)
	case files      // 하위 파일 = 항목 1개씩 (나이 조건 파일 단위)
}

public struct CleanupRule: Hashable, Sendable {
	public let name: String
	public let root: String
	public let risk: RiskLevel
	public let minAgeDays: Int
	public let granularity: Granularity
	public let exclude: [String]      // 제외 glob 패턴 (루트 기준 상대 경로)
	public let title: String          // 목록 표시용 짧은 이름
	public let description: String    // 삭제 가능 근거 (한 줄)

	public init(
		name: String,
		root: String,
		risk: RiskLevel,
		minAgeDays: Int = 0,
		granularity: Granularity = .children,
		exclude: [String] = [],
		title: String = "",
		description: String = ""
	) {
		self.name = name
		self.root = root
		self.risk = risk
		self.minAgeDays = minAgeDays
		self.granularity = granularity
		self.exclude = exclude
		self.title = title
		self.description = description
	}
}

public struct ScanItem: Hashable, Sendable {
	public let ruleName: String
	public let path: String
	public let sizeBytes: Int64
	public let risk: RiskLevel
	/// 스캔 시점 사용 중인 앱 번들 ID (표시용) | 정리 가능 여부: 정리 시점 재판단
	public let inUseBy: String?

	public init(ruleName: String, path: String, sizeBytes: Int64, risk: RiskLevel, inUseBy: String? = nil) {
		self.ruleName = ruleName
		self.path = path
		self.sizeBytes = sizeBytes
		self.risk = risk
		self.inUseBy = inUseBy
	}

	public func marked(inUseBy owner: String?) -> ScanItem {
		ScanItem(ruleName: ruleName, path: path, sizeBytes: sizeBytes, risk: risk, inUseBy: owner)
	}
}

public struct SkippedItem: Hashable, Sendable {
	public let path: String
	public let reason: SkipReason

	public init(path: String, reason: SkipReason) {
		self.path = path
		self.reason = reason
	}
}

public struct ScanReport: Sendable {
	public var items: [ScanItem]
	public var skipped: [SkippedItem]

	public init(items: [ScanItem] = [], skipped: [SkippedItem] = []) {
		self.items = items
		self.skipped = skipped
	}

	public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

	public func bytesByRule() -> [String: Int64] {
		items.reduce(into: [:]) { $0[$1.ruleName, default: 0] += $1.sizeBytes }
	}

	public func largest(_ n: Int) -> [ScanItem] {
		Array(items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(n))
	}
}

public enum CleanOutcome: String, Hashable, Sendable {
	case wouldTrash
	case trashed
	case rejectedOutsideRules
	case needsConfirmation
	case stale       // 스캔 이후 삭제 · 심볼릭 링크로 변경
	case inUse       // 정리 시점 해당 앱 실행 중
	case protected   // 앱 관리 라이브러리 · macOS 기본 앱
	case failed
}

public struct CleanEntry: Hashable, Sendable {
	public let item: ScanItem
	public let outcome: CleanOutcome
	public let error: String

	public init(item: ScanItem, outcome: CleanOutcome, error: String = "") {
		self.item = item
		self.outcome = outcome
		self.error = error
	}
}

public struct CleanResult: Sendable {
	public let dryRun: Bool
	public let entries: [CleanEntry]

	public init(dryRun: Bool, entries: [CleanEntry]) {
		self.dryRun = dryRun
		self.entries = entries
	}

	public var freedBytes: Int64 {
		entries
			.filter { $0.outcome == .wouldTrash || $0.outcome == .trashed }
			.reduce(0) { $0 + $1.item.sizeBytes }
	}
}
