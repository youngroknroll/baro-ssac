#if os(macOS)
import BaroSsacMac
import SwiftUI

internal struct BaroSsacApp: App {
	@StateObject private var system: ScanViewModel
	@StateObject private var files: FilesViewModel
	@StateObject private var apps: AppsViewModel

	init() {
		let container = AppContainer.live()
		_system = StateObject(wrappedValue: ScanViewModel(container: container))
		_files = StateObject(wrappedValue: FilesViewModel(container: container))
		_apps = StateObject(wrappedValue: AppsViewModel(container: container))
	}

	var body: some Scene {
		WindowGroup("baro-ssac") {
			RootView(system: system, files: files, apps: apps)
		}
		.defaultSize(width: 1000, height: 680)
	}
}
#endif
