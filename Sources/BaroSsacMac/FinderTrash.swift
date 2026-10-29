#if os(macOS)
import Foundation
import BaroSsacCore

/// Finder 휴지통으로 이동한다. 되돌릴 수 있는 유일한 삭제 경로이므로 rm 계열은 쓰지 않는다.
public struct FinderTrash: TrashPort {
	public init() {}

	public func moveToTrash(_ path: String) throws {
		try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
	}
}
#endif
