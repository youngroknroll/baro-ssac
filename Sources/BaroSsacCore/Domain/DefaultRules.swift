// macOS 기본 정리 규칙.
//
// 1단계는 관리자 권한 없이 정리 가능한 사용자 홈 아래 경로만 다룬다.
// Time Machine 로컬 스냅샷, Docker 디스크 이미지처럼 '파일 삭제'가 아닌
// 명령으로 처리해야 하는 항목은 별도 포트로 다룬다.
import Foundation

public enum DefaultRules {
	/// 어떤 규칙도 이 경로이거나, 이 경로 안이거나, 이 경로를 포함해서는 안 된다.
	public static let forbiddenRoots: [String] = [
		"/System",
		"/Library",
		"/Applications",
		"/usr",
		"/bin",
		"/sbin",
		"/private/var/folders",  // 실행 중인 프로세스의 임시파일 (재부팅 시 정리됨)
		"/private/var/vm",       // 스왑 / sleepimage
	]

	public static func rules(home: String) -> [CleanupRule] {
		let lib = "\(home)/Library"
		let xcode = "\(lib)/Developer/Xcode"
		return [
			CleanupRule(
				name: "app-caches", root: "\(lib)/Caches", risk: .low,
				exclude: [
					"com.apple.bird",       // iCloud Drive 동기화 상태
					"CloudKit*",            // iCloud 앱 데이터 캐시
					"com.apple.HomeKit*",
					"com.apple.Safari",     // 지우면 Safari가 느려지고 로그인 상태가 풀릴 수 있음
					"com.apple.akd",        // Apple ID 인증
				],
				title: "앱 캐시",
				description: "Homebrew, pip, 브라우저 등 앱이 만든 캐시. 필요하면 앱이 다시 만듭니다"
			),
			CleanupRule(
				name: "user-logs", root: "\(lib)/Logs", risk: .low, minAgeDays: 7, granularity: .files,
				title: "오래된 로그",
				description: "7일이 지난 앱 로그 파일"
			),
			CleanupRule(
				name: "xcode-derived-data", root: "\(xcode)/DerivedData", risk: .low,
				title: "Xcode 빌드 데이터",
				description: "빌드 중간 산출물. 다음 빌드 때 다시 만들어집니다"
			),
			CleanupRule(
				name: "xcode-device-support", root: "\(xcode)/iOS DeviceSupport", risk: .medium,
				title: "iOS 디버그 심볼",
				description: "기기를 연결하면 다시 내려받는 디버그 심볼"
			),
			CleanupRule(
				name: "xcode-archives", root: "\(xcode)/Archives", risk: .high,
				title: "Xcode 아카이브",
				description: "배포한 빌드의 아카이브와 dSYM. 크래시 분석에 필요할 수 있습니다"
			),
			CleanupRule(
				name: "simulator-caches", root: "\(lib)/Developer/CoreSimulator/Caches", risk: .low,
				title: "시뮬레이터 캐시",
				description: "iOS 시뮬레이터 캐시"
			),
			CleanupRule(
				name: "npm-cache", root: "\(home)/.npm/_cacache", risk: .low, granularity: .root,
				title: "npm 캐시",
				description: "npm 패키지 캐시. 인덱스와 내용이 한 쌍이라 통째로 정리합니다"
			),
			CleanupRule(
				name: "xdg-cache", root: "\(home)/.cache", risk: .medium,
				title: "CLI 도구 캐시",
				description: "uv, pip, pre-commit, Hugging Face 모델 등. 다시 받는 데 오래 걸릴 수 있습니다"
			),
			CleanupRule(
				name: "gradle-caches", root: "\(home)/.gradle/caches", risk: .medium,
				title: "Gradle 캐시",
				description: "Gradle 의존성 캐시. 다음 빌드 때 다시 내려받습니다"
			),
			CleanupRule(
				name: "maven-repo", root: "\(home)/.m2/repository", risk: .medium,
				title: "Maven 저장소",
				description: "Maven 로컬 저장소. 다음 빌드 때 다시 내려받습니다"
			),
			CleanupRule(
				name: "ios-backups", root: "\(lib)/Application Support/MobileSync/Backup", risk: .high,
				title: "iPhone 백업",
				description: "iPhone/iPad 로컬 백업. 지우면 복구할 수 없습니다"
			),
		]
	}
}
