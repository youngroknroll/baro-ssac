#if os(macOS)
import BaroSsacCore
import CryptoKit
import Foundation

/// 파일 내용의 SHA-256. 표본 모드는 앞 1MB + 뒤 1MB + 크기만 읽는다.
public struct SHA256ContentHash: ContentHashPort {
	private static let chunkSize = 1 << 20

	public init() {}

	public func hash(of path: String, sampleOnly: Bool) throws -> String {
		let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
		defer { try? handle.close() }

		var hasher = SHA256()
		if sampleOnly {
			if let head = try handle.read(upToCount: Self.chunkSize) {
				hasher.update(data: head)
			}
			let end = try handle.seekToEnd()
			let chunk = UInt64(Self.chunkSize)
			if end > chunk {
				try handle.seek(toOffset: end - chunk)
				if let tail = try handle.read(upToCount: Self.chunkSize) {
					hasher.update(data: tail)
				}
			}
			hasher.update(data: Data(String(end).utf8))
		} else {
			while let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty {
				hasher.update(data: data)
			}
		}
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}
}
#endif
