#if os(macOS)
import BaroSsacCore
import Foundation

/// FileWalkerPort 의 실제 구현.
///
/// 크기는 실제 할당 크기다. iCloud 에만 있고 Mac 에 내려받지 않은 파일은 0 이 되어
/// 목록과 중복 검사에서 자연스럽게 빠진다 (해시를 계산하려다 내려받는 일이 없다).
public struct LocalFileWalker: FileWalkerPort {
	private let fs = LocalFileSystem()

	public init() {}

	public func listFiles(under root: String, minSize: Int64) throws -> FileListing {
		do {
			_ = try FileManager.default.contentsOfDirectory(atPath: root)
		} catch {
			throw FileSystemError.permissionDenied(root)
		}

		let keys: [URLResourceKey] = [
			.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
			.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
		]
		guard let enumerator = FileManager.default.enumerator(
			at: URL(fileURLWithPath: root, isDirectory: true),
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles, .skipsPackageDescendants],
			errorHandler: { _, _ in true }  // 읽을 수 없는 하위 폴더는 건너뛰고 계속
		) else {
			return FileListing()
		}

		var listing = FileListing()
		let keySet = Set(keys)
		for case let url as URL in enumerator {
			guard let values = try? url.resourceValues(forKeys: keySet), values.isSymbolicLink != true else { continue }
			let isPackage = values.isPackage == true
			if values.isDirectory == true && !isPackage { continue }

			let size: Int64
			if isPackage {
				size = (try? fs.stat(url.path).sizeBytes) ?? 0
			} else {
				size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
			}
			listing.totalBytes += size
			guard size >= minSize else { continue }

			listing.records.append(FileRecord(
				path: url.path,
				sizeBytes: size,
				modifiedAt: values.contentModificationDate ?? .distantPast,
				lastUsedAt: SpotlightMetadata.lastUsedDate(path: url.path),
				isPackage: isPackage
			))
		}
		return listing
	}
}
#endif
