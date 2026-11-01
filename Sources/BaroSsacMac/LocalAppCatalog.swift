#if os(macOS)
import BaroSsacCore
import Foundation

/// /Applications 와 ~/Applications 의 앱. 하위 폴더(예: /Applications/Utilities)는 한 단계까지 본다.
public struct LocalAppCatalog: AppCatalogPort {
	private let roots: [String]
	private let fs = LocalFileSystem()

	public init(home: String) {
		roots = ["/Applications", "\(home)/Applications"]
	}

	public func installedApps() -> [InstalledApp] {
		roots
			.flatMap { appBundles(in: $0, depth: 2) }
			.map(app(at:))
	}

	private func appBundles(in directory: String, depth: Int) -> [String] {
		guard depth > 0, let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
			return []
		}
		var result: [String] = []
		for name in names.sorted() where !name.hasPrefix(".") {
			let path = directory + "/" + name
			if fs.isSymlink(path) { continue }
			if name.hasSuffix(".app") {
				result.append(path)
			} else if fs.isDirectory(path) {
				result += appBundles(in: path, depth: depth - 1)
			}
		}
		return result
	}

	private func app(at path: String) -> InstalledApp {
		let bundle = Bundle(path: path)
		let fileName = String(PathUtil.basename(path).dropLast(".app".count))
		let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
			?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
			?? fileName
		return InstalledApp(
			path: path,
			name: name,
			bundleID: bundle?.bundleIdentifier,
			sizeBytes: (try? fs.stat(path).sizeBytes) ?? 0,
			lastUsedAt: SpotlightMetadata.lastUsedDate(path: path)
		)
	}
}
#endif
