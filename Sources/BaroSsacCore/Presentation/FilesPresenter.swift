// 사용자 파일 · 앱 화면 상태와 표시 규칙 (UI 프레임워크 비의존)
import Foundation

public enum FileListMode: String, CaseIterable, Hashable, Sendable {
	case suggested
	case all

	public var title: String {
		switch self {
		case .suggested: "정리 추천"
		case .all: "전체 (크기순)"
		}
	}
}

public enum SuggestionText {
	public static func describe(_ suggestion: Suggestion, now: Date) -> String {
		switch suggestion {
		case let .duplicate(keep):
			return "중복 · 원본 \(PathUtil.basename(keep))"
		case .installer:
			return "설치 파일"
		case let .stale(since):
			let days = max(Int(now.timeIntervalSince(since) / 86_400), 0)
			if days >= 365 { return "\(days / 365)년 넘게 안 열었음" }
			if days >= 30 { return "\(days / 30)개월 넘게 안 열었음" }
			return "\(days)일 동안 안 열었음"
		}
	}
}

/// 홈 폴더 → `~` 축약 표시
public enum HomePath {
	public static func display(_ path: String, home: String) -> String {
		let p = PathUtil.normalize(path)
		let h = PathUtil.normalize(home)
		if p == h { return "~" }
		if p.hasPrefix(h + "/") { return "~" + String(p.dropFirst(h.count)) }
		return path
	}

	public static func parent(of path: String) -> String {
		let normalized = PathUtil.normalize(path)
		guard let slash = normalized.lastIndex(of: "/"), slash != normalized.startIndex else { return "/" }
		return String(normalized[..<slash])
	}
}

public struct FileRow: Hashable, Identifiable {
	public let path: String
	public let name: String
	public let folder: String
	public let sizeBytes: Int64
	public let reasons: [String]
	public let protectedReason: String?

	public var id: String { path }
	public var sizeText: String { formatSize(sizeBytes) }
}

/// 중복 묶음: 원본 1개(유지) + 사본(삭제 후보)
public struct DuplicateGroup: Hashable, Identifiable {
	public let keeper: FileRow
	public let copies: [FileRow]
	/// 사본 전체 삭제 시 확보 용량
	public let reclaimableBytes: Int64

	public var id: String { keeper.path }
	public var sizeText: String { keeper.sizeText }
	public var reclaimableText: String { formatSize(reclaimableBytes) }
}

public struct FilesPresenter {
	private let home: String
	public private(set) var report: FileReport?
	private var selected: Set<String> = []

	public init(home: String) {
		self.home = home
	}

	// MARK: 로드

	public mutating func load(_ report: FileReport) {
		self.report = report
		// 사용자 파일 기본 선택 없음 (추천 있어도) | 결정: 사용자
		selected = []
	}

	public var hasReport: Bool { report != nil }

	// MARK: 조회

	public func totalBytes(_ category: FileCategory) -> Int64 {
		report?.summary(for: category)?.totalBytes ?? 0
	}

	public func suggestedBytes(_ category: FileCategory) -> Int64 {
		report?.summary(for: category)?.suggestedBytes ?? 0
	}

	public func suggestedCount(_ category: FileCategory) -> Int {
		items(category).filter(\.isSuggested).count
	}

	public func rows(_ category: FileCategory, mode: FileListMode, now: Date) -> [FileRow] {
		let shown = mode == .suggested ? items(category).filter(\.isSuggested) : items(category)
		return shown
			.sorted { $0.sizeBytes > $1.sizeBytes }
			.map { row($0, now: now) }
	}

	public func isSelected(_ path: String) -> Bool { selected.contains(path) }

	public func selectedItems(in category: FileCategory) -> [FileItem] {
		items(category).filter { selected.contains($0.path) }
	}

	public func selectedBytes(in category: FileCategory) -> Int64 {
		selectedItems(in: category).reduce(0) { $0 + $1.sizeBytes }
	}

	public func trashRequests(in category: FileCategory) -> [TrashRequest] {
		selectedItems(in: category).map { TrashRequest(path: $0.path, sizeBytes: $0.sizeBytes) }
	}

	// MARK: 선택 변경

	public mutating func setSelected(_ path: String, _ on: Bool) {
		guard let item = allItems().first(where: { $0.path == path }), !item.isProtected else { return }
		if on { selected.insert(path) } else { selected.remove(path) }
	}

	public mutating func selectAllSuggested(in category: FileCategory) {
		for item in items(category) where item.isSuggested {
			selected.insert(item.path)
		}
	}

	public mutating func clearSelection(in category: FileCategory) {
		for item in items(category) {
			selected.remove(item.path)
		}
	}

	// MARK: 중복 파일

	/// 원본 · 사본 묶음 | 정렬: 확보 용량 내림차순
	public func duplicateGroups(now: Date) -> [DuplicateGroup] {
		duplicateMembers()
			.map { member in
				DuplicateGroup(
					keeper: row(member.keeper, now: now),
					copies: member.copies.map { row($0, now: now) },
					reclaimableBytes: member.copies.reduce(0) { $0 + $1.sizeBytes }
				)
			}
			.sorted {
				$0.reclaimableBytes != $1.reclaimableBytes
					? $0.reclaimableBytes > $1.reclaimableBytes
					: $0.keeper.path < $1.keeper.path
			}
	}

	public var duplicateReclaimableBytes: Int64 {
		duplicateMembers().reduce(0) { total, member in
			total + member.copies.reduce(0) { $0 + $1.sizeBytes }
		}
	}

	/// 사본만 선택 (원본 유지)
	public mutating func selectAllDuplicateCopies() {
		for member in duplicateMembers() {
			for copy in member.copies where !copy.isProtected {
				selected.insert(copy.path)
			}
		}
	}

	public mutating func clearDuplicateSelection() {
		for member in duplicateMembers() {
			selected.remove(member.keeper.path)
			for copy in member.copies {
				selected.remove(copy.path)
			}
		}
	}

	/// 중복 묶음 항목(원본 포함) 중 선택분
	public func selectedDuplicateItems() -> [FileItem] {
		duplicateMembers()
			.flatMap { [$0.keeper] + $0.copies }
			.filter { selected.contains($0.path) }
	}

	public func duplicateTrashRequests() -> [TrashRequest] {
		selectedDuplicateItems().map { TrashRequest(path: $0.path, sizeBytes: $0.sizeBytes) }
	}

	/// 원본 · 사본 전부 선택된 묶음 수 (삭제 시 내용 전부 소실)
	public func fullySelectedDuplicateGroups() -> Int {
		duplicateGroupsEmptied(by: selected)
	}

	/// `paths` 삭제 시 원본 · 사본 전부 사라지는 묶음 수
	public func duplicateGroupsEmptied(by paths: Set<String>) -> Int {
		duplicateMembers().filter { member in
			([member.keeper] + member.copies).allSatisfy { paths.contains($0.path) }
		}.count
	}

	// MARK: -

	private struct DuplicateMember {
		let keeper: FileItem
		let copies: [FileItem]
	}

	/// 묶음 구성: 사본의 `.duplicate(keep:)` 기준 | 정렬: 사본 경로순 · 묶음 원본 경로순
	private func duplicateMembers() -> [DuplicateMember] {
		let all = allItems()
		let byPath = Dictionary(all.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
		var copiesByKeeper: [String: [FileItem]] = [:]
		for item in all {
			for case let .duplicate(keep) in item.suggestions {
				copiesByKeeper[keep, default: []].append(item)
			}
		}
		return copiesByKeeper
			.compactMap { keep, copies -> DuplicateMember? in
				guard let keeper = byPath[keep] else { return nil }
				return DuplicateMember(keeper: keeper, copies: copies.sorted { $0.path < $1.path })
			}
			.sorted { $0.keeper.path < $1.keeper.path }
	}

	private func row(_ item: FileItem, now: Date) -> FileRow {
		FileRow(
			path: item.path,
			name: item.record.name,
			folder: HomePath.display(HomePath.parent(of: item.path), home: home),
			sizeBytes: item.sizeBytes,
			reasons: item.suggestions.map { SuggestionText.describe($0, now: now) },
			protectedReason: item.protectedReason
		)
	}

	private func items(_ category: FileCategory) -> [FileItem] {
		report?.summary(for: category)?.items ?? []
	}

	private func allItems() -> [FileItem] {
		report?.summaries.flatMap(\.items) ?? []
	}
}
