// 사용자 파일 · 앱 관리 포트
import Foundation

public struct FileListing: Sendable {
	/// minSize 이상 파일 · 패키지
	public var records: [FileRecord]
	/// 전체 크기 (작은 파일 포함)
	public var totalBytes: Int64

	public init(records: [FileRecord] = [], totalBytes: Int64 = 0) {
		self.records = records
		self.totalBytes = totalBytes
	}
}

public protocol FileWalkerPort {
	/// root 하위 재귀 순회 | 제외: 숨김 파일 · 심볼릭 링크 | 패키지: 내부 미진입 · 1개로 집계
	/// minSize 미만: totalBytes 에만 합산 | root 읽기 불가: FileSystemError.permissionDenied
	func listFiles(under root: String, minSize: Int64) throws -> FileListing
}

public protocol ContentHashPort {
	/// 내용 해시 | sampleOnly: 앞 · 뒤 일부 + 크기 기반 빠른 해시 (일치 시 전체 해시로 재확인)
	func hash(of path: String, sampleOnly: Bool) throws -> String
}

public protocol AppCatalogPort {
	/// 대상: /Applications · ~/Applications
	func installedApps() -> [InstalledApp]
}
