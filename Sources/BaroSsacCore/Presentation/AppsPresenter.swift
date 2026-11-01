import Foundation

public struct AppRow: Hashable, Identifiable {
	public let path: String
	public let name: String
	public let totalBytes: Int64
	public let leftoverCount: Int
	public let reasons: [String]
	public let protectedReason: String?

	public var id: String { path }
	public var sizeText: String { formatSize(totalBytes) }
}

public struct LeftoverRow: Hashable, Identifiable {
	public let path: String
	public let display: String
	public let sizeBytes: Int64
	public let match: LeftoverMatch
	public let isSelected: Bool

	public var id: String { path }
	public var sizeText: String { formatSize(sizeBytes) }
	public var matchText: String {
		switch match {
		case .bundleID: "이 앱의 파일"
		case .appName: "이름이 같음 · 확인 필요"
		}
	}
}

public struct AppsPresenter {
	private let home: String
	public private(set) var items: [AppItem] = []
	public private(set) var isLoaded = false
	/// 앱 경로 → 함께 지울 관련 파일 경로.
	private var leftoverSelection: [String: Set<String>] = [:]

	public init(home: String) {
		self.home = home
	}

	public mutating func load(_ items: [AppItem]) {
		self.items = items
		isLoaded = true
		// 번들 ID 로 찾은 파일은 그 앱의 것이 확실하므로 기본 선택. 이름으로 찾은 파일은 사용자가 확인한다.
		leftoverSelection = Dictionary(uniqueKeysWithValues: items.map { item in
			(item.app.path, Set(item.leftovers.filter { $0.match == .bundleID }.map(\.path)))
		})
	}

	public var totalBytes: Int64 { items.reduce(0) { $0 + $1.totalBytes } }

	public func rows(mode: FileListMode, now: Date) -> [AppRow] {
		let shown = mode == .suggested ? items.filter { !$0.suggestions.isEmpty && !$0.isProtected } : items
		return shown
			.sorted { $0.totalBytes > $1.totalBytes }
			.map { item in
				AppRow(
					path: item.app.path,
					name: item.app.name,
					totalBytes: item.totalBytes,
					leftoverCount: item.leftovers.count,
					reasons: item.suggestions.map { SuggestionText.describe($0, now: now) },
					protectedReason: item.protectedReason
				)
			}
	}

	public func item(_ appPath: String) -> AppItem? {
		items.first { $0.app.path == appPath }
	}

	public func leftoverRows(for appPath: String) -> [LeftoverRow] {
		guard let item = item(appPath) else { return [] }
		let chosen = leftoverSelection[appPath] ?? []
		return item.leftovers.map { leftover in
			LeftoverRow(
				path: leftover.path,
				display: HomePath.display(leftover.path, home: home),
				sizeBytes: leftover.sizeBytes,
				match: leftover.match,
				isSelected: chosen.contains(leftover.path)
			)
		}
	}

	public mutating func setLeftover(_ path: String, of appPath: String, _ on: Bool) {
		guard let item = item(appPath), item.leftovers.contains(where: { $0.path == path }) else { return }
		if on {
			leftoverSelection[appPath, default: []].insert(path)
		} else {
			leftoverSelection[appPath, default: []].remove(path)
		}
	}

	/// 앱 번들 + 고른 관련 파일. 보호된 앱이면 빈 목록.
	public func uninstallRequests(for appPath: String) -> [TrashRequest] {
		guard let item = item(appPath), !item.isProtected else { return [] }
		let chosen = leftoverSelection[appPath] ?? []
		let app = TrashRequest(path: item.app.path, sizeBytes: item.app.sizeBytes, bundleID: item.app.bundleID)
		let leftovers = item.leftovers
			.filter { chosen.contains($0.path) }
			.map { TrashRequest(path: $0.path, sizeBytes: $0.sizeBytes) }
		return [app] + leftovers
	}

	public func uninstallBytes(for appPath: String) -> Int64 {
		uninstallRequests(for: appPath).reduce(0) { $0 + $1.sizeBytes }
	}
}
