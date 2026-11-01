#if os(macOS)
import CoreServices
import Foundation

/// Spotlight 메타데이터 조회. Spotlight 색인이 꺼진 볼륨이면 nil.
internal enum SpotlightMetadata {
	/// Finder·Launch Services 로 마지막으로 연 날짜. 한 번도 열지 않았으면 nil.
	static func lastUsedDate(path: String) -> Date? {
		guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
		return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
	}
}
#endif
