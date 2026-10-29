#if os(macOS)
import SwiftUI
import BaroSsacCore

/// 디스크 전체를 원으로, 정리 가능한 종류를 조각으로 그리는 도넛.
internal struct DonutChart: View {
	let segments: [ChartSegment]
	let centerText: String
	let caption: String

	private struct Arc: Identifiable {
		let id: String
		let color: Color
		let from: Double
		let to: Double
	}

	private var arcs: [Arc] {
		let total = Double(segments.reduce(0) { $0 + $1.bytes })
		guard total > 0 else { return [] }
		var cursor = 0.0
		return segments.compactMap { seg in
			let fraction = Double(seg.bytes) / total
			guard fraction > 0 else { return nil }
			defer { cursor += fraction }
			return Arc(id: seg.key, color: Color(hex: seg.color), from: cursor, to: cursor + fraction)
		}
	}

	var body: some View {
		GeometryReader { geo in
			let side = min(geo.size.width, geo.size.height)
			let thickness = side * 0.17
			ZStack {
				if arcs.isEmpty {
					Circle().stroke(Color(hex: ChartColors.free), lineWidth: thickness)
				} else {
					ForEach(arcs) { arc in
						Circle()
							.trim(from: arc.from, to: arc.to)
							.stroke(arc.color, style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
							.rotationEffect(.degrees(-90))  // 12시 방향에서 시계 방향으로
					}
				}
				VStack(spacing: 2) {
					Text(centerText)
						.font(.system(size: side * 0.085, weight: .semibold))
					if !caption.isEmpty {
						Text(caption)
							.font(.system(size: side * 0.06))
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(thickness / 2)
			.frame(width: side, height: side)
		}
	}
}

internal extension Color {
	/// "#rrggbb"
	init(hex: String) {
		var value: UInt64 = 0
		Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
		self.init(
			red: Double((value >> 16) & 0xff) / 255,
			green: Double((value >> 8) & 0xff) / 255,
			blue: Double(value & 0xff) / 255
		)
	}
}
#endif
