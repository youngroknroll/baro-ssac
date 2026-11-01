// 사용자 파일·앱 관리에 필요한 포트.
import Foundation

public struct FileListing: Sendable {
	/// minSize 이상인 파일과 패키지.
	public var records: [FileRecord]
	/// 작은 파일까지 포함한 전체 크기.
	public var totalBytes: Int64

	public init(records: [FileRecord] = [], totalBytes: Int64 = 0) {
		self.records = records
		self.totalBytes = totalBytes
	}
}

public protocol FileWalkerPort {
	/// root 아래를 재귀로 훑는다. 숨김 파일과 심볼릭 링크는 건너뛰고, 패키지는 안으로 들어가지 않고 하나로 센다.
	/// minSize 미만 파일은 totalBytes 에만 더한다. root 를 읽을 수 없으면 FileSystemError.permissionDenied.
	func listFiles(under root: String, minSize: Int64) throws -> FileListing
}

public protocol ContentHashPort {
	/// 내용 해시. sampleOnly 면 앞·뒤 일부와 크기만으로 만든 빠른 해시 (같으면 전체 해시로 다시 확인한다).
	func hash(of path: String, sampleOnly: Bool) throws -> String
}

public protocol AppCatalogPort {
	/// /Applications 와 ~/Applications 의 앱.
	func installedApps() -> [InstalledApp]
}
