// 포트: 유스케이스 → 외부 인터페이스
import Foundation

public struct EntryStat: Hashable, Sendable {
	public let sizeBytes: Int64       // 하위 트리 전체 실제 디스크 사용량
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
	/// 직계 자식 경로 | 권한 없음: FileSystemError.permissionDenied
	func listChildren(_ path: String) throws -> [String]
	/// 심볼릭 링크 미추적 | 권한 없음: FileSystemError.permissionDenied
	func stat(_ path: String) throws -> EntryStat
	/// 심볼릭 링크: false | 하위 트리 미순회 (경량 질의)
	func isDirectory(_ path: String) -> Bool
	/// 하위 트리 미순회 (경량 질의)
	func isSymlink(_ path: String) -> Bool
}

public protocol TrashPort {
	func moveToTrash(_ path: String) throws
}

public protocol RunningAppsPort {
	/// 실행 중 앱 번들 ID | 호출마다 새로 조회
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
