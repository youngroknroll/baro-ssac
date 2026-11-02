#if os(macOS)
import BaroSsacCore
import BaroSsacMac
import Foundation

@MainActor
internal final class AppsViewModel: ObservableObject {
	@Published private(set) var presenter: AppsPresenter
	@Published var mode: FileListMode = .all
	/// 진행 상황 · 직전 결과 알림 (창 부제) | 빈 값이면 요약 표시
	@Published var status = ""
	@Published var isBusy = false
	/// 삭제 확인 시트 대상 앱 경로
	@Published var uninstalling: String?
	@Published var failures: [TrashEntry] = []

	private let container: AppContainer
	private var notice: String?

	init(container: AppContainer) {
		self.container = container
		presenter = AppsPresenter(home: container.home)
	}

	var rows: [AppRow] { presenter.rows(mode: mode, now: Date()) }

	var subtitle: String {
		if !status.isEmpty { return status }
		guard presenter.isLoaded else { return "/Applications, ~/Applications" }
		return "앱 \(presenter.items.count)개"
	}

	private var unusedRows: [AppRow] { presenter.rows(mode: .suggested, now: Date()) }

	var heroValue: String { formatSize(unusedRows.reduce(0) { $0 + $1.totalBytes }) }

	/// 요약 카드 행: 미사용 앱 수, 전체 앱 수 · 크기(관련 파일 포함)
	var heroFacts: [HeroFact] {
		[
			HeroFact(label: "1년 넘게 미사용", value: "\(unusedRows.count)개"),
			HeroFact(label: "전체 앱", value: "\(presenter.items.count)개 · \(formatSize(presenter.totalBytes))"),
		]
	}

	var unusedFraction: Double {
		let total = presenter.totalBytes
		return total > 0 ? Double(unusedRows.reduce(0) { $0 + $1.totalBytes }) / Double(total) : 0
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
		status = "휴지통으로 옮기는 중…"
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
			notice = "실행 중인 앱 · 삭제 안 함 · 앱 종료 후 다시 시도"
		} else {
			notice = "휴지통으로 이동 \(formatSize(result.freedBytes))"
		}
		isBusy = false
		scan()
	}
}
#endif
