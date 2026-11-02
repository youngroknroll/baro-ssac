import Foundation

public struct CleanUseCase {
	private let trash: TrashPort
	private let fs: FileSystemPort
	private let rules: [String: CleanupRule]
	private let runningApps: RunningAppsPort?

	public init(trash: TrashPort, fs: FileSystemPort, rules: [CleanupRule], runningApps: RunningAppsPort? = nil) {
		self.trash = trash
		self.fs = fs
		self.rules = Dictionary(uniqueKeysWithValues: rules.map { ($0.name, $0) })
		self.runningApps = runningApps
	}

	public func execute(
		_ items: [ScanItem],
		dryRun: Bool = true,
		confirmedPaths: Set<String> = []
	) -> CleanResult {
		let confirmed = Set(confirmedPaths.map(PathUtil.normalize))
		// 실행 중 판단 기준: 정리 시점 조회 (스캔 결과 inUseBy 미사용)
		let running = runningApps?.runningBundleIdentifiers() ?? []
		let entries = items.map { cleanOne($0, dryRun: dryRun, confirmed: confirmed, running: running) }
		return CleanResult(dryRun: dryRun, entries: entries)
	}

	/// 허용 위치 검사 (정규화 경로) | ROOT 세분성: 루트 자체만 · 그 외: 루트 하위만
	private static func isAllowedTarget(_ path: String, rule: CleanupRule) -> Bool {
		if rule.granularity == .root {
			return PathUtil.normalize(path) == PathUtil.normalize(rule.root)
		}
		return PathUtil.isStrictlyInside(path, root: rule.root)
	}

	private func cleanOne(
		_ item: ScanItem,
		dryRun: Bool,
		confirmed: Set<String>,
		running: Set<String>
	) -> CleanEntry {
		guard let rule = rules[item.ruleName], Self.isAllowedTarget(item.path, rule: rule) else {
			return CleanEntry(item: item, outcome: .rejectedOutsideRules)
		}
		let path = PathUtil.normalize(item.path)
		// 위험도 출처: 규칙 (아이템 값 미사용 · 위조 방지)
		if rule.risk == .high && !confirmed.contains(path) {
			return CleanEntry(item: item, outcome: .needsConfirmation)
		}
		if AppMatching.owner(of: path, running: running) != nil {
			return CleanEntry(item: item, outcome: .inUse)
		}
		if dryRun {
			return CleanEntry(item: item, outcome: .wouldTrash)
		}
		// 정리 직전 재확인: 스캔 이후 상태 변경 대비
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
