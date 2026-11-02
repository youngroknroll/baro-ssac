#if os(macOS)
import BaroSsacCore
import SwiftUI

/// 중복 파일 탭: 내용 동일 파일 묶음 단위 표시 · 묶음별 원본 표시
internal struct DuplicatesView: View {
	@ObservedObject var model: FilesViewModel

	var body: some View {
		VStack(spacing: 0) {
			if model.hasScanned {
				content
				ActionBar {
					SelectionSummary(count: model.selectedDuplicateCount, bytes: model.selectedDuplicateBytes)
				} trailing: {
					Button("사본 모두 선택") { model.selectAllDuplicateCopies() }
						.disabled(model.isBusy || model.duplicateGroups().isEmpty)
						.help("묶음마다 원본 유지 · 사본만 선택")
					Button("선택 해제") { model.clearDuplicateSelection() }
						.disabled(model.isBusy || model.selectedDuplicateCount == 0)
					TrashButton(enabled: model.canTrashDuplicates) { model.requestTrash(.duplicates) }
				}
			} else {
				emptyState
			}
		}
		.navigationTitle("중복 파일")
		.navigationSubtitle(model.duplicateSubtitle)
		.scanToolbar(isBusy: model.isBusy) { model.scan() }
		.alert(model.confirmationTitle(.duplicates), isPresented: trashShown) {
			Button("휴지통으로 보내기", role: .destructive) { model.performTrash() }
			Button("취소", role: .cancel) { model.pendingTrash = nil }
		} message: {
			Text(model.confirmationText(.duplicates))
		}
	}

	// MARK: - 빈 화면

	private var emptyState: some View {
		ContentUnavailableView {
			Label("중복 파일", systemImage: "doc.on.doc")
		} description: {
			Text("대상: 문서 · 사진 · 음악 · 동영상 · 다운로드\n기준: 내용 동일 · 묶음마다 원본 1개 유지")
		} actions: {
			Button("스캔하기") { model.scan() }
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(model.isBusy)
		}
	}

	// MARK: - 내용

	private var content: some View {
		VStack(spacing: 16) {
			HeroCard(
				title: "사본 제거 시 확보 용량",
				value: formatSize(model.presenter.duplicateReclaimableBytes),
				facts: model.duplicateHeroFacts,
				notice: model.duplicateHeroNotice
			)
			.padding(.horizontal, Design.pagePadding)
			.padding(.top, Design.pagePadding)

			list
		}
	}

	@ViewBuilder
	private var list: some View {
		let groups = model.duplicateGroups()
		if groups.isEmpty {
			ContentUnavailableView(
				"중복 파일 없음",
				systemImage: "checkmark.circle",
				description: Text("검사 대상: 1MB 초과 파일")
			)
		} else {
			List {
				ForEach(groups) { group in
					Section {
						fileRow(group.keeper, isKeeper: true)
						ForEach(group.copies) { copy in
							fileRow(copy, isKeeper: false)
						}
					} header: {
						groupHeader(group)
					}
				}
			}
			.listStyle(.inset)
			.disabled(model.isBusy)
		}
	}

	private func groupHeader(_ group: DuplicateGroup) -> some View {
		HStack(spacing: 8) {
			Text(group.keeper.name)
				.fontWeight(.semibold)
				.foregroundStyle(.primary)
				.lineLimit(1)
				.truncationMode(.middle)
			Text("사본 \(group.copies.count)개 · 각 \(group.sizeText)")
				.foregroundStyle(.secondary)
			Spacer()
			Text("\(group.reclaimableText) 확보")
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
		.font(.subheadline)
		.padding(.top, 6)
	}

	private func fileRow(_ row: FileRow, isKeeper: Bool) -> some View {
		HStack(spacing: 10) {
			Toggle("", isOn: selection(row.path))
				.toggleStyle(.checkbox)
				.labelsHidden()
			FileIcon(path: row.path, size: 24)
			// 위치 우선 표시 (이름 동일 사례 많음)
			TitleAndCaption(title: row.folder, caption: row.name, help: row.path)
			Spacer(minLength: 12)
			if isKeeper {
				Tag(text: "원본 유지", tint: .green)
			} else {
				Tag(text: "사본", tint: .orange)
			}
			SizeLabel(text: row.sizeText)
		}
		.padding(.vertical, 3)
		.contextMenu { RevealMenu(path: row.path) }
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
