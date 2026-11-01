// 사용자가 고른 파일·앱을 휴지통으로 보낸다. 캐시 정리(CleanUseCase)와 같은 원칙을 '경로 목록'에 적용한다.
import Foundation

public struct TrashRequest: Hashable, Sendable {
	public let path: String
	public let sizeBytes: Int64
	/// 앱 번들이면 그 번들 ID. 실행 중인지, macOS 기본 앱인지 확인하는 데 쓴다.
	public let bundleID: String?

	public init(path: String, sizeBytes: Int64, bundleID: String? = nil) {
		self.path = path
		self.sizeBytes = sizeBytes
		self.bundleID = bundleID
	}
}

public struct TrashEntry: Hashable, Sendable {
	public let request: TrashRequest
	public let outcome: CleanOutcome
	public let error: String

	public init(request: TrashRequest, outcome: CleanOutcome, error: String = "") {
		self.request = request
		self.outcome = outcome
		self.error = error
	}
}

public struct TrashResult: Sendable {
	public let dryRun: Bool
	public let entries: [TrashEntry]

	public init(dryRun: Bool, entries: [TrashEntry]) {
		self.dryRun = dryRun
		self.entries = entries
	}

	public var freedBytes: Int64 {
		entries
			.filter { $0.outcome == .wouldTrash || $0.outcome == .trashed }
			.reduce(0) { $0 + $1.request.sizeBytes }
	}

	public func count(_ outcome: CleanOutcome) -> Int {
		entries.filter { $0.outcome == outcome }.count
	}
}

public struct TrashFilesUseCase {
	private let trash: TrashPort
	private let fs: FileSystemPort
	private let allowedRoots: [String]
	private let runningApps: RunningAppsPort?

	public init(trash: TrashPort, fs: FileSystemPort, allowedRoots: [String], runningApps: RunningAppsPort? = nil) {
		self.trash = trash
		self.fs = fs
		self.allowedRoots = allowedRoots
		self.runningApps = runningApps
	}

	public func execute(_ requests: [TrashRequest], dryRun: Bool = true) -> TrashResult {
		let running = runningApps?.runningBundleIdentifiers() ?? []
		return TrashResult(dryRun: dryRun, entries: requests.map { trashOne($0, dryRun: dryRun, running: running) })
	}

	private func trashOne(_ request: TrashRequest, dryRun: Bool, running: Set<String>) -> TrashEntry {
		let path = PathUtil.normalize(request.path)
		guard allowedRoots.contains(where: { PathUtil.isStrictlyInside(path, root: $0) }) else {
			return TrashEntry(request: request, outcome: .rejectedOutsideRules)
		}
		if ProtectedPackages.reason(for: path) != nil || (request.bundleID?.hasPrefix("com.apple.") ?? false) {
			return TrashEntry(request: request, outcome: .protected)
		}
		if let id = request.bundleID, running.contains(id) {
			return TrashEntry(request: request, outcome: .inUse)
		}
		if dryRun {
			return TrashEntry(request: request, outcome: .wouldTrash)
		}
		// 고른 뒤에 상태가 바뀌었을 수 있으므로 보내기 직전에 다시 확인한다
		if !fs.exists(path) || fs.isSymlink(path) {
			return TrashEntry(request: request, outcome: .stale)
		}
		do {
			try trash.moveToTrash(path)
		} catch {
			return TrashEntry(request: request, outcome: .failed, error: Self.describe(error))
		}
		return TrashEntry(request: request, outcome: .trashed)
	}

	private static func describe(_ error: Error) -> String {
		if let localized = error as? LocalizedError, let text = localized.errorDescription {
			return text
		}
		return "\(error)"
	}
}
