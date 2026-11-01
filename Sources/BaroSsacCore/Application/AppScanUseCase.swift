import Foundation

public struct AppScanUseCase {
	private let catalog: AppCatalogPort
	private let fs: FileSystemPort
	private let clock: ClockPort
	private let home: String
	private let policy: SuggestionPolicy

	public init(
		catalog: AppCatalogPort,
		fs: FileSystemPort,
		clock: ClockPort,
		home: String,
		policy: SuggestionPolicy = .standard
	) {
		self.catalog = catalog
		self.fs = fs
		self.clock = clock
		self.home = home
		self.policy = policy
	}

	/// 설치된 앱과 그 앱이 남긴 파일. 관련 파일까지 합친 크기 내림차순.
	public func execute() -> [AppItem] {
		let staleCutoff = clock.now().addingTimeInterval(-Double(policy.staleAfterDays) * 86_400)
		return catalog.installedApps()
			.map { item(for: $0, staleCutoff: staleCutoff) }
			.sorted { $0.totalBytes > $1.totalBytes }
	}

	private func item(for app: InstalledApp, staleCutoff: Date) -> AppItem {
		if app.isBuiltIn {
			return AppItem(app: app, leftovers: [], suggestions: [], protectedReason: "macOS 기본 앱")
		}
		let leftovers = AppLeftovers.candidates(bundleID: app.bundleID, appName: app.name, home: home)
			.compactMap { candidate -> Leftover? in
				guard
					fs.exists(candidate.path),
					!fs.isSymlink(candidate.path),
					let st = try? fs.stat(candidate.path)
				else { return nil }
				return Leftover(path: candidate.path, sizeBytes: st.sizeBytes, match: candidate.match)
			}
		// 앱은 크기와 상관없이, 마지막 사용일을 알 때만 판단한다 (수정일은 업데이트 날짜라 의미가 없다).
		var suggestions: [Suggestion] = []
		if let lastUsed = app.lastUsedAt, lastUsed <= staleCutoff {
			suggestions.append(.stale(since: lastUsed))
		}
		return AppItem(app: app, leftovers: leftovers, suggestions: suggestions, protectedReason: nil)
	}
}
