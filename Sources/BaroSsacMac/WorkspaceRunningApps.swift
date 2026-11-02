#if os(macOS)
import AppKit
import BaroSsacCore

/// 실행 중 앱 번들 ID | `runningApplications`: 백그라운드 스레드 호출 안전
public struct WorkspaceRunningApps: RunningAppsPort {
	public init() {}

	public func runningBundleIdentifiers() -> Set<String> {
		Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
	}
}
#endif
