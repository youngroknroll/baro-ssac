// 캐시 폴더가 어떤 실행 중인 앱의 것인지 판단한다. IO 없는 순수 규칙.
import Foundation

public enum AppMatching {
	/// `path`의 마지막 이름이 실행 중인 앱의 번들 ID와 같거나 `번들ID.`로 시작하면 그 번들 ID.
	/// 대소문자는 구분하지 않는다. 해당하는 앱이 없으면 nil.
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
