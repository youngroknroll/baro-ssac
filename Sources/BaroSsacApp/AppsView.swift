#if os(macOS)
import BaroSsacCore
import SwiftUI

internal struct AppsView: View {
	@ObservedObject var model: AppsViewModel

	var body: some View {
		VStack(spacing: 0) {
			if model.presenter.isLoaded {
				content
			} else {
				emptyState
			}
		}
		.navigationTitle("응용 프로그램")
		.navigationSubtitle(model.subtitle)
		.modeToolbar($model.mode)
		.scanToolbar(isBusy: model.isBusy) { model.scan() }
		.sheet(isPresented: sheetShown) {
			if let appPath = model.uninstalling {
				UninstallSheet(model: model, appPath: appPath)
			}
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
			Label("응용 프로그램", systemImage: "square.grid.2x2")
		} description: {
			Text("크기: 앱 + 설정 · 캐시 · 데이터 합산\n표시: 1년 넘게 미사용 앱")
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
				title: "장기 미사용 앱 용량",
				value: model.heroValue,
				facts: model.heroFacts,
				fraction: model.unusedFraction
			)
			.padding(.horizontal, Design.pagePadding)
			.padding(.top, Design.pagePadding)

			list
		}
	}

	@ViewBuilder
	private var list: some View {
		let rows = model.rows
		if rows.isEmpty {
			ContentUnavailableView(
				"장기 미사용 앱 없음",
				systemImage: "checkmark.circle",
				description: Text("전체 목록: 툴바의 '전체 (크기순)'")
			)
		} else {
			List(rows) { row in
				appRow(row)
					.contextMenu { RevealMenu(path: row.path) }
			}
			.listStyle(.inset)
		}
	}

	private func appRow(_ row: AppRow) -> some View {
		HStack(spacing: 12) {
			FileIcon(path: row.path, size: 32)
			TitleAndCaption(
				title: row.name,
				caption: row.leftoverCount > 0 ? "관련 파일 \(row.leftoverCount)개 포함" : "관련 파일 없음",
				help: row.path
			)
			Spacer(minLength: 12)
			ForEach(row.reasons, id: \.self) { reason in
				Tag(text: reason, tint: .orange)
			}
			if let reason = row.protectedReason {
				Tag(text: reason)
			}
			SizeLabel(text: row.sizeText, emphasized: true)
			Button {
				model.requestUninstall(row.path)
			} label: {
				Image(systemName: "trash")
			}
			.buttonStyle(.borderless)
			.help(row.protectedReason == nil ? "\(row.name) 삭제" : "macOS 기본 앱 · 삭제 불가")
			.disabled(row.protectedReason != nil || model.isBusy)
			.opacity(row.protectedReason == nil ? 1 : 0)
		}
		.padding(.vertical, 4)
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

/// 앱 삭제 확인 시트: 함께 지울 관련 파일 선택
internal struct UninstallSheet: View {
	@ObservedObject var model: AppsViewModel
	let appPath: String

	var body: some View {
		let item = model.presenter.item(appPath)
		let leftovers = model.presenter.leftoverRows(for: appPath)
		VStack(alignment: .leading, spacing: 0) {
			// 머리: 아이콘 · 제목 · 대상 안내
			HStack(spacing: 14) {
				FileIcon(path: appPath, size: 56)
				VStack(alignment: .leading, spacing: 4) {
					Text("\(item?.app.name ?? "앱") 삭제")
						.font(.title3.weight(.semibold))
					Text("대상: 앱 + 선택한 관련 파일 · 복구: 휴지통 비우기 전까지 가능")
						.font(.callout)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.padding(20)

			Divider()

			// 몸통: 앱 본체 · 관련 파일 목록
			ScrollView {
				VStack(alignment: .leading, spacing: 10) {
					HStack(spacing: 10) {
						Image(systemName: "checkmark.square.fill")
							.foregroundStyle(.secondary)
							.help("앱 본체 · 항상 포함")
						TitleAndCaption(
							title: item?.app.name ?? "앱",
							caption: HomePath.display(appPath, home: NSHomeDirectory())
						)
						Spacer()
						SizeLabel(text: formatSize(item?.app.sizeBytes ?? 0))
					}

					if leftovers.isEmpty {
						Text("관련 파일 없음")
							.foregroundStyle(.secondary)
							.padding(.top, 4)
					} else {
						Text("함께 삭제할 관련 파일")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.secondary)
							.padding(.top, 8)
						ForEach(leftovers) { leftover in
							HStack(spacing: 10) {
								Toggle("", isOn: binding(leftover.path))
									.toggleStyle(.checkbox)
									.labelsHidden()
								TitleAndCaption(
									title: leftover.display,
									caption: leftover.matchText,
									help: leftover.path
								)
								Spacer()
								SizeLabel(text: leftover.sizeText)
							}
						}
						Label("Containers: 앱이 저장한 문서 · 데이터 포함 가능", systemImage: "info.circle")
							.font(.caption)
							.foregroundStyle(.secondary)
							.padding(.top, 4)
					}
				}
				.padding(20)
			}
			.frame(maxHeight: 300)

			Divider()

			// 바닥: 합계 · 취소 · 삭제
			HStack {
				VStack(alignment: .leading, spacing: 0) {
					Text("합계").font(.caption).foregroundStyle(.secondary)
					Text(formatSize(model.presenter.uninstallBytes(for: appPath)))
						.font(.title3.weight(.semibold))
						.monospacedDigit()
				}
				Spacer()
				Button("취소", role: .cancel) { model.uninstalling = nil }
					.keyboardShortcut(.cancelAction)
					.controlSize(.large)
				Button("휴지통으로 보내기", role: .destructive) { model.performUninstall() }
					.buttonStyle(.borderedProminent)
					.tint(.red)
					.controlSize(.large)
			}
			.padding(20)
		}
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
