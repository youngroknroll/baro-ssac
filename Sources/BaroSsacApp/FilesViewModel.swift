#if os(macOS)
import BaroSsacCore
import BaroSsacMac
import Foundation

/// 파일 화면 공통 상태 (문서 · 사진 · 음악 · 동영상 · 다운로드 · 중복)
/// 스캔: 다섯 카테고리 일괄 (중복 판단이 카테고리 간에 걸침)
@MainActor
internal final class FilesViewModel: ObservableObject {
	@Published private(set) var presenter: FilesPresenter
	@Published var mode: FileListMode = .suggested
	/// 진행 상황 · 직전 결과 알림 (창 부제) | 빈 값이면 요약 표시
	@Published var status = ""
	@Published var isBusy = false
	@Published private(set) var hasScanned = false
	@Published var pendingTrash: TrashTarget?
	@Published var failures: [TrashEntry] = []

	private let container: AppContainer
	private var notice: String?

	init(container: AppContainer) {
		self.container = container
		presenter = FilesPresenter(home: container.home)
	}

	// MARK: 화면용 조회

	func rows(_ category: FileCategory) -> [FileRow] {
		presenter.rows(category, mode: mode, now: Date())
	}

	func subtitle(_ category: FileCategory) -> String {
		if !status.isEmpty { return status }
		guard hasScanned else { return category.roots(home: "~").joined(separator: ", ") }
		return "전체 \(formatSize(presenter.totalBytes(category)))"
	}

	/// 요약 카드 행: 폴더 전체, 추천 항목 수, 고른 항목 크기
	func heroFacts(_ category: FileCategory) -> [HeroFact] {
		var facts = [
			HeroFact(label: "폴더 전체", value: formatSize(presenter.totalBytes(category))),
			HeroFact(label: "추천 항목", value: "\(presenter.suggestedCount(category))개"),
		]
		let selected = presenter.selectedBytes(in: category)
		if selected > 0 {
			facts.append(HeroFact(label: "고른 항목", value: formatSize(selected), emphasized: true))
		}
		return facts
	}

	func heroNotice(_ category: FileCategory) -> String? {
		if presenter.suggestedCount(category) == 0 && mode == .suggested { return "정리 추천 없음" }
		return selectedCount(category) == 0 ? "제거할 항목을 선택하세요" : nil
	}

	/// 폴더 전체 대비 정리 추천 비율
	func suggestedFraction(_ category: FileCategory) -> Double {
		let total = presenter.totalBytes(category)
		return total > 0 ? Double(presenter.suggestedBytes(category)) / Double(total) : 0
	}

	func selectedCount(_ category: FileCategory) -> Int {
		presenter.selectedItems(in: category).count
	}

	func canTrash(_ category: FileCategory) -> Bool {
		!isBusy && !presenter.selectedItems(in: category).isEmpty
	}

	// MARK: 선택

	func setSelected(_ path: String, _ on: Bool) { presenter.setSelected(path, on) }
	func selectAllSuggested(_ category: FileCategory) { presenter.selectAllSuggested(in: category) }
	func clearSelection(_ category: FileCategory) { presenter.clearSelection(in: category) }

	// MARK: 스캔

	func scan() {
		isBusy = true
		status = "살펴보는 중…"
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let report = container.fileScan.execute(container.fileScopes) { done, total, category in
				Task { @MainActor in
					self?.status = "살펴보는 중 \(done)/\(total) · \(category.title)"
				}
			}
			await MainActor.run { self?.finishScan(report) }
		}
	}

	private func finishScan(_ report: FileReport) {
		presenter.load(report)
		let denied = report.skipped.filter { $0.reason == .permissionDenied }.count
		status = denied > 0 ? "권한 없음으로 건너뛴 위치 \(denied)곳" : ""
		if let notice {
			status = notice
			self.notice = nil
		}
		hasScanned = true
		isBusy = false
	}

	// MARK: 중복 파일

	func duplicateGroups() -> [DuplicateGroup] {
		presenter.duplicateGroups(now: Date())
	}

	var duplicateSubtitle: String {
		if !status.isEmpty { return status }
		guard hasScanned else { return "문서 · 사진 · 음악 · 동영상 · 다운로드" }
		return "묶음 \(presenter.duplicateGroups(now: Date()).count)개"
	}

	/// 요약 카드 행: 중복 묶음 수, 원본 유지 규칙, 고른 항목 크기
	var duplicateHeroFacts: [HeroFact] {
		var facts = [
			HeroFact(label: "중복 묶음", value: "\(presenter.duplicateGroups(now: Date()).count)개"),
			HeroFact(label: "원본", value: "묶음마다 1개 유지"),
		]
		if selectedDuplicateBytes > 0 {
			facts.append(HeroFact(label: "고른 항목", value: formatSize(selectedDuplicateBytes), emphasized: true))
		}
		return facts
	}

	var duplicateHeroNotice: String? {
		if presenter.duplicateGroups(now: Date()).isEmpty { return "중복 파일 없음" }
		return selectedDuplicateCount == 0 ? "제거할 항목을 선택하세요" : nil
	}

	var selectedDuplicateCount: Int { presenter.selectedDuplicateItems().count }
	var selectedDuplicateBytes: Int64 { presenter.selectedDuplicateItems().reduce(0) { $0 + $1.sizeBytes } }

	var canTrashDuplicates: Bool {
		!isBusy && !presenter.selectedDuplicateItems().isEmpty
	}

	func selectAllDuplicateCopies() { presenter.selectAllDuplicateCopies() }
	func clearDuplicateSelection() { presenter.clearDuplicateSelection() }

	// MARK: 휴지통

	func requestTrash(_ target: TrashTarget) {
		pendingTrash = target
	}

	func confirmationText(_ target: TrashTarget) -> String {
		let items = selectedItems(target)
		let names = items.prefix(8).map(\.record.name).joined(separator: "\n")
		let more = items.count > 8 ? "\n외 \(items.count - 8)개" : ""
		let size = formatSize(items.reduce(0) { $0 + $1.sizeBytes })
		var text = "용량 \(size)\n복구: 휴지통 비우기 전까지 가능\n\n\(names)\(more)"
		let unsafe = presenter.duplicateGroupsEmptied(by: Set(items.map(\.path)))
		if unsafe > 0 {
			text = "⚠ 원본 · 사본 모두 선택된 묶음 \(unsafe)개 · 제거 시 해당 내용 전부 삭제\n\n" + text
		}
		return text
	}

	func confirmationTitle(_ target: TrashTarget) -> String {
		"휴지통으로 이동 \(selectedItems(target).count)개"
	}

	func performTrash() {
		guard let target = pendingTrash else { return }
		pendingTrash = nil
		isBusy = true
		status = "휴지통으로 옮기는 중…"
		let requests = selectedItems(target).map { TrashRequest(path: $0.path, sizeBytes: $0.sizeBytes) }
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let result = container.trashFiles.execute(requests, dryRun: false)
			await MainActor.run { self?.finishTrash(result) }
		}
	}

	private func finishTrash(_ result: TrashResult) {
		failures = result.entries.filter { $0.outcome == .failed }
		var text = "휴지통으로 이동 \(formatSize(result.freedBytes))"
		let skipped = result.count(.protected) + result.count(.stale) + result.count(.rejectedOutsideRules)
		if skipped > 0 {
			text += " · 건너뜀 \(skipped)개"
		}
		// 재스캔: 중복 판단 갱신 | 결과 알림은 재스캔 종료 후 표시
		notice = text
		isBusy = false
		scan()
	}

	private func selectedItems(_ target: TrashTarget) -> [FileItem] {
		switch target {
		case let .category(category): presenter.selectedItems(in: category)
		case .duplicates: presenter.selectedDuplicateItems()
		}
	}
}

/// 휴지통 확인 대상 화면: 카테고리 하나 또는 중복 파일 탭
internal enum TrashTarget: Hashable {
	case category(FileCategory)
	case duplicates
}
#endif
