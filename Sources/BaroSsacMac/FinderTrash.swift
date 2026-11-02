#if os(macOS)
import Foundation
import BaroSsacCore

/// Finder 휴지통 이동 (유일한 삭제 경로 · 복구 가능) | rm 계열 미사용
public struct FinderTrash: TrashPort {
	public init() {}

	public func moveToTrash(_ path: String) throws {
		try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
	}
}
#endif
