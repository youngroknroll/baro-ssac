#if os(macOS)
import Foundation
import BaroSsacCore

/// 컴포지션 루트: 실제 어댑터를 유스케이스에 연결한다. UI는 여기서 만든 객체만 사용한다.
public struct AppContainer {
	public let rules: [CleanupRule]
	public let scan: ScanUseCase
	public let clean: CleanUseCase
	public let disk: DiskPort

	public init(rules: [CleanupRule], scan: ScanUseCase, clean: CleanUseCase, disk: DiskPort) {
		self.rules = rules
		self.scan = scan
		self.clean = clean
		self.disk = disk
	}

	/// 주의: 앱 샌드박스가 켜져 있으면 홈이 컨테이너 경로가 되어 아무것도 찾지 못한다.
	public static func live(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> AppContainer {
		let rules = DefaultRules.rules(home: home)
		let fs = LocalFileSystem()
		return AppContainer(
			rules: rules,
			scan: ScanUseCase(fs: fs, clock: SystemClock()),
			clean: CleanUseCase(trash: FinderTrash(), fs: fs, rules: rules),
			disk: LocalDisk(path: home)
		)
	}
}
#endif
