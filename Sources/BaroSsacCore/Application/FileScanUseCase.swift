import Foundation

public typealias FileScanProgress = (_ done: Int, _ total: Int, _ category: FileCategory) -> Void

public struct FileScanUseCase {
	private let walker: FileWalkerPort
	private let hasher: ContentHashPort
	private let fs: FileSystemPort
	private let clock: ClockPort
	private let policy: SuggestionPolicy

	public init(
		walker: FileWalkerPort,
		hasher: ContentHashPort,
		fs: FileSystemPort,
		clock: ClockPort,
		policy: SuggestionPolicy = .standard
	) {
		self.walker = walker
		self.hasher = hasher
		self.fs = fs
		self.clock = clock
		self.policy = policy
	}

	public func execute(_ scopes: [CategoryScope], onProgress: FileScanProgress? = nil) -> FileReport {
		var skipped: [SkippedItem] = []
		var collected: [Collected] = []

		for (index, scope) in scopes.enumerated() {
			var total: Int64 = 0
			var records: [FileRecord] = []
			for root in scope.roots {
				guard fs.exists(root) else {
					skipped.append(SkippedItem(path: root, reason: .notFound))
					continue
				}
				do {
					let listing = try walker.listFiles(under: root, minSize: policy.listMinBytes)
					total += listing.totalBytes
					records += listing.records
				} catch {
					skipped.append(SkippedItem(path: root, reason: .permissionDenied))
				}
			}
			collected.append(Collected(scope: scope, totalBytes: total, records: records))
			onProgress?(index + 1, scopes.count, scope.category)
		}

		// 중복은 카테고리를 넘나든다 (다운로드에 받은 사본과 문서의 원본).
		let downloadsRoots = scopes.filter { $0.category == .downloads }.flatMap(\.roots)
		let keepers = duplicateKeepers(in: collected.flatMap { $0.records }, downloadsRoots: downloadsRoots)
		let now = clock.now()

		let summaries = collected.map { entry in
			let items = entry.records
				.map { item(for: $0, category: entry.scope.category, keepers: keepers, now: now) }
				.sorted { $0.sizeBytes > $1.sizeBytes }
			return CategorySummary(category: entry.scope.category, totalBytes: entry.totalBytes, items: items)
		}
		return FileReport(summaries: summaries, skipped: skipped)
	}

	private struct Collected {
		let scope: CategoryScope
		let totalBytes: Int64
		let records: [FileRecord]
	}

	private func item(
		for record: FileRecord,
		category: FileCategory,
		keepers: [String: String],
		now: Date
	) -> FileItem {
		if let reason = ProtectedPackages.reason(for: record.path) {
			return FileItem(record: record, category: category, suggestions: [], protectedReason: reason)
		}
		var suggestions: [Suggestion] = []
		if let keep = keepers[record.path] {
			suggestions.append(.duplicate(keep: keep))
		}
		if category == .downloads && SuggestionPolicy.installerExtensions.contains(record.fileExtension) {
			suggestions.append(.installer)
		}
		let staleCutoff = now.addingTimeInterval(-Double(policy.staleAfterDays) * 86_400)
		if record.sizeBytes >= policy.staleMinBytes && record.lastTouchedAt <= staleCutoff {
			suggestions.append(.stale(since: record.lastTouchedAt))
		}
		return FileItem(record: record, category: category, suggestions: suggestions, protectedReason: nil)
	}

	// MARK: - 중복

	/// 중복 사본의 경로 → 남길 사본의 경로. 남길 사본 자신은 들어 있지 않다.
	/// 비싼 순서대로 걸러낸다: 크기 → 앞·뒤 표본 해시 → 전체 해시.
	private func duplicateKeepers(in records: [FileRecord], downloadsRoots: [String]) -> [String: String] {
		let candidates = records.filter {
			!$0.isPackage && $0.sizeBytes >= policy.duplicateMinBytes && ProtectedPackages.reason(for: $0.path) == nil
		}
		var result: [String: String] = [:]
		for sameSize in groups(of: candidates, by: { String($0.sizeBytes) }) {
			for sameSample in groups(of: sameSize, by: { try? hasher.hash(of: $0.path, sampleOnly: true) }) {
				for sameContent in groups(of: sameSample, by: { try? hasher.hash(of: $0.path, sampleOnly: false) }) {
					let ordered = sameContent.sorted { keepOrder($0, $1, downloadsRoots: downloadsRoots) }
					guard let keeper = ordered.first else { continue }
					for copy in ordered.dropFirst() {
						result[copy.path] = keeper.path
					}
				}
			}
		}
		return result
	}

	/// 키가 같은 것끼리 묶어, 둘 이상인 묶음만 돌려준다. 키를 구하지 못한(nil) 항목은 버린다.
	private func groups(of records: [FileRecord], by key: (FileRecord) -> String?) -> [[FileRecord]] {
		guard records.count >= 2 else { return [] }
		var buckets: [String: [FileRecord]] = [:]
		for record in records {
			guard let k = key(record) else { continue }
			buckets[k, default: []].append(record)
		}
		return buckets.values.filter { $0.count >= 2 }
	}

	/// 남길 사본 고르기: 다운로드 폴더 밖 → 더 오래된 것 → 경로 순.
	private func keepOrder(_ a: FileRecord, _ b: FileRecord, downloadsRoots: [String]) -> Bool {
		let aInDownloads = downloadsRoots.contains { PathUtil.isStrictlyInside(a.path, root: $0) }
		let bInDownloads = downloadsRoots.contains { PathUtil.isStrictlyInside(b.path, root: $0) }
		if aInDownloads != bInDownloads { return !aInDownloads }
		if a.modifiedAt != b.modifiedAt { return a.modifiedAt < b.modifiedAt }
		return a.path < b.path
	}
}
