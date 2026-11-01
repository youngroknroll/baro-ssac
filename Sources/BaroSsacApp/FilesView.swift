#if os(macOS)
import BaroSsacCore
import SwiftUI

/// 문서·사진·음악·동영상·다운로드 중 한 카테고리.
internal struct FilesView: View {
	let category: FileCategory
	@ObservedObject var model: FilesViewModel

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			header
			if model.presenter.hasReport {
				list
			} else {
				placeholder
			}
			footer
		}
		.padding(20)
		.alert("휴지통으로 보낼까요?", isPresented: trashShown) {
			Button("휴지통으로 보내기", role: .destructive) { model.performTrash() }
			Button("취소", role: .cancel) { model.pendingTrash = nil }
		} message: {
			Text(model.confirmationText(.category(category)))
		}
		.alert("일부 항목을 보내지 못했습니다", isPresented: failuresShown) {
			Button("확인", role: .cancel) { model.failures = [] }
		} message: {
			Text(model.failures.prefix(10).map { "\($0.request.path)\n  \($0.error)" }.joined(separator: "\n"))
		}
	}

	// MARK: - 상단

	private var header: some View {
		HStack(alignment: .top) {
			VStack(alignment: .leading, spacing: 4) {
				Text(category.title).font(.title2.weight(.semibold))
				Text(model.summaryText(category)).foregroundStyle(.secondary)
				if !model.status.isEmpty {
					Text(model.status).font(.callout).foregroundStyle(.secondary)
				}
			}
			Spacer()
			Picker("", selection: $model.mode) {
				ForEach(FileListMode.allCases, id: \.self) { mode in
					Text(mode.title).tag(mode)
				}
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.frame(width: 220)
			Button("스캔") { model.scan() }
				.disabled(model.isBusy)
		}
	}

	private var placeholder: some View {
		VStack(spacing: 8) {
			Spacer()
			Text("스캔을 누르면 폴더를 살펴보고, 정리해도 될 만한 파일을 이유와 함께 보여 줍니다.")
			Text("파일은 직접 고른 것만 휴지통으로 보냅니다.").foregroundStyle(.secondary)
			Spacer()
		}
		.frame(maxWidth: .infinity)
	}

	// MARK: - 목록

	@ViewBuilder
	private var list: some View {
		let rows = model.rows(category)
		if rows.isEmpty {
			VStack {
				Spacer()
				Text(model.mode == .suggested ? "정리 추천이 없습니다" : "1MB 넘는 파일이 없습니다")
					.foregroundStyle(.secondary)
				Spacer()
			}
			.frame(maxWidth: .infinity)
		} else {
			List(rows) { row in
				fileRow(row)
					.contextMenu { RevealMenu(path: row.path) }
			}
			.listStyle(.inset(alternatesRowBackgrounds: true))
			.disabled(model.isBusy)
		}
	}

	private func fileRow(_ row: FileRow) -> some View {
		HStack(spacing: 10) {
			Toggle("", isOn: selection(row.path))
				.toggleStyle(.checkbox)
				.labelsHidden()
				.disabled(row.protectedReason != nil)
			VStack(alignment: .leading, spacing: 2) {
				Text(row.name).lineLimit(1).truncationMode(.middle)
				Text(row.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
			}
			.help(row.path)
			Spacer()
			ForEach(row.reasons, id: \.self) { reason in
				Chip(text: reason, tint: .orange)
			}
			if let reason = row.protectedReason {
				Chip(text: reason)
			}
			Text(row.sizeText)
				.monospacedDigit()
				.frame(width: 90, alignment: .trailing)
		}
	}

	// MARK: - 하단

	private var footer: some View {
		HStack {
			if model.presenter.hasReport {
				Text(model.selectionText(category))
			}
			Spacer()
			Button("추천 모두 선택") { model.selectAllSuggested(category) }
				.disabled(model.isBusy || model.presenter.suggestedCount(category) == 0)
			Button("선택 해제") { model.clearSelection(category) }
				.disabled(model.isBusy)
			Button("휴지통으로 보내기") { model.requestTrash(.category(category)) }
				.disabled(!model.canTrash(category))
				.keyboardShortcut(.defaultAction)
		}
	}

	// MARK: - 바인딩

	private func selection(_ path: String) -> Binding<Bool> {
		Binding(
			get: { model.presenter.isSelected(path) },
			set: { model.setSelected(path, $0) }
		)
	}

	private var trashShown: Binding<Bool> {
		Binding(
			get: { model.pendingTrash == .category(category) },
			set: { if !$0 { model.pendingTrash = nil } }
		)
	}

	private var failuresShown: Binding<Bool> {
		Binding(
			get: { !model.failures.isEmpty },
			set: { if !$0 { model.failures = [] } }
		)
	}
}
#endif
