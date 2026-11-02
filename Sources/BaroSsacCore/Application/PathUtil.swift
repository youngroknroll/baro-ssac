// 경로 처리 순수 함수
// 직접 구현 이유: Foundation standardizingPath 의 플랫폼 의존 동작 (/private 접두사 변경 등)
import Foundation
#if canImport(Glibc)
import Glibc
#endif

public enum PathUtil {
	/// `.` · `..` 정리 | 심볼릭 링크 미해석
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

	/// `root` 의 엄격한 하위 경로 여부 (root 자체: false)
	public static func isStrictlyInside(_ path: String, root: String) -> Bool {
		let p = normalize(path)
		let r = normalize(root)
		return p != r && p.hasPrefix(r + "/")
	}

	/// `root` 기준 상대 경로 | 하위 아님: nil · 동일: "."
	public static func relative(_ path: String, to root: String) -> String? {
		let p = normalize(path)
		let r = normalize(root)
		if p == r { return "." }
		guard p.hasPrefix(r + "/") else { return nil }
		return String(p.dropFirst(r.count + 1))
	}

	/// POSIX fnmatch | `*` 가 `/` 도 매칭 (Python fnmatch 동일)
	public static func matches(_ pattern: String, _ name: String) -> Bool {
		fnmatch(pattern, name, 0) == 0
	}
}
