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

internal struct FakeRunningApps: RunningAppsPort {
	let ids: Set<String>
	func runningBundleIdentifiers() -> Set<String> { ids }
}

/// root → 그 아래 파일 목록. 없는 root 를 물으면 permissionDenied (exists 확인은 FileSystemPort 몫).
internal struct FakeWalker: FileWalkerPort {
	let listings: [String: FileListing]

	func listFiles(under root: String, minSize: Int64) throws -> FileListing {
		guard let listing = listings[root] else { throw FileSystemError.permissionDenied(root) }
		return FileListing(
			records: listing.records.filter { $0.sizeBytes >= minSize },
			totalBytes: listing.totalBytes
		)
	}
}

/// 경로 → 내용. 표본 해시는 내용의 앞 3글자만 본다 (앞부분만 같은 파일을 2단계에서 걸러내는지 확인용).
internal final class FakeHasher: ContentHashPort {
	let contents: [String: String]
	private(set) var fullHashCount = 0

	init(_ contents: [String: String]) {
		self.contents = contents
	}

	func hash(of path: String, sampleOnly: Bool) throws -> String {
		guard let content = contents[path] else { throw FileSystemError.permissionDenied(path) }
		if sampleOnly { return String(content.prefix(3)) }
		fullHashCount += 1
		return content
	}
}

internal struct FakeCatalog: AppCatalogPort {
	let apps: [InstalledApp]
	func installedApps() -> [InstalledApp] { apps }
}

internal func fileRecord(
	_ path: String,
	_ size: Int64,
	modified: Date = epoch,
	lastUsed: Date? = nil,
	isPackage: Bool = false
) -> FileRecord {
	FileRecord(path: path, sizeBytes: size, modifiedAt: modified, lastUsedAt: lastUsed, isPackage: isPackage)
}

internal let megabyte: Int64 = 1024 * 1024

internal func days(_ n: Double) -> TimeInterval { n * 86_400 }
