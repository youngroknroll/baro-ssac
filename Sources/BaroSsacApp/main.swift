// SwiftPM 실행 진입점 | Xcode 앱 프로젝트: 이 파일 대신 BaroSsacApp 에 @main
#if os(macOS)
import AppKit

// `swift run` (번들 없음) 실행 시에도 Dock 표시 · 창 활성화
NSApplication.shared.setActivationPolicy(.regular)
BaroSsacApp.main()
#else
print("baro-ssac: macOS 전용")
#endif
