// swift-tools-version:5.9
import PackageDescription

let package = Package(
	name: "baro-ssac",
	platforms: [.macOS(.v13)],
	products: [
		.library(name: "BaroSsacCore", targets: ["BaroSsacCore"]),
		.library(name: "BaroSsacMac", targets: ["BaroSsacMac"]),
		.executable(name: "BaroSsacApp", targets: ["BaroSsacApp"]),
	],
	targets: [
		// 도메인 + 유스케이스 + 프레젠터. Foundation 외 의존 없음. Linux에서도 테스트 가능.
		.target(name: "BaroSsacCore"),
		// macOS 어댑터: FileManager, 휴지통, 볼륨 용량.
		.target(name: "BaroSsacMac", dependencies: ["BaroSsacCore"]),
		// SwiftUI 화면. 배포용 .app 은 Xcode 앱 프로젝트에서 이 타깃의 소스를 참조한다 (README 참고).
		.executableTarget(name: "BaroSsacApp", dependencies: ["BaroSsacCore", "BaroSsacMac"]),
		.testTarget(name: "BaroSsacCoreTests", dependencies: ["BaroSsacCore"]),
	]
)
