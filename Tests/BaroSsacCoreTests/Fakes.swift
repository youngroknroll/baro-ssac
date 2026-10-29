// 테스트 더블: 포트를 메모리 위에서 구현한다.
import Foundation
@testable import BaroSsacCore

internal let epoch = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01T00:00:00Z

/// files: [경로: 바이트 크기]. 디렉터리는 파일 경로로부터 유추된다.
internal struct InMemoryFileSystem: FileSystemPort {
	private let files: [String: Int64]
	private let mtimes: [String: Date]
	private let symlinks: Set<String>
	private let denied: Set<String>

	init(
		_ files: [String: Int64],
		mtimes: [String: Date] = [:],
		symlinks: Set<String> = [],
		denied: Set<String> = []
	) {
		self.files = files
		self.mtimes = mtimes
		self.symlinks = symlinks
		self.denied = denied
	}

	private func isAncestor(_ dir: String, of path: String) -> Bool {
		path.hasPrefix(dir + "/")
	}

	func exists(_ path: String) -> Bool {
		symlinks.contains(path) || files.keys.contains { $0 == path || isAncestor(path, of: $0) }
	}

	func listChildren(_ path: String) throws -> [String] {
		try check(path)
		var children = Set<String>()
		for entry in Array(files.keys) + Array(symlinks) where isAncestor(path, of: entry) {
			let rest = entry.dropFirst(path.count + 1)
			guard let first = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first else {
				continue
			}
			children.insert(path + "/" + String(first))
		}
		return children.sorted()
	}

	func stat(_ path: String) throws -> EntryStat {
		try check(path)
		if symlinks.contains(path) {
			return EntryStat(sizeBytes: 0, modifiedAt: epoch, isSymlink: true)
		}
		let size = files
			.filter { $0.key == path || isAncestor(path, of: $0.key) }
			.values
			.reduce(0, +)
		return EntryStat(sizeBytes: size, modifiedAt: mtimes[path] ?? epoch, isSymlink: false)
	}

	func isDirectory(_ path: String) -> Bool {
		!symlinks.contains(path) && files.keys.contains { isAncestor(path, of: $0) }
	}

	func isSymlink(_ path: String) -> Bool {
		symlinks.contains(path)
	}

	private func check(_ path: String) throws {
		if denied.contains(path) { throw FileSystemError.permissionDenied(path) }
	}
}

internal struct FixedClock: ClockPort {
	let fixed: Date
	func now() -> Date { fixed }
}

internal struct TrashError: LocalizedError {
	let path: String
	var errorDescription: String? { "cannot trash \(path)" }
}

/// 호출을 기록해야 하므로 참조 타입이 필요하다.
internal final class SpyTrash: TrashPort {
	private(set) var trashed: [String] = []
	private let failOn: Set<String>

	init(failOn: Set<String> = []) {
		self.failOn = failOn
	}

	func moveToTrash(_ path: String) throws {
		if failOn.contains(path) { throw TrashError(path: path) }
		trashed.append(path)
	}
}

internal struct FakeDisk: DiskPort {
	let total: Int64
	let free: Int64
	func usage() -> DiskUsage? { DiskUsage(totalBytes: total, freeBytes: free) }
}

internal func days(_ n: Double) -> TimeInterval { n * 86_400 }
