#if os(macOS)
import BaroSsacCore
import SwiftUI

internal struct AppsView: View {
	@ObservedObject var model: AppsViewModel

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			header
			if model.presenter.isLoaded {
				list
			} else {
				placeholder
			}
		}
		.padding(20)
		.sheet(isPresented: sheetShown) {
			if let appPath = model.uninstalling {
				UninstallSheet(model: model, appPath: appPath)
			}
		}
		.alert("일부 항목을 보내지 못했습니다", isPresented: failuresShown) {
			Button("확인", role: .cancel) { model.failures = [] }
		} message: {
			Text(model.failures.prefix(10).map { "\($0.request.path)\n  \($0.error)" }.joined(separator: "\n"))
		}
	}

	private var header: some View {
		HStack(alignment: .top) {
			VStack(alignment: .leading, spacing: 4) {
				Text("응용 프로그램").font(.title2.weight(.semibold))
				Text(model.summaryText).foregroundStyle(.secondary)
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
			Text("스캔을 누르면 설치된 앱을 크기순으로 보여 줍니다.")
			Text("앱을 지울 때 그 앱이 남긴 설정·캐시·데이터도 함께 찾아 줍니다.").foregroundStyle(.secondary)
			Spacer()
		}
		.frame(maxWidth: .infinity)
	}

	private var list: some View {
		List(model.rows) { row in
			HStack(spacing: 10) {
				Image(nsImage: NSWorkspace.shared.icon(forFile: row.path))
					.resizable()
					.frame(width: 28, height: 28)
				VStack(alignment: .leading, spacing: 2) {
					Text(row.name)
					if row.leftoverCount > 0 {
						Text("관련 파일 \(row.leftoverCount)개 포함").font(.caption).foregroundStyle(.secondary)
					}
				}
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
				Button("삭제…") { model.requestUninstall(row.path) }
					.disabled(row.protectedReason != nil || model.isBusy)
			}
			.contextMenu { RevealMenu(path: row.path) }
		}
		.listStyle(.inset(alternatesRowBackgrounds: true))
	}

	private var sheetShown: Binding<Bool> {
		Binding(
			get: { model.uninstalling != nil },
			set: { if !$0 { model.uninstalling = nil } }
		)
	}

	private var failuresShown: Binding<Bool> {
		Binding(
			get: { !model.failures.isEmpty },
			set: { if !$0 { model.failures = [] } }
		)
	}
}

/// 앱과 함께 지울 관련 파일을 고르는 확인 창.
internal struct UninstallSheet: View {
	@ObservedObject var model: AppsViewModel
	let appPath: String

	var body: some View {
		let item = model.presenter.item(appPath)
		let leftovers = model.presenter.leftoverRows(for: appPath)
		VStack(alignment: .leading, spacing: 12) {
			Text("\(item?.app.name ?? "앱") 삭제").font(.title3.weight(.semibold))
			Text("앱과 아래에서 고른 파일을 휴지통으로 보냅니다. 휴지통을 비우기 전까지는 되돌릴 수 있습니다.")
				.foregroundStyle(.secondary)

			HStack {
				Image(systemName: "checkmark.square.fill").foregroundStyle(.secondary)
				Text(HomePath.display(appPath, home: NSHomeDirectory()))
				Spacer()
				Text(formatSize(item?.app.sizeBytes ?? 0)).monospacedDigit()
			}

			if leftovers.isEmpty {
				Text("이 앱이 남긴 파일을 찾지 못했습니다.").foregroundStyle(.secondary)
			} else {
				Text("관련 파일").font(.headline)
				ScrollView {
					VStack(alignment: .leading, spacing: 6) {
						ForEach(leftovers) { leftover in
							HStack {
								Toggle("", isOn: binding(leftover.path))
									.toggleStyle(.checkbox)
									.labelsHidden()
								VStack(alignment: .leading, spacing: 1) {
									Text(leftover.display).lineLimit(1).truncationMode(.middle)
									Text(leftover.matchText).font(.caption).foregroundStyle(.secondary)
								}
								.help(leftover.path)
								Spacer()
								Text(leftover.sizeText).monospacedDigit()
							}
						}
					}
				}
				.frame(maxHeight: 240)
				Text("Containers 안에는 앱이 저장한 문서나 데이터가 있을 수 있습니다.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			HStack {
				Text("합계 \(formatSize(model.presenter.uninstallBytes(for: appPath)))")
				Spacer()
				Button("취소", role: .cancel) { model.uninstalling = nil }
					.keyboardShortcut(.cancelAction)
				Button("휴지통으로 보내기", role: .destructive) { model.performUninstall() }
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 560)
	}

	private func binding(_ path: String) -> Binding<Bool> {
		Binding(
			get: { model.presenter.leftoverRows(for: appPath).first { $0.path == path }?.isSelected ?? false },
			set: { model.setLeftover(path, of: appPath, $0) }
		)
	}
}
#endif
