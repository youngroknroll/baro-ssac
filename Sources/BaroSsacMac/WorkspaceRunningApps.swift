#if os(macOS)
import AppKit
import BaroSsacCore

/// 지금 실행 중인 앱의 번들 ID. `runningApplications` 는 백그라운드 스레드에서 불러도 안전하다.
public struct WorkspaceRunningApps: RunningAppsPort {
	public init() {}

	public func runningBundleIdentifiers() -> Set<String> {
		Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
	}
}
#endif
