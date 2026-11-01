#if os(macOS)
import Foundation
import BaroSsacCore
import BaroSsacMac

@MainActor
internal final class ScanViewModel: ObservableObject {
	@Published private(set) var presenter: Presenter
	@Published var status = "스캔을 누르면 정리할 수 있는 데이터를 찾습니다"
	@Published var isBusy = false
	@Published var pendingConfirmation: [String]? = nil
	@Published var failures: [CleanEntry] = []

	private let container: AppContainer
	private var cleanNotice: String?

	init(container: AppContainer) {
		self.container = container
		var p = Presenter(rules: container.rules)
		p.setDisk(container.disk.usage())
		presenter = p
	}

	// MARK: 화면용 조회

	var groups: [GroupRow] { presenter.groups() }
	var segments: [ChartSegment] { presenter.chartSegments() }
	var hasReport: Bool { !presenter.groups().isEmpty }
	var canClean: Bool { !isBusy && presenter.selectedBytes > 0 }
	var selectedCount: Int { presenter.selectedItems().count }
	var centerCaption: String { presenter.selectedBytes > 0 ? "선택" : "" }

	var diskText: String {
		guard let disk = presenter.disk else { return "" }
		var text = "디스크 \(formatSize(disk.totalBytes)) · 여유 \(formatSize(disk.freeBytes))"
		if presenter.selectedBytes > 0 {
			text += " → 비우면 \(formatSize(disk.freeBytes + presenter.selectedBytes))"
		}
		return text
	}

	// MARK: 선택

	func setItem(_ path: String, _ on: Bool) {
		presenter.setItemSelected(path, on)
	}

	func setGroup(_ name: String, _ on: Bool) {
		presenter.setGroupSelected(name, on)
	}

	// MARK: 스캔

	func scan() {
		isBusy = true
		status = "스캔 중…"
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let report = container.scan.execute(container.rules) { done, total, rule in
				Task { @MainActor in
					self?.status = "스캔 중 (\(done)/\(total)) · \(rule.title)"
				}
			}
			await MainActor.run { self?.finishScan(report) }
		}
	}

	private func finishScan(_ report: ScanReport) {
		presenter.load(report)
		presenter.setDisk(container.disk.usage())
		let denied = report.skipped.filter { $0.reason == .permissionDenied }.count
		if presenter.groups().isEmpty {
			status = "정리할 데이터가 없습니다"
		} else if denied > 0 {
			status = "확보 가능 · 권한이 없어 건너뛴 항목 \(denied)개"
		} else {
			status = "확보 가능"
		}
		if let notice = cleanNotice {
			status = notice
			cleanNotice = nil
		}
		isBusy = false
	}

	// MARK: 정리

	func requestClean() {
		let high = presenter.highRiskSelectedPaths()
		if high.isEmpty {
			performClean(confirmed: [])
		} else {
			pendingConfirmation = high
		}
	}

	func performClean(confirmed: [String]) {
		pendingConfirmation = nil
		isBusy = true
		status = "휴지통으로 보내는 중…"
		let items = presenter.selectedItems()
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let result = container.clean.execute(items, dryRun: false, confirmedPaths: Set(confirmed))
			await MainActor.run { self?.finishClean(result) }
		}
	}

	private func finishClean(_ result: CleanResult) {
		failures = result.entries.filter { $0.outcome == .failed }
		var text = "\(formatSize(result.freedBytes)) 를 휴지통으로 보냈습니다 · 비우면 공간이 확보됩니다"
		let inUse = result.entries.filter { $0.outcome == .inUse }.count
		if inUse > 0 {
			text += " · 실행 중이라 건너뛴 항목 \(inUse)개"
		}
		// 바로 이어지는 재스캔이 상태 문구를 덮어쓰므로, 재스캔이 끝난 뒤에 보여 준다.
		cleanNotice = text
		isBusy = false
		scan()
	}
}
#endif
