#if os(macOS)
import BaroSsacCore
import SwiftUI

/// 파일 카테고리 화면 (문서 · 사진 · 음악 · 동영상 · 다운로드)
internal struct FilesView: View {
	let category: FileCategory
	@ObservedObject var model: FilesViewModel

	var body: some View {
		VStack(spacing: 0) {
			if model.hasScanned {
				content
				ActionBar {
					SelectionSummary(
						count: model.selectedCount(category),
						bytes: model.presenter.selectedBytes(in: category)
					)
				} trailing: {
					Button("추천 모두 선택") { model.selectAllSuggested(category) }
						.disabled(model.isBusy || model.presenter.suggestedCount(category) == 0)
					Button("선택 해제") { model.clearSelection(category) }
						.disabled(model.isBusy || model.selectedCount(category) == 0)
					TrashButton(enabled: model.canTrash(category)) { model.requestTrash(.category(category)) }
				}
			} else {
				emptyState
			}
		}
		.navigationTitle(category.title)
		.navigationSubtitle(model.subtitle(category))
		.modeToolbar($model.mode)
		.scanToolbar(isBusy: model.isBusy) { model.scan() }
		.alert(model.confirmationTitle(.category(category)), isPresented: trashShown) {
			Button("휴지통으로 보내기", role: .destructive) { model.performTrash() }
			Button("취소", role: .cancel) { model.pendingTrash = nil }
		} message: {
			Text(model.confirmationText(.category(category)))
		}
		.alert("휴지통 이동 실패 항목", isPresented: failuresShown) {
			Button("확인", role: .cancel) { model.failures = [] }
		} message: {
			Text(model.failures.prefix(10).map { "\($0.request.path)\n\($0.error)" }.joined(separator: "\n\n"))
		}
	}

	// MARK: - 빈 화면

	private var emptyState: some View {
		ContentUnavailableView {
			Label(category.title, systemImage: Self.icon(category))
		} description: {
			Text("추천 기준: 중복 파일 · 설치 파일 · 1년 넘게 안 연 100MB 이상 파일\n처리: 직접 선택한 파일만 휴지통으로 이동")
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
				title: "정리 추천",
				value: formatSize(model.presenter.suggestedBytes(category)),
				facts: model.heroFacts(category),
				notice: model.heroNotice(category),
				fraction: model.suggestedFraction(category)
			)
			.padding(.horizontal, Design.pagePadding)
			.padding(.top, Design.pagePadding)

			list
		}
	}

	@ViewBuilder
	private var list: some View {
		let rows = model.rows(category)
		if rows.isEmpty {
			if model.mode == .suggested {
				ContentUnavailableView(
					"정리 추천 없음",
					systemImage: "checkmark.circle",
					description: Text("전체 목록: 툴바의 '전체 (크기순)'")
				)
			} else {
				ContentUnavailableView(
					"1MB 초과 파일 없음",
					systemImage: "tray",
					description: Text("1MB 미만 파일: 목록 제외 · 전체 크기에만 합산")
				)
			}
		} else {
			List(rows) { row in
				fileRow(row)
					.contextMenu { RevealMenu(path: row.path) }
			}
			.listStyle(.inset)
			.disabled(model.isBusy)
		}
	}

	private func fileRow(_ row: FileRow) -> some View {
		HStack(spacing: 10) {
			Toggle("", isOn: selection(row.path))
				.toggleStyle(.checkbox)
				.labelsHidden()
				.disabled(row.protectedReason != nil)
			FileIcon(path: row.path, size: 24)
			TitleAndCaption(title: row.name, caption: row.folder, help: row.path)
			Spacer(minLength: 12)
			ForEach(row.reasons, id: \.self) { reason in
				Tag(text: reason, tint: .orange)
			}
			if let reason = row.protectedReason {
				Tag(text: reason)
			}
			SizeLabel(text: row.sizeText, emphasized: true)
		}
		.padding(.vertical, 3)
		.opacity(row.protectedReason == nil ? 1 : 0.6)
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

	static func icon(_ category: FileCategory) -> String {
		switch category {
		case .documents: "doc"
		case .pictures: "photo"
		case .music: "music.note"
		case .movies: "film"
		case .downloads: "arrow.down.circle"
		}
	}
}
#endif
