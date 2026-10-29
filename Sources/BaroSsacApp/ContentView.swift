#if os(macOS)
import SwiftUI
import BaroSsacCore

internal struct ContentView: View {
	@ObservedObject var model: ScanViewModel

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			header
			list
			footer
		}
		.padding(24)
		.frame(minWidth: 640, minHeight: 560)
		.onAppear { NSApp.activate(ignoringOtherApps: true) }
		.alert("주의가 필요한 항목", isPresented: confirmationShown) {
			Button("휴지통으로 보내기", role: .destructive) {
				model.performClean(confirmed: model.pendingConfirmation ?? [])
			}
			Button("취소", role: .cancel) { model.pendingConfirmation = nil }
		} message: {
			let paths = model.pendingConfirmation ?? []
			Text("다음 \(paths.count)개 항목은 복구하기 어려울 수 있습니다.\n\n" + paths.joined(separator: "\n"))
		}
		.alert("일부 항목을 보내지 못했습니다", isPresented: failuresShown) {
			Button("확인", role: .cancel) { model.failures = [] }
		} message: {
			Text(model.failures.prefix(10).map { "\($0.item.path)\n  \($0.error)" }.joined(separator: "\n"))
		}
	}

	// MARK: - 상단: 도넛 + 숫자 + 스캔

	private var header: some View {
		HStack(alignment: .center, spacing: 20) {
			DonutChart(segments: model.segments, centerText: model.presenter.selectedText, caption: model.centerCaption)
				.frame(width: 176, height: 176)
			VStack(alignment: .leading, spacing: 4) {
				Text(model.hasReport ? model.presenter.totalText : "—")
					.font(.system(size: 30, weight: .semibold))
				Text(model.status).foregroundStyle(.secondary)
				Text(model.diskText).foregroundStyle(.secondary).padding(.top, 6)
			}
			Spacer()
			Button("스캔") { model.scan() }
				.disabled(model.isBusy)
				.frame(minWidth: 96)
		}
	}

	// MARK: - 가운데: 종류 · 위험도 · 용량 (목록이 곧 범례)

	private var list: some View {
		List {
			ForEach(model.groups) { group in
				DisclosureGroup {
					ForEach(group.children) { child in
						childRow(child)
					}
				} label: {
					groupRow(group)
				}
			}
		}
		.listStyle(.inset(alternatesRowBackgrounds: true))
		.disabled(model.isBusy)
	}

	private func groupRow(_ g: GroupRow) -> some View {
		HStack(spacing: 8) {
			Toggle("", isOn: groupBinding(g.name))
				.toggleStyle(.checkbox)
				.labelsHidden()
			Circle().fill(Color(hex: g.color)).frame(width: 10, height: 10)
			Text(g.title).fontWeight(.semibold)
				.help(g.description)
			Spacer()
			Text(riskLabel(g.risk))
				.foregroundStyle(riskColor(g.risk))
				.frame(width: 80, alignment: .trailing)
			Text(g.sizeText)
				.fontWeight(.semibold)
				.monospacedDigit()
				.frame(width: 90, alignment: .trailing)
		}
	}

	private func childRow(_ c: ChildRow) -> some View {
		HStack(spacing: 8) {
			Toggle("", isOn: itemBinding(c.path))
				.toggleStyle(.checkbox)
				.labelsHidden()
			Text(c.label).help(c.path)
			Spacer()
			Text(c.sizeText)
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.frame(width: 90, alignment: .trailing)
		}
		.padding(.leading, 18)
	}

	// MARK: - 하단: 선택 합계 + 정리

	private var footer: some View {
		HStack {
			if model.hasReport {
				Text("\(model.selectedCount)개 선택 · \(model.presenter.selectedText)")
			}
			Spacer()
			Button("휴지통으로 보내기") { model.requestClean() }
				.disabled(!model.canClean)
				.keyboardShortcut(.defaultAction)
				.frame(minWidth: 160)
		}
	}

	// MARK: - 바인딩과 표시 규칙

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

	private func riskLabel(_ risk: RiskLevel) -> String {
		switch risk {
		case .low: return "안전"
		case .medium: return "재다운로드"
		case .high: return "주의"
		}
	}

	private func riskColor(_ risk: RiskLevel) -> Color {
		switch risk {
		case .low: return Color(hex: "#3a7d44")
		case .medium: return Color(hex: "#b07d14")
		case .high: return Color(hex: "#b3261e")
		}
	}
}
#endif
