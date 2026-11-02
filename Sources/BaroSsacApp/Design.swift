#if os(macOS)
import BaroSsacCore
import SwiftUI

// 디자인 토큰 · 공통 부품 (전 화면 공통 간격 · 모양 · 색)
// 원칙: 골격 = macOS 표준(툴바 · 창 제목 · 사이드바 · 시스템 색) | 정보 = 큰 숫자 하나 + 항목명-값 행

internal enum Design {
	static let pagePadding: CGFloat = 24
	static let cornerRadius: CGFloat = 14
	static let sizeColumnWidth: CGFloat = 84
	/// 카드 배경: primary 투명도 → 라이트 · 다크 모드 공통
	static let cardFill = Color.primary.opacity(0.045)
	static let trackFill = Color.primary.opacity(0.08)
}

// MARK: - 색

internal enum Palette {
	/// Core 색 이름(ChartColors) → 시스템 색
	static func color(_ name: String) -> Color {
		switch name {
		case "blue": .blue
		case "purple": .purple
		case "pink": .pink
		case "orange": .orange
		case "teal": .teal
		case "indigo": .indigo
		case "mint": .mint
		case "cyan": .cyan
		case "yellow": .yellow
		case "brown": .brown
		case "green": .green
		case ChartColors.free: Design.trackFill
		default: Color.gray.opacity(0.45)
		}
	}
}

internal extension RiskLevel {
	var label: String {
		switch self {
		case .low: "안전"
		case .medium: "다시 받음"
		case .high: "주의"
		}
	}

	var tint: Color {
		switch self {
		case .low: .green
		case .medium: .orange
		case .high: .red
		}
	}

	var help: String {
		switch self {
		case .low: "앱이 필요 시 재생성"
		case .medium: "재다운로드 필요 · 시간 소요"
		case .high: "복구 어려움 · 직접 선택 시에만 정리"
		}
	}
}

// MARK: - 요약 카드

/// 요약 카드의 한 줄: 항목명 + 값
internal struct HeroFact: Hashable {
	let label: String
	let value: String
	var emphasized = false
}

/// 화면 상단 요약 카드: 작은 제목 · 큰 숫자 · 항목명-값 행 · 알림 한 줄 · 선택적 비율 막대 · 선택적 왼쪽 그림
internal struct HeroCard<Accessory: View>: View {
	let title: String
	let value: String
	var facts: [HeroFact]
	var notice: String?
	var fraction: Double?
	let accessory: Accessory

	init(
		title: String,
		value: String,
		facts: [HeroFact] = [],
		notice: String? = nil,
		fraction: Double? = nil,
		@ViewBuilder accessory: () -> Accessory
	) {
		self.title = title
		self.value = value
		self.facts = facts
		self.notice = notice
		self.fraction = fraction
		self.accessory = accessory()
	}

	var body: some View {
		HStack(alignment: .center, spacing: 28) {
			accessory
			VStack(alignment: .leading, spacing: 10) {
				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
					Text(value)
						.font(.system(size: 34, weight: .bold, design: .rounded))
						.monospacedDigit()
						.contentTransition(.numericText())
				}
				if !facts.isEmpty {
					Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
						ForEach(facts, id: \.label) { fact in
							GridRow {
								Text(fact.label)
									.foregroundStyle(.secondary)
								Text(fact.value)
									.monospacedDigit()
									.fontWeight(fact.emphasized ? .bold : .regular)
									.foregroundStyle(fact.emphasized ? Color.accentColor : Color.primary)
							}
						}
					}
					.font(.callout)
				}
				if let notice {
					Label(notice, systemImage: "info.circle")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
				if let fraction {
					UsageBar(fraction: fraction)
						.frame(maxWidth: 360)
				}
			}
			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Design.cardFill, in: RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous))
		.animation(.snappy, value: value)
		.animation(.snappy, value: facts)
	}
}

internal extension HeroCard where Accessory == EmptyView {
	init(
		title: String,
		value: String,
		facts: [HeroFact] = [],
		notice: String? = nil,
		fraction: Double? = nil
	) {
		self.init(title: title, value: value, facts: facts, notice: notice, fraction: fraction) { EmptyView() }
	}
}

/// 비율 막대 (전체 대비 일부)
internal struct UsageBar: View {
	let fraction: Double
	var tint: Color = .accentColor

	var body: some View {
		GeometryReader { geo in
			let clamped = min(max(fraction, 0), 1)
			ZStack(alignment: .leading) {
				Capsule().fill(Design.trackFill)
				Capsule()
					.fill(tint)
					.frame(width: clamped > 0 ? max(geo.size.width * clamped, 6) : 0)
			}
		}
		.frame(height: 6)
		.animation(.snappy, value: fraction)
	}
}

// MARK: - 목록 부품

/// 목록 행 이유 표시 (예: 설치 파일 · 실행 중 · 주의)
internal struct Tag: View {
	let text: String
	var tint: Color = .secondary

	var body: some View {
		Text(text)
			.font(.caption.weight(.medium))
			.lineLimit(1)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.foregroundStyle(tint)
			.background(tint.opacity(0.12), in: Capsule())
	}
}

/// 파일 아이콘 (Finder 동일)
internal struct FileIcon: View {
	let path: String
	var size: CGFloat = 20

	var body: some View {
		Image(nsImage: NSWorkspace.shared.icon(forFile: path))
			.resizable()
			.interpolation(.high)
			.frame(width: size, height: size)
	}
}

/// 목록 크기 열 | 고정폭 숫자로 정렬
internal struct SizeLabel: View {
	let text: String
	var emphasized = false

	var body: some View {
		Text(text)
			.monospacedDigit()
			.fontWeight(emphasized ? .semibold : .regular)
			.foregroundStyle(emphasized ? .primary : .secondary)
			.frame(width: Design.sizeColumnWidth, alignment: .trailing)
	}
}

/// 두 줄 표시: 위 이름 · 아래 위치
internal struct TitleAndCaption: View {
	let title: String
	let caption: String
	var help: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(title).lineLimit(1).truncationMode(.middle)
			Text(caption)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.head)
		}
		.help(help ?? title)
	}
}

/// 우클릭 메뉴: Finder에서 보기 · 열기 (삭제 전 확인용)
internal struct RevealMenu: View {
	let path: String

	var body: some View {
		Button("Finder에서 보기") {
			NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
		}
		Button("열기") {
			NSWorkspace.shared.open(URL(fileURLWithPath: path))
		}
	}
}

// MARK: - 하단 작업 막대

/// 하단 고정 작업 막대: 왼쪽 선택 요약 · 오른쪽 동작
internal struct ActionBar<Leading: View, Trailing: View>: View {
	let leading: Leading
	let trailing: Trailing

	init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
		self.leading = leading()
		self.trailing = trailing()
	}

	var body: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				leading
				Spacer()
				trailing
			}
			.padding(.horizontal, Design.pagePadding)
			.padding(.top, 14)
			.padding(.bottom, 18)
		}
		.background(.bar)
		// 높이 고정: 압축 시 하단 여백 소실 · 버튼이 창 끝에 붙음 (2026-11-02 확인)
		.fixedSize(horizontal: false, vertical: true)
	}
}

internal struct SelectionSummary: View {
	let count: Int
	let bytes: Int64

	var body: some View {
		if count == 0 {
			Text("제거할 항목을 선택하세요").foregroundStyle(.secondary)
		} else {
			HStack(spacing: 6) {
				Text("\(count)개 선택").fontWeight(.semibold)
				Text(formatSize(bytes)).monospacedDigit().foregroundStyle(.secondary)
			}
		}
	}
}

/// 휴지통 버튼: ⌘⌫ (Finder 동일) | Return 키 미지정 (삭제 동작)
internal struct TrashButton: View {
	let enabled: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Label("휴지통으로 보내기", systemImage: "trash")
		}
		.buttonStyle(.borderedProminent)
		.controlSize(.large)
		.keyboardShortcut(.delete, modifiers: .command)
		.disabled(!enabled)
		.help("선택 항목 휴지통으로 이동 (⌘⌫)")
	}
}

// MARK: - 툴바

internal extension View {
	/// 툴바 오른쪽 스캔 버튼 (⌘R) | 진행 중: 진행 표시
	func scanToolbar(isBusy: Bool, action: @escaping () -> Void) -> some View {
		toolbar {
			ToolbarItem(placement: .primaryAction) {
				if isBusy {
					ProgressView().controlSize(.small)
				} else {
					Button(action: action) {
						Label("스캔", systemImage: "arrow.clockwise")
					}
					.keyboardShortcut("r", modifiers: .command)
					.help("다시 스캔 (⌘R)")
				}
			}
		}
	}

	/// 툴바 가운데 보기 전환 (정리 추천 / 전체)
	func modeToolbar(_ mode: Binding<FileListMode>) -> some View {
		toolbar {
			ToolbarItem(placement: .principal) {
				Picker("보기", selection: mode) {
					ForEach(FileListMode.allCases, id: \.self) { mode in
						Text(mode.title).tag(mode)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()
			}
		}
	}
}
#endif
