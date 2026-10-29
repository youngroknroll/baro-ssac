// SwiftPM 실행 타깃의 진입점. Xcode 앱 프로젝트에서는 이 파일 대신 BaroSsacApp 에 @main 을 붙인다.
#if os(macOS)
import AppKit

// 번들 없이 `swift run` 으로 띄울 때도 Dock 에 나타나고 창이 앞으로 오게 한다.
NSApplication.shared.setActivationPolicy(.regular)
BaroSsacApp.main()
#else
print("baro-ssac은 macOS에서만 실행됩니다.")
#endif
