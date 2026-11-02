#if os(macOS)
import Foundation
import BaroSsacCore
import BaroSsacMac

@MainActor
internal final class ScanViewModel: ObservableObject {
	@Published private(set) var presenter: Presenter
	/// 진행 상황 · 직전 결과 알림 (창 부제) | 빈 값이면 요약 표시
	@Published var status = ""
	@Published var isBusy = false
	@Published private(set) var hasScanned = false
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

	/// 도넛 가운데: 디스크 사용률 (요약 카드 큰 숫자와 중복 방지)
	var donutCenter: String {
		guard let disk = presenter.disk, disk.totalBytes > 0 else { return presenter.selectedText }
		return "\(Int((Double(disk.usedBytes) / Double(disk.totalBytes) * 100).rounded()))%"
	}

	var donutCaption: String { presenter.disk == nil ? centerCaption : "사용 중" }

	/// 요약 카드 행: 현재 남은 용량, 고른 항목 제거 시 남는 용량
	var heroFacts: [HeroFact] {
		guard let disk = presenter.disk else { return [] }
		var facts = [HeroFact(label: "현재 남은 용량", value: formatSize(disk.freeBytes))]
		if presenter.selectedBytes > 0 {
			facts.append(HeroFact(
				label: "고른 항목 제거 시",
				value: formatSize(disk.freeBytes + presenter.selectedBytes),
				emphasized: true
			))
		}
		return facts
	}

	var heroNotice: String? {
		hasReport && presenter.selectedBytes == 0 ? "제거할 항목을 선택하세요" : nil
	}

	var subtitle: String {
		if !status.isEmpty { return status }
		guard hasScanned else { return "캐시 · 로그 · 개발 도구 파일" }
		return hasReport ? "\(presenter.groups().count)가지 종류 · \(presenter.totalText)" : "정리할 파일 없음"
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
		status = "살펴보는 중…"
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let report = container.scan.execute(container.rules) { done, total, rule in
				Task { @MainActor in
					self?.status = "살펴보는 중 \(done)/\(total) · \(rule.title)"
				}
			}
			await MainActor.run { self?.finishScan(report) }
		}
	}

	private func finishScan(_ report: ScanReport) {
		presenter.load(report)
		presenter.setDisk(container.disk.usage())
		let denied = report.skipped.filter { $0.reason == .permissionDenied }.count
		status = denied > 0 ? "권한 없음으로 건너뛴 위치 \(denied)곳" : ""
		if let notice = cleanNotice {
			status = notice
			cleanNotice = nil
		}
		hasScanned = true
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
		status = "휴지통으로 옮기는 중…"
		let items = presenter.selectedItems()
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let result = container.clean.execute(items, dryRun: false, confirmedPaths: Set(confirmed))
			await MainActor.run { self?.finishClean(result) }
		}
	}

	private func finishClean(_ result: CleanResult) {
		failures = result.entries.filter { $0.outcome == .failed }
		var text = "휴지통으로 이동 \(formatSize(result.freedBytes)) · 휴지통 비우기 후 공간 확보"
		let inUse = result.entries.filter { $0.outcome == .inUse }.count
		if inUse > 0 {
			text += " · 실행 중 앱 항목 \(inUse)개 건너뜀"
		}
		// 결과 알림: 재스캔 종료 후 표시 (재스캔이 상태 문구를 덮어씀)
		cleanNotice = text
		isBusy = false
		scan()
	}
}
#endif
