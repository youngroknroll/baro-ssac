// 도메인 모델: IO에 의존하지 않는 순수 값 타입.
import Foundation

public enum RiskLevel: String, Hashable, Sendable {
	case low      // 앱이 자동으로 다시 만드는 데이터
	case medium   // 재생성에 시간이 들거나 다시 내려받아야 함
	case high     // 사용자 데이터일 수 있음 (명시적 확인 필요)
}

public enum SkipReason: String, Hashable, Sendable {
	case notFound, symlink, tooRecent, permissionDenied, excluded
}

public enum Granularity: String, Hashable, Sendable {
	case root       // 루트를 통째로 하나의 항목으로 (일관성이 필요한 캐시 DB)
	case children   // 루트의 직계 자식마다 하나의 항목으로 (앱별 캐시 폴더)
	case files      // 재귀적으로 파일마다 하나의 항목으로 (나이 조건을 파일 단위로)
}

public struct CleanupRule: Hashable, Sendable {
	public let name: String
	public let root: String
	public let risk: RiskLevel
	public let minAgeDays: Int
	public let granularity: Granularity
	public let exclude: [String]      // 루트 기준 상대 경로에 대한 glob 패턴
	public let title: String          // 목록에 보이는 짧은 이름
	public let description: String    // 왜 지워도 되는지 한 줄 설명

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

	public init(ruleName: String, path: String, sizeBytes: Int64, risk: RiskLevel) {
		self.ruleName = ruleName
		self.path = path
		self.sizeBytes = sizeBytes
		self.risk = risk
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
	case stale       // 스캔 이후 사라졌거나 심볼릭 링크로 바뀜
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
