#if os(macOS)
import CoreServices
import Foundation

/// Spotlight 메타데이터 조회 | 색인 꺼진 볼륨: nil
internal enum SpotlightMetadata {
	/// 마지막 사용일 (Finder · Launch Services 기준) | 열어 본 적 없음: nil
	static func lastUsedDate(path: String) -> Date? {
		guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
		return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
	}
}
#endif
