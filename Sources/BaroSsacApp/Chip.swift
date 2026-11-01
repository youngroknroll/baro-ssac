#if os(macOS)
import SwiftUI

/// 목록 행에 붙는 작은 이유 표시 ("설치 파일", "실행 중" 등).
internal struct Chip: View {
	let text: String
	var tint: Color = .secondary

	var body: some View {
		Text(text)
			.font(.caption)
			.lineLimit(1)
			.padding(.horizontal, 6)
			.padding(.vertical, 1)
			.background(Capsule().fill(tint.opacity(0.15)))
			.foregroundStyle(tint)
	}
}

/// Finder 에서 보기 / 열기. 지우기 전에 무엇인지 확인할 수 있게 한다.
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
#endif
