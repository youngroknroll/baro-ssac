// 캐시 폴더 ↔ 실행 중 앱 매칭 (IO 없는 순수 규칙)
import Foundation

public enum AppMatching {
	/// 반환: 마지막 경로 이름 = 번들 ID 또는 `번들ID.` 접두 시 해당 번들 ID
	/// 대소문자 무시 | 해당 앱 없음: nil
	public static func owner(of path: String, running: Set<String>) -> String? {
		let name = PathUtil.basename(path).lowercased()
		return running
			.sorted()
			.first { id in
				let lowered = id.lowercased()
				return name == lowered || name.hasPrefix(lowered + ".")
			}
	}
}
