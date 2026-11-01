#if os(macOS)
import BaroSsacCore
import BaroSsacMac
import Foundation

/// 문서·사진·음악·동영상·다운로드 화면이 함께 쓰는 상태. 스캔은 다섯 카테고리를 한 번에 한다
/// (중복은 카테고리를 넘나들기 때문).
@MainActor
internal final class FilesViewModel: ObservableObject {
	@Published private(set) var presenter: FilesPresenter
	@Published var mode: FileListMode = .suggested
	@Published var status = "스캔을 누르면 문서·사진·음악·동영상·다운로드 폴더를 살펴봅니다"
	@Published var isBusy = false
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

	func summaryText(_ category: FileCategory) -> String {
		guard presenter.hasReport else { return "" }
		let total = formatSize(presenter.totalBytes(category))
		let count = presenter.suggestedCount(category)
		guard count > 0 else { return "전체 \(total) · 정리 추천 없음" }
		return "전체 \(total) · 정리 추천 \(count)개 \(formatSize(presenter.suggestedBytes(category)))"
	}

	func selectionText(_ category: FileCategory) -> String {
		"\(presenter.selectedItems(in: category).count)개 선택 · \(formatSize(presenter.selectedBytes(in: category)))"
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
					self?.status = "살펴보는 중 (\(done)/\(total)) · \(category.title)"
				}
			}
			await MainActor.run { self?.finishScan(report) }
		}
	}

	private func finishScan(_ report: FileReport) {
		presenter.load(report)
		let denied = report.skipped.filter { $0.reason == .permissionDenied }.count
		status = denied > 0 ? "권한이 없어 건너뛴 폴더 \(denied)개" : ""
		if let notice {
			status = notice
			self.notice = nil
		}
		isBusy = false
	}

	// MARK: 중복 파일

	func duplicateGroups() -> [DuplicateGroup] {
		presenter.duplicateGroups(now: Date())
	}

	var duplicateSummaryText: String {
		guard presenter.hasReport else { return "" }
		let groups = presenter.duplicateGroups(now: Date()).count
		guard groups > 0 else { return "중복 파일 없음" }
		return "묶음 \(groups)개 · 사본을 지우면 \(formatSize(presenter.duplicateReclaimableBytes)) 확보"
	}

	var duplicateSelectionText: String {
		let items = presenter.selectedDuplicateItems()
		return "\(items.count)개 선택 · \(formatSize(items.reduce(0) { $0 + $1.sizeBytes }))"
	}

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
		var text = "\(items.count)개 · \(size)\n\n\(names)\(more)\n\n휴지통을 비우기 전까지는 되돌릴 수 있습니다."
		let unsafe = presenter.duplicateGroupsEmptied(by: Set(items.map(\.path)))
		if unsafe > 0 {
			text = "⚠️ 원본과 사본을 모두 고른 중복 묶음이 \(unsafe)개 있습니다. 이대로 지우면 그 내용이 하나도 남지 않습니다.\n\n" + text
		}
		return text
	}

	func performTrash() {
		guard let target = pendingTrash else { return }
		pendingTrash = nil
		isBusy = true
		status = "휴지통으로 보내는 중…"
		let requests = selectedItems(target).map { TrashRequest(path: $0.path, sizeBytes: $0.sizeBytes) }
		let container = self.container
		Task.detached(priority: .userInitiated) { [weak self] in
			let result = container.trashFiles.execute(requests, dryRun: false)
			await MainActor.run { self?.finishTrash(result) }
		}
	}

	private func finishTrash(_ result: TrashResult) {
		failures = result.entries.filter { $0.outcome == .failed }
		var text = "\(formatSize(result.freedBytes)) 를 휴지통으로 보냈습니다"
		let skipped = result.count(.protected) + result.count(.stale) + result.count(.rejectedOutsideRules)
		if skipped > 0 {
			text += " · 건너뛴 항목 \(skipped)개"
		}
		// 중복 판단이 바뀌므로 다시 스캔한다. 재스캔이 끝난 뒤 이 문구를 보여 준다.
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

/// 휴지통 확인 창을 띄운 화면: 한 카테고리이거나 중복 파일 탭.
internal enum TrashTarget: Hashable {
	case category(FileCategory)
	case duplicates
}
#endif
