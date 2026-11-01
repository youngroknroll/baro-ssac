#if os(macOS)
import BaroSsacCore
import Foundation

/// 컴포지션 루트: 실제 어댑터를 유스케이스에 연결한다. UI는 여기서 만든 객체만 사용한다.
public struct AppContainer {
	public let home: String
	public let disk: DiskPort

	// 시스템 데이터(캐시 규칙)
	public let rules: [CleanupRule]
	public let scan: ScanUseCase
	public let clean: CleanUseCase

	// 사용자 파일
	public let fileScopes: [CategoryScope]
	public let fileScan: FileScanUseCase
	public let trashFiles: TrashFilesUseCase

	// 응용 프로그램
	public let appScan: AppScanUseCase
	public let trashApps: TrashFilesUseCase

	public init(
		home: String,
		disk: DiskPort,
		rules: [CleanupRule],
		scan: ScanUseCase,
		clean: CleanUseCase,
		fileScopes: [CategoryScope],
		fileScan: FileScanUseCase,
		trashFiles: TrashFilesUseCase,
		appScan: AppScanUseCase,
		trashApps: TrashFilesUseCase
	) {
		self.home = home
		self.disk = disk
		self.rules = rules
		self.scan = scan
		self.clean = clean
		self.fileScopes = fileScopes
		self.fileScan = fileScan
		self.trashFiles = trashFiles
		self.appScan = appScan
		self.trashApps = trashApps
	}

	/// 주의: 앱 샌드박스가 켜져 있으면 홈이 컨테이너 경로가 되어 아무것도 찾지 못한다.
	public static func live(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> AppContainer {
		let rules = DefaultRules.rules(home: home)
		let fs = LocalFileSystem()
		let trash = FinderTrash()
		let clock = SystemClock()
		let runningApps = WorkspaceRunningApps()
		let appRoots = ["/Applications", "\(home)/Applications"] + AppLeftovers.allowedRoots(home: home)
		return AppContainer(
			home: home,
			disk: LocalDisk(path: home),
			rules: rules,
			scan: ScanUseCase(fs: fs, clock: clock, runningApps: runningApps),
			clean: CleanUseCase(trash: trash, fs: fs, rules: rules, runningApps: runningApps),
			fileScopes: FileCategory.scopes(home: home),
			fileScan: FileScanUseCase(walker: LocalFileWalker(), hasher: SHA256ContentHash(), fs: fs, clock: clock),
			trashFiles: TrashFilesUseCase(trash: trash, fs: fs, allowedRoots: FileCategory.allRoots(home: home)),
			appScan: AppScanUseCase(catalog: LocalAppCatalog(home: home), fs: fs, clock: clock, home: home),
			trashApps: TrashFilesUseCase(trash: trash, fs: fs, allowedRoots: appRoots, runningApps: runningApps)
		)
	}
}
#endif
