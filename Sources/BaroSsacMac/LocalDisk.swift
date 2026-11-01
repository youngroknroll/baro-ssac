#if os(macOS)
import Foundation
import BaroSsacCore

/// 주어진 경로가 속한 볼륨의 용량. "여유"는 Finder가 보여 주는 값과 같은 기준(purgeable 포함)이다.
public struct LocalDisk: DiskPort {
	private let path: String

	public init(path: String) {
		self.path = path
	}

	public func usage() -> DiskUsage? {
		let url = URL(fileURLWithPath: path)
		let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
		guard
			let values = try? url.resourceValues(forKeys: keys),
			let total = values.volumeTotalCapacity,
			let free = values.volumeAvailableCapacityForImportantUsage
		else { return nil }
		return DiskUsage(totalBytes: Int64(total), freeBytes: free)
	}
}

public struct SystemClock: ClockPort {
	public init() {}
	public func now() -> Date { Date() }
}
#endif
