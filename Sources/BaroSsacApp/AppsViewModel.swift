#if os(macOS)
import BaroSsacCore
import BaroSsacMac
import Foundation

@MainActor
internal final class AppsViewModel: ObservableObject {
	@Published private(set) var presenter: AppsPresenter
	@Published var mode: FileListMode = .all
	@Published var status = "스캔을 누르면 설치된 앱과 앱이 남긴 파일을 찾습니다"
	@Published var isBusy = false
	/// 삭제 확인 창에 띄운 앱의 경로.
	@Published var uninstalling: String?
	@Published var failures: [TrashEntry] = []

	private let container: AppContainer
	private var notice: String?

	init(container: AppContainer) {
		self.container = container
		presenter = AppsPresenter(home: container.home)
	}

	var rows: [AppRow] { presenter.rows(mode: mode, now: Date()) }

	var summaryText: String {
		guard presenter.isLoaded else { return "" }
		let suggested = presenter.rows(mode: .suggested, now: Date()).count
		let total = formatSize(presenter.totalBytes)
		return "앱 \(presenter.items.count)개 · 관련 파일 포함 \(total) · 1년 넘게 안 쓴 앱 \(suggested)개"
	}

	// MARK: 스캔

	func scan() {
		isBusy = true
		status = "앱을 살펴보는 중…"
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let items = container.appScan.execute()
			await MainActor.run { self?.finishScan(items) }
		}
	}

	private func finishScan(_ items: [AppItem]) {
		presenter.load(items)
		status = notice ?? ""
		notice = nil
		isBusy = false
	}

	// MARK: 삭제

	func setLeftover(_ path: String, of appPath: String, _ on: Bool) {
		presenter.setLeftover(path, of: appPath, on)
	}

	func requestUninstall(_ appPath: String) {
		uninstalling = appPath
	}

	func performUninstall() {
		guard let appPath = uninstalling else { return }
		uninstalling = nil
		isBusy = true
		status = "휴지통으로 보내는 중…"
		let requests = presenter.uninstallRequests(for: appPath)
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let result = container.trashApps.execute(requests, dryRun: false)
			await MainActor.run { self?.finishUninstall(result) }
		}
	}

	private func finishUninstall(_ result: TrashResult) {
		failures = result.entries.filter { $0.outcome == .failed }
		if result.count(.inUse) > 0 {
			notice = "앱이 실행 중이라 지우지 않았습니다. 앱을 종료한 뒤 다시 시도하세요"
		} else {
			notice = "\(formatSize(result.freedBytes)) 를 휴지통으로 보냈습니다"
		}
		isBusy = false
		scan()
	}
}
#endif
