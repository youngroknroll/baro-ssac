// 포트: 유스케이스가 바깥 세계에 요구하는 인터페이스.
import Foundation

public struct EntryStat: Hashable, Sendable {
	public let sizeBytes: Int64       // 하위 트리 전체의 실제 디스크 사용량
	public let modifiedAt: Date
	public let isSymlink: Bool

	public init(sizeBytes: Int64, modifiedAt: Date, isSymlink: Bool) {
		self.sizeBytes = sizeBytes
		self.modifiedAt = modifiedAt
		self.isSymlink = isSymlink
	}
}

public enum FileSystemError: Error, Equatable {
	case permissionDenied(String)
}

public protocol FileSystemPort {
	func exists(_ path: String) -> Bool
	/// 직계 자식 경로. 권한이 없으면 FileSystemError.permissionDenied.
	func listChildren(_ path: String) throws -> [String]
	/// 심볼릭 링크를 따라가지 않는다. 권한이 없으면 FileSystemError.permissionDenied.
	func stat(_ path: String) throws -> EntryStat
	/// 심볼릭 링크는 false. 하위 트리를 걷지 않는 가벼운 질의.
	func isDirectory(_ path: String) -> Bool
	/// 하위 트리를 걷지 않는 가벼운 질의.
	func isSymlink(_ path: String) -> Bool
}

public protocol TrashPort {
	func moveToTrash(_ path: String) throws
}

public protocol RunningAppsPort {
	/// 지금 실행 중인 앱들의 번들 ID. 호출할 때마다 새로 조회한다.
	func runningBundleIdentifiers() -> Set<String>
}

public protocol ClockPort {
	func now() -> Date
}

public struct DiskUsage: Hashable, Sendable {
	public let totalBytes: Int64
	public let freeBytes: Int64

	public init(totalBytes: Int64, freeBytes: Int64) {
		self.totalBytes = totalBytes
		self.freeBytes = freeBytes
	}

	public var usedBytes: Int64 { totalBytes - freeBytes }
}

public protocol DiskPort {
	func usage() -> DiskUsage?
}
