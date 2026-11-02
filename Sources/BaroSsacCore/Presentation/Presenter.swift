// 화면 상태와 표시 규칙 (UI 프레임워크 비의존 · 단위 테스트 대상)
import Foundation

private let units = ["B", "KB", "MB", "GB", "TB"]

public func formatSize(_ n: Int64) -> String {
	var value = Double(n)
	var unit = 0
	while value >= 1024 && unit < units.count - 1 {
		value /= 1024
		unit += 1
	}
	if unit == 0 { return "\(Int(value)) B" }
	var text = String(format: "%.2f", value)
	while text.hasSuffix("0") { text.removeLast() }
	if text.hasSuffix(".") { text.removeLast() }
	if !text.contains(".") { text += ".0" }
	return "\(text) \(units[unit])"
}

/// 차트 색 이름 (Core 는 이름만 · 실제 색은 화면에서 시스템 색으로 변환)
/// (시스템 색 → 다크 모드 자동 대응)
public enum ChartColors {
	/// 종류별 조각 색 | 배정: 용량순 (큰 조각 = 앞쪽 색)
	public static let palette = [
		"blue", "purple", "pink", "orange", "teal", "indigo",
		"mint", "cyan", "yellow", "brown", "green",
	]
	public static let other = "other"
	public static let free = "free"
}

public struct ChildRow: Hashable, Identifiable {
	public let path: String
	public let label: String
	public let sizeBytes: Int64
	public let inUseBy: String?
	public var id: String { path }
	public var sizeText: String { formatSize(sizeBytes) }
}

public struct GroupRow: Hashable, Identifiable {
	public let name: String
	public let title: String
	public let risk: RiskLevel
	public let sizeBytes: Int64
	public let color: String
	public let description: String
	public let children: [ChildRow]
	public var id: String { name }
	public var sizeText: String { formatSize(sizeBytes) }
}

public struct ChartSegment: Hashable, Identifiable {
	public let key: String
	public let label: String
	public let bytes: Int64
	public let color: String
	public var id: String { key }
}

public enum GroupState { case none, partial, all }

public struct Presenter {
	private let rules: [String: CleanupRule]
	private var items: [ScanItem] = []           // 스캔 순서 유지
	private var byPath: [String: ScanItem] = [:]
	private var selected: Set<String> = []
	public private(set) var disk: DiskUsage?

	public init(rules: [CleanupRule]) {
		self.rules = Dictionary(uniqueKeysWithValues: rules.map { ($0.name, $0) })
	}

	// MARK: 로드

	public mutating func load(_ report: ScanReport) {
		// 0바이트 항목 제외 (삭제해도 확보 공간 없음)
		items = report.items.filter { $0.sizeBytes > 0 }
		byPath = Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0) })
		// 기본 선택: LOW · MEDIUM | 제외: HIGH · 실행 중 앱 항목 (사용자 직접 선택)
		selected = Set(items.filter { $0.risk != .high && $0.inUseBy == nil }.map { $0.path })
	}

	public mutating func setDisk(_ usage: DiskUsage?) {
		disk = usage
	}

	// MARK: 조회

	public func groups() -> [GroupRow] {
		var order: [String] = []
		var byRule: [String: [ScanItem]] = [:]
		for item in items {
			if byRule[item.ruleName] == nil { order.append(item.ruleName) }
			byRule[item.ruleName, default: []].append(item)
		}
		let unsorted: [(name: String, rule: CleanupRule, items: [ScanItem])] = order.compactMap { name in
			guard let rule = rules[name], let its = byRule[name] else { return nil }
			return (name, rule, its.sorted { $0.sizeBytes > $1.sizeBytes })
		}
		let sorted = unsorted.sorted { lhs, rhs in
			lhs.items.reduce(0) { $0 + $1.sizeBytes } > rhs.items.reduce(0) { $0 + $1.sizeBytes }
		}
		return sorted.enumerated().map { index, g in
			GroupRow(
				name: g.name,
				title: g.rule.title.isEmpty ? g.name : g.rule.title,
				risk: g.rule.risk,
				sizeBytes: g.items.reduce(0) { $0 + $1.sizeBytes },
				color: ChartColors.palette[index % ChartColors.palette.count],
				description: g.rule.description,
				children: g.items.map {
					ChildRow(
						path: $0.path,
						label: PathUtil.basename($0.path),
						sizeBytes: $0.sizeBytes,
						inUseBy: $0.inUseBy
					)
				}
			)
		}
	}

	/// 원 전체 = 디스크 총 용량 | 조각 순서: 종류별 → 그 외 사용 중 → 여유 공간
	public func chartSegments() -> [ChartSegment] {
		var segs = groups().map { ChartSegment(key: $0.name, label: $0.title, bytes: $0.sizeBytes, color: $0.color) }
		guard let disk else { return segs }
		let cleanable = segs.reduce(0) { $0 + $1.bytes }
		let other = max(disk.usedBytes - cleanable, 0)
		segs.append(ChartSegment(key: "other", label: "그 외 사용 중", bytes: other, color: ChartColors.other))
		segs.append(ChartSegment(key: "free", label: "여유 공간", bytes: disk.freeBytes, color: ChartColors.free))
		return segs
	}

	public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
	public var totalText: String { formatSize(totalBytes) }

	public func isSelected(_ path: String) -> Bool { selected.contains(path) }

	public var selectedBytes: Int64 {
		items.filter { selected.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
	}
	public var selectedText: String { formatSize(selectedBytes) }

	public func selectedItems() -> [ScanItem] {
		items.filter { selected.contains($0.path) }
	}

	public func highRiskSelectedPaths() -> [String] {
		selectedItems().filter { $0.risk == .high }.map { $0.path }
	}

	public func groupState(_ name: String) -> GroupState {
		let paths = items.filter { $0.ruleName == name }.map { $0.path }
		let chosen = paths.filter { selected.contains($0) }.count
		if chosen == 0 { return .none }
		return chosen == paths.count ? .all : .partial
	}

	// MARK: 선택 변경

	public mutating func setItemSelected(_ path: String, _ on: Bool) {
		guard byPath[path] != nil else { return }
		if on { selected.insert(path) } else { selected.remove(path) }
	}

	public mutating func setGroupSelected(_ name: String, _ on: Bool) {
		for item in items where item.ruleName == name {
			setItemSelected(item.path, on)
		}
	}
}
