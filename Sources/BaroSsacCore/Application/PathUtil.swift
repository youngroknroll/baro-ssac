// 경로 처리. Foundation의 standardizingPath는 /private 접두사를 바꾸는 등 플랫폼 의존적이라
// 테스트 가능한 순수 함수로 직접 구현한다.
import Foundation
#if canImport(Glibc)
import Glibc
#endif

public enum PathUtil {
	/// `.`과 `..`을 정리한다. 심볼릭 링크는 건드리지 않는다.
	public static func normalize(_ path: String) -> String {
		let isAbsolute = path.hasPrefix("/")
		var parts: [String] = []
		for component in path.split(separator: "/", omittingEmptySubsequences: true) {
			switch component {
			case ".":
				continue
			case "..":
				if let last = parts.last, last != ".." {
					parts.removeLast()
				} else if !isAbsolute {
					parts.append("..")
				}
			default:
				parts.append(String(component))
			}
		}
		let joined = parts.joined(separator: "/")
		if isAbsolute { return "/" + joined }
		return joined.isEmpty ? "." : joined
	}

	public static func basename(_ path: String) -> String {
		path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
	}

	/// `path`가 `root`의 엄격한 하위 경로인지 (root 자체는 false).
	public static func isStrictlyInside(_ path: String, root: String) -> Bool {
		let p = normalize(path)
		let r = normalize(root)
		return p != r && p.hasPrefix(r + "/")
	}

	/// `root` 기준 상대 경로. 하위가 아니면 nil, 같으면 ".".
	public static func relative(_ path: String, to root: String) -> String? {
		let p = normalize(path)
		let r = normalize(root)
		if p == r { return "." }
		guard p.hasPrefix(r + "/") else { return nil }
		return String(p.dropFirst(r.count + 1))
	}

	/// POSIX fnmatch. `*`는 `/`도 포함해 매칭한다 (Python fnmatch와 같은 동작).
	public static func matches(_ pattern: String, _ name: String) -> Bool {
		fnmatch(pattern, name, 0) == 0
	}
}
