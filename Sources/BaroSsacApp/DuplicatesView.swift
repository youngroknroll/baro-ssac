#if os(macOS)
import BaroSsacCore
import SwiftUI

/// 중복 파일 탭. 같은 내용의 파일을 묶음 단위로 보여 주고, 묶음마다 남길 원본을 표시한다.
internal struct DuplicatesView: View {
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
			Text(model.confirmationText(.duplicates))
		}
	}

	// MARK: - 상단

	private var header: some View {
		HStack(alignment: .top) {
			VStack(alignment: .leading, spacing: 4) {
				Text("중복 파일").font(.title2.weight(.semibold))
				Text(model.duplicateSummaryText).foregroundStyle(.secondary)
				if !model.status.isEmpty {
					Text(model.status).font(.callout).foregroundStyle(.secondary)
				}
			}
			Spacer()
			Button("스캔") { model.scan() }
				.disabled(model.isBusy)
		}
	}

	private var placeholder: some View {
		VStack(spacing: 8) {
			Spacer()
			Text("스캔을 누르면 문서·사진·음악·동영상·다운로드에서 내용이 같은 파일을 찾습니다.")
			Text("묶음마다 하나는 원본으로 남기고, 나머지 사본만 정리할 수 있습니다.").foregroundStyle(.secondary)
			Spacer()
		}
		.frame(maxWidth: .infinity)
	}

	// MARK: - 목록

	@ViewBuilder
	private var list: some View {
		let groups = model.duplicateGroups()
		if groups.isEmpty {
			VStack {
				Spacer()
				Text("1MB 넘는 파일 가운데 내용이 같은 파일이 없습니다").foregroundStyle(.secondary)
				Spacer()
			}
			.frame(maxWidth: .infinity)
		} else {
			List {
				ForEach(groups) { group in
					Section {
						fileRow(group.keeper, isKeeper: true)
						ForEach(group.copies) { copy in
							fileRow(copy, isKeeper: false)
						}
					} header: {
						HStack {
							Text(group.keeper.name).lineLimit(1).truncationMode(.middle)
							Text("· 사본 \(group.copies.count)개 · 각 \(group.sizeText)")
								.foregroundStyle(.secondary)
							Spacer()
							Text("\(group.reclaimableText) 확보 가능").foregroundStyle(.secondary)
						}
					}
				}
			}
			.listStyle(.inset(alternatesRowBackgrounds: true))
			.disabled(model.isBusy)
		}
	}

	private func fileRow(_ row: FileRow, isKeeper: Bool) -> some View {
		HStack(spacing: 10) {
			Toggle("", isOn: selection(row.path))
				.toggleStyle(.checkbox)
				.labelsHidden()
			// 이름이 같은 경우가 많아 폴더를 먼저 보여 준다.
			VStack(alignment: .leading, spacing: 2) {
				Text(row.folder).lineLimit(1).truncationMode(.head)
				Text(row.name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
			}
			.help(row.path)
			Spacer()
			if isKeeper {
				Chip(text: "원본 · 남김", tint: .green)
			} else {
				Chip(text: "사본", tint: .orange)
			}
			Text(row.sizeText)
				.monospacedDigit()
				.frame(width: 90, alignment: .trailing)
		}
		.contextMenu { RevealMenu(path: row.path) }
	}

	// MARK: - 하단

	private var footer: some View {
		HStack {
			if model.presenter.hasReport {
				Text(model.duplicateSelectionText)
			}
			Spacer()
			Button("사본 모두 선택") { model.selectAllDuplicateCopies() }
				.disabled(model.isBusy || model.duplicateGroups().isEmpty)
			Button("선택 해제") { model.clearDuplicateSelection() }
				.disabled(model.isBusy)
			Button("휴지통으로 보내기") { model.requestTrash(.duplicates) }
				.disabled(!model.canTrashDuplicates)
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
			get: { model.pendingTrash == .duplicates },
			set: { if !$0 { model.pendingTrash = nil } }
		)
	}
}
#endif
