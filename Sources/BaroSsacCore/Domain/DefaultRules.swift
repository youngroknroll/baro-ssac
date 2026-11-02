// macOS 기본 정리 규칙
//
// 범위: 관리자 권한 불필요한 사용자 홈 하위 경로
// 별도 포트 대상: Time Machine 로컬 스냅샷 · Docker 디스크 이미지 등
// (파일 삭제 아닌 명령 처리 항목)
import Foundation

public enum DefaultRules {
	/// 금지 경로: 규칙 루트가 이 경로 자체 · 하위 · 상위 불가
	public static let forbiddenRoots: [String] = [
		"/System",
		"/Library",
		"/Applications",
		"/usr",
		"/bin",
		"/sbin",
		"/private/var/folders",  // 실행 중 프로세스 임시 파일 (재부팅 시 정리)
		"/private/var/vm",       // 스왑 · sleepimage
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
					"com.apple.Safari",     // 삭제 시 Safari 속도 저하 · 로그인 해제 가능
					"com.apple.akd",        // Apple ID 인증
				],
				title: "앱 캐시",
				description: "Homebrew · pip · 브라우저 등 앱 캐시 · 필요 시 앱이 재생성"
			),
			CleanupRule(
				name: "user-logs", root: "\(lib)/Logs", risk: .low, minAgeDays: 7, granularity: .files,
				title: "오래된 로그",
				description: "7일 지난 앱 로그 파일"
			),
			CleanupRule(
				name: "xcode-derived-data", root: "\(xcode)/DerivedData", risk: .low,
				title: "Xcode 빌드 데이터",
				description: "빌드 중간 산출물 · 다음 빌드 때 재생성"
			),
			CleanupRule(
				name: "xcode-device-support", root: "\(xcode)/iOS DeviceSupport", risk: .medium,
				title: "iOS 디버그 심볼",
				description: "디버그 심볼 · 기기 연결 시 재다운로드"
			),
			CleanupRule(
				name: "xcode-archives", root: "\(xcode)/Archives", risk: .high,
				title: "Xcode 아카이브",
				description: "배포 빌드 아카이브 · dSYM · 크래시 분석에 필요할 수 있음"
			),
			CleanupRule(
				name: "simulator-caches", root: "\(lib)/Developer/CoreSimulator/Caches", risk: .low,
				title: "시뮬레이터 캐시",
				description: "iOS 시뮬레이터 캐시"
			),
			CleanupRule(
				name: "npm-cache", root: "\(home)/.npm/_cacache", risk: .low, granularity: .root,
				title: "npm 캐시",
				description: "npm 패키지 캐시 · 인덱스와 내용 한 쌍 · 통째로 정리"
			),
			CleanupRule(
				name: "xdg-cache", root: "\(home)/.cache", risk: .medium,
				title: "CLI 도구 캐시",
				description: "uv · pip · pre-commit · Hugging Face 모델 등 · 재다운로드에 시간 소요"
			),
			CleanupRule(
				name: "gradle-caches", root: "\(home)/.gradle/caches", risk: .medium,
				title: "Gradle 캐시",
				description: "Gradle 의존성 캐시 · 다음 빌드 때 재다운로드"
			),
			CleanupRule(
				name: "maven-repo", root: "\(home)/.m2/repository", risk: .medium,
				title: "Maven 저장소",
				description: "Maven 로컬 저장소 · 다음 빌드 때 재다운로드"
			),
			CleanupRule(
				name: "ios-backups", root: "\(lib)/Application Support/MobileSync/Backup", risk: .high,
				title: "iPhone 백업",
				description: "iPhone · iPad 로컬 백업 · 삭제 시 복구 불가"
			),
		]
	}
}
