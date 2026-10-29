import Foundation

public struct CleanUseCase {
	private let trash: TrashPort
	private let fs: FileSystemPort
	private let rules: [String: CleanupRule]

	public init(trash: TrashPort, fs: FileSystemPort, rules: [CleanupRule]) {
		self.trash = trash
		self.fs = fs
		self.rules = Dictionary(uniqueKeysWithValues: rules.map { ($0.name, $0) })
	}

	public func execute(
		_ items: [ScanItem],
		dryRun: Bool = true,
		confirmedPaths: Set<String> = []
	) -> CleanResult {
		let confirmed = Set(confirmedPaths.map(PathUtil.normalize))
		return CleanResult(dryRun: dryRun, entries: items.map { cleanOne($0, dryRun: dryRun, confirmed: confirmed) })
	}

	/// 정규화한 경로가 규칙이 허용하는 위치인지. ROOT 세분성은 루트 자체만, 그 외는 루트의 '하위'만.
	private static func isAllowedTarget(_ path: String, rule: CleanupRule) -> Bool {
		if rule.granularity == .root {
			return PathUtil.normalize(path) == PathUtil.normalize(rule.root)
		}
		return PathUtil.isStrictlyInside(path, root: rule.root)
	}

	private func cleanOne(_ item: ScanItem, dryRun: Bool, confirmed: Set<String>) -> CleanEntry {
		guard let rule = rules[item.ruleName], Self.isAllowedTarget(item.path, rule: rule) else {
			return CleanEntry(item: item, outcome: .rejectedOutsideRules)
		}
		let path = PathUtil.normalize(item.path)
		// 위험도는 아이템이 아니라 규칙에서 가져온다 (위조 방지)
		if rule.risk == .high && !confirmed.contains(path) {
			return CleanEntry(item: item, outcome: .needsConfirmation)
		}
		if dryRun {
			return CleanEntry(item: item, outcome: .wouldTrash)
		}
		// 스캔 이후 상태가 바뀌었을 수 있으므로 정리 직전에 다시 확인한다
		if !fs.exists(path) || fs.isSymlink(path) {
			return CleanEntry(item: item, outcome: .stale)
		}
		do {
			try trash.moveToTrash(path)
		} catch {
			return CleanEntry(item: item, outcome: .failed, error: Self.describe(error))
		}
		return CleanEntry(item: item, outcome: .trashed)
	}

	private static func describe(_ error: Error) -> String {
		if let localized = error as? LocalizedError, let text = localized.errorDescription {
			return text
		}
		return "\(error)"
	}
}
