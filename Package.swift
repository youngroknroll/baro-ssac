// swift-tools-version:5.9
import PackageDescription

let package = Package(
	name: "baro-ssac",
	platforms: [.macOS(.v14)],
	products: [
		.library(name: "BaroSsacCore", targets: ["BaroSsacCore"]),
		.library(name: "BaroSsacMac", targets: ["BaroSsacMac"]),
		.executable(name: "BaroSsacApp", targets: ["BaroSsacApp"]),
	],
	targets: [
		// 도메인 · 유스케이스 · 프레젠터 | 의존: Foundation 만 | Linux 테스트 가능
		.target(name: "BaroSsacCore"),
		// macOS 어댑터: FileManager · 휴지통 · 볼륨 용량 · Spotlight · 앱 목록
		.target(name: "BaroSsacMac", dependencies: ["BaroSsacCore"]),
		// SwiftUI 화면 | 배포용 .app: Xcode 앱 프로젝트에서 이 소스 참조 (README)
		.executableTarget(name: "BaroSsacApp", dependencies: ["BaroSsacCore", "BaroSsacMac"]),
		.testTarget(name: "BaroSsacCoreTests", dependencies: ["BaroSsacCore"]),
	]
)
