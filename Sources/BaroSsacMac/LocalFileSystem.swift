#if os(macOS)
import Darwin
import Foundation
import BaroSsacCore

/// FileSystemPort의 실제 구현. 심볼릭 링크는 절대 따라가지 않는다.
public struct LocalFileSystem: FileSystemPort {
	private let fm = FileManager.default

	public init() {}

	public func exists(_ path: String) -> Bool {
		var st = Darwin.stat()
		return lstat(path, &st) == 0
	}

	public func listChildren(_ path: String) throws -> [String] {
		do {
			return try fm.contentsOfDirectory(atPath: path).map { path + "/" + $0 }
		} catch {
			if Self.isPermissionError(error) { throw FileSystemError.permissionDenied(path) }
			throw error
		}
	}

	public func isDirectory(_ path: String) -> Bool {
		var st = Darwin.stat()
		guard lstat(path, &st) == 0 else { return false }
		return (st.st_mode & S_IFMT) == S_IFDIR
	}

	public func isSymlink(_ path: String) -> Bool {
		var st = Darwin.stat()
		guard lstat(path, &st) == 0 else { return false }
		return (st.st_mode & S_IFMT) == S_IFLNK
	}

	public func stat(_ path: String) throws -> EntryStat {
		var top = Darwin.stat()
		guard lstat(path, &top) == 0 else {
			if errno == EACCES || errno == EPERM { throw FileSystemError.permissionDenied(path) }
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
		}
		if (top.st_mode & S_IFMT) == S_IFLNK {
			return EntryStat(sizeBytes: 0, modifiedAt: Self.mtime(top), isSymlink: true)
		}

		var seen = Set<InodeKey>()
		var size = Self.allocated(top, &seen)
		var newest = top.st_mtimespec.tv_sec

		if (top.st_mode & S_IFMT) == S_IFDIR {
			// 최상위 디렉터리를 못 읽으면 permissionDenied 를 그대로 올린다 (포트 계약).
			// 그 아래의 읽을 수 없는 폴더는 건너뛴다.
			var stack = [path]
			var first = true
			while let dir = stack.popLast() {
				let names: [String]
				do {
					names = try fm.contentsOfDirectory(atPath: dir)
				} catch {
					if first { throw FileSystemError.permissionDenied(path) }
					continue
				}
				first = false
				for name in names {
					let child = dir + "/" + name
					var st = Darwin.stat()
					guard lstat(child, &st) == 0 else { continue }
					size += Self.allocated(st, &seen)
					newest = max(newest, st.st_mtimespec.tv_sec)
					if (st.st_mode & S_IFMT) == S_IFDIR { stack.append(child) }
				}
			}
		}
		return EntryStat(sizeBytes: size, modifiedAt: Date(timeIntervalSince1970: TimeInterval(newest)), isSymlink: false)
	}

	// MARK: - helpers

	private struct InodeKey: Hashable {
		let dev: dev_t
		let ino: ino_t
	}

	/// 하드링크는 한 번만 센다. 논리 크기가 아닌 실제 할당 블록 기준.
	private static func allocated(_ st: Darwin.stat, _ seen: inout Set<InodeKey>) -> Int64 {
		let key = InodeKey(dev: st.st_dev, ino: st.st_ino)
		if seen.contains(key) { return 0 }
		seen.insert(key)
		let blocks = Int64(st.st_blocks) * 512
		return blocks > 0 ? blocks : Int64(st.st_size)
	}

	private static func mtime(_ st: Darwin.stat) -> Date {
		Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
	}

	private static func isPermissionError(_ error: Error) -> Bool {
		let e = error as NSError
		if e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoPermissionError { return true }
		if e.domain == NSPOSIXErrorDomain && (e.code == Int(EACCES) || e.code == Int(EPERM)) { return true }
		if let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError {
			return underlying.domain == NSPOSIXErrorDomain && (underlying.code == Int(EACCES) || underlying.code == Int(EPERM))
		}
		return false
	}
}
#endif
