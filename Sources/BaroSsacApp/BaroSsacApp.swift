#if os(macOS)
import SwiftUI
import BaroSsacMac

internal struct BaroSsacApp: App {
	@StateObject private var model = ScanViewModel(container: .live())

	var body: some Scene {
		WindowGroup("baro-ssac") {
			ContentView(model: model)
		}
		.windowResizability(.contentSize)
	}
}
#endif
