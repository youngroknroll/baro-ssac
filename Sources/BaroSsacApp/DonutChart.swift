#if os(macOS)
import BaroSsacCore
import SwiftUI

/// 도넛: 원 = 디스크 전체 · 조각 = 정리 가능 종류 | 가운데: 디스크 사용률
internal struct DonutChart: View {
	let segments: [ChartSegment]
	let centerText: String
	let caption: String

	/// 조각 사이 틈 (둘레 대비 비율) | 작은 조각은 틈 없음
	private static let gap = 0.006

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
			let inset = fraction > Self.gap * 3 ? Self.gap / 2 : 0
			return Arc(
				id: seg.key,
				color: Palette.color(seg.color),
				from: cursor + inset,
				to: cursor + fraction - inset
			)
		}
	}

	var body: some View {
		GeometryReader { geo in
			let side = min(geo.size.width, geo.size.height)
			let thickness = side * 0.12
			ZStack {
				Circle().stroke(Design.trackFill, lineWidth: thickness)
				ForEach(arcs) { arc in
					Circle()
						.trim(from: arc.from, to: arc.to)
						.stroke(arc.color, style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
						.rotationEffect(.degrees(-90))  // 시작: 12시 방향 · 시계 방향
				}
				VStack(spacing: 0) {
					Text(centerText)
						.font(.system(size: side * 0.12, weight: .bold, design: .rounded))
						.monospacedDigit()
						.minimumScaleFactor(0.6)
						.lineLimit(1)
					if !caption.isEmpty {
						Text(caption)
							.font(.system(size: side * 0.075))
							.foregroundStyle(.secondary)
					}
				}
				.padding(thickness * 1.4)
			}
			.padding(thickness / 2)
			.frame(width: side, height: side)
			.animation(.snappy, value: centerText)
		}
	}
}
#endif
