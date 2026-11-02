#if os(macOS)
import BaroSsacCore
import SwiftUI

/// 시스템 데이터 화면 (캐시 · 로그 · 개발 도구 파일)
internal struct SystemDataView: View {
	@ObservedObject var model: ScanViewModel

	var body: some View {
		VStack(spacing: 0) {
			if model.hasScanned {
				content
				ActionBar {
					SelectionSummary(count: model.selectedCount, bytes: model.presenter.selectedBytes)
				} trailing: {
					TrashButton(enabled: model.canClean) { model.requestClean() }
				}
			} else {
				emptyState
			}
		}
		.navigationTitle("시스템 데이터")
		.navigationSubtitle(model.subtitle)
		.scanToolbar(isBusy: model.isBusy) { model.scan() }
		.alert("주의 항목 포함", isPresented: confirmationShown) {
			Button("휴지통으로 보내기", role: .destructive) {
				model.performClean(confirmed: model.pendingConfirmation ?? [])
			}
			Button("취소", role: .cancel) { model.pendingConfirmation = nil }
		} message: {
			let paths = model.pendingConfirmation ?? []
			Text("복구 어려운 항목 \(paths.count)개\n\n" + paths.joined(separator: "\n"))
		}
		.alert("휴지통 이동 실패 항목", isPresented: failuresShown) {
			Button("확인", role: .cancel) { model.failures = [] }
		} message: {
			Text(model.failures.prefix(10).map { "\($0.item.path)\n\($0.error)" }.joined(separator: "\n\n"))
		}
	}

	// MARK: - 빈 화면

	private var emptyState: some View {
		ContentUnavailableView {
			Label("시스템 데이터", systemImage: "internaldrive")
		} description: {
			Text("대상: 앱 캐시 · 오래된 로그 · 개발 도구 파일\n처리: 휴지통으로만 이동")
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
				title: "정리 가능 용량",
				value: model.hasReport ? model.presenter.totalText : "0 B",
				facts: model.heroFacts,
				notice: model.heroNotice
			) {
				DonutChart(
					segments: model.segments,
					centerText: model.donutCenter,
					caption: model.donutCaption
				)
					.frame(width: 132, height: 132)
			}
			.padding(.horizontal, Design.pagePadding)
			.padding(.top, Design.pagePadding)

			if model.hasReport {
				list
			} else {
				ContentUnavailableView(
					"정리할 파일 없음",
					systemImage: "checkmark.circle",
					description: Text("제거 가능한 캐시 · 로그 없음")
				)
			}
		}
	}

	/// 목록: 종류 · 위험도 · 용량 | 색 점 = 도넛 조각 색 (범례 겸용)
	private var list: some View {
		List {
			ForEach(model.groups) { group in
				DisclosureGroup {
					ForEach(group.children) { child in
						childRow(child)
							.contextMenu { RevealMenu(path: child.path) }
					}
				} label: {
					groupRow(group)
				}
			}
		}
		.listStyle(.inset)
		.disabled(model.isBusy)
	}

	private func groupRow(_ g: GroupRow) -> some View {
		HStack(spacing: 10) {
			Toggle("", isOn: groupBinding(g.name))
				.toggleStyle(.checkbox)
				.labelsHidden()
			Circle()
				.fill(Palette.color(g.color))
				.frame(width: 8, height: 8)
			VStack(alignment: .leading, spacing: 1) {
				Text(g.title).fontWeight(.semibold)
				Text(g.description)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.help(g.description)
			Spacer()
			Tag(text: g.risk.label, tint: g.risk.tint)
				.help(g.risk.help)
			SizeLabel(text: g.sizeText, emphasized: true)
		}
		.padding(.vertical, 4)
	}

	private func childRow(_ c: ChildRow) -> some View {
		HStack(spacing: 10) {
			Toggle("", isOn: itemBinding(c.path))
				.toggleStyle(.checkbox)
				.labelsHidden()
			FileIcon(path: c.path, size: 16)
			Text(c.label)
				.lineLimit(1)
				.truncationMode(.middle)
				.help(c.path)
			if let owner = c.inUseBy {
				Tag(text: "실행 중", tint: .blue)
					.help("실행 중: \(owner) · 앱 종료 후 정리 가능")
			}
			Spacer()
			SizeLabel(text: c.sizeText)
		}
	}

	// MARK: - 바인딩

	private func itemBinding(_ path: String) -> Binding<Bool> {
		Binding(
			get: { model.presenter.isSelected(path) },
			set: { model.setItem(path, $0) }
		)
	}

	private func groupBinding(_ name: String) -> Binding<Bool> {
		Binding(
			get: { model.presenter.groupState(name) != .none },
			set: { model.setGroup(name, $0) }
		)
	}

	private var confirmationShown: Binding<Bool> {
		Binding(
			get: { model.pendingConfirmation != nil },
			set: { if !$0 { model.pendingConfirmation = nil } }
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
