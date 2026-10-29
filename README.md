# baro-ssac (바로싹)

macOS의 캐시·로그·개발 도구 찌꺼기를 안전하게 정리하는 데스크톱 앱. Python 프로토타입과 같은 구조·같은 테스트를 Swift로 옮긴 것이다.

## 원칙

- 허용 목록 방식: `DefaultRules`에 정의된 경로만 다루고, 규칙마다 `exclude` 패턴으로 iCloud 동기화 상태 같은 민감한 캐시는 뺀다.
- 기본은 dry-run. 실제 정리는 Finder 휴지통 이동(`FileManager.trashItem`)이라 되돌릴 수 있다.
- 규칙 밖 경로, `..` 우회 경로, 다른 규칙 이름을 붙인 항목은 정리 요청이 와도 거부한다.
- 규칙의 세분성(`Granularity`)이 정리 단위를 정한다: `.root`(통째로), `.children`(앱별 폴더), `.files`(파일 단위 나이 판단).
- 위험도 HIGH는 경로별로 명시적 확인(`confirmedPaths`)이 있어야만 정리한다.
- 정리 직전에 경로가 아직 존재하고 심볼릭 링크가 아닌지 다시 확인한다(`.stale`).

## 구조

```
Sources/
├── BaroSsacCore/       # Foundation 외 의존 없음. Linux에서도 테스트됨
│   ├── Domain/           # Models, DefaultRules
│   ├── Application/      # Ports, ScanUseCase, CleanUseCase, PathUtil
│   └── Presentation/     # Presenter (그룹화·정렬·용량 표기·차트 조각·선택 상태)
├── BaroSsacMac/        # macOS 어댑터: LocalFileSystem, FinderTrash, LocalDisk, AppContainer
└── BaroSsacApp/        # SwiftUI: ScanViewModel, ContentView, DonutChart
Tests/BaroSsacCoreTests/ # XCTest 51개. 인메모리 파일시스템 fake 사용
```

의존 방향은 `BaroSsacApp → BaroSsacMac → BaroSsacCore`.

## 개발

Xcode 15 이상 (Swift 5.9+).

```bash
swift test                 # 코어 테스트
swift run BaroSsacApp    # 개발 중 바로 실행 (번들 없이 창만 뜸)
```

## 코드 스타일

[GitHub Swift Style Guide](https://github.com/github/swift-style-guide)를 따른다. 사람이 기억하는 대신 도구가 잡는다.

```bash
brew install swiftformat swiftlint
swiftformat .      # 탭 들여쓰기, 끝 공백, self 제거 등 자동 수정
swiftlint          # 강제 언래핑, 최상위 접근 제어 누락 등 경고
```

가이드에서 특히 지키는 것:

- 들여쓰기는 **탭**. 괄호에 맞춘 정렬 대신 한 단계 더 들여쓴다 (`.editorconfig`, `.swiftformat`).
- 최상위 타입·함수·변수에는 `public`/`internal`/`private`를 **항상 명시**한다. 중첩 정의는 기본값을 쓴다.
- `!` 강제 언래핑과 `Type!` 금지. 테스트에서는 `XCTUnwrap`.
- `struct` 우선. `class`가 필요하면(ObservableObject, 호출 기록용 스파이) `final`.
- `guard`로 먼저 빠져나간다. `self`는 클로저 캡처나 이름 충돌처럼 꼭 필요한 곳에만.
- 전역 상수 대신 `enum` 이름공간(`ChartColors.palette`).

커밋 전에 `swiftformat . && swiftlint && swift test`.

또는 `Package.swift`를 Xcode로 열면 ⌘U로 테스트, 스킴 `BaroSsacApp`으로 실행할 수 있다.

## 배포용 .app 만들기

SwiftPM은 `.app` 번들을 만들지 않으므로 Xcode 앱 프로젝트가 필요하다. 한 번만 하면 된다.

1. Xcode → File → New → Project → macOS → App. Product Name `baro-ssac`, Interface SwiftUI.
2. 생성된 `ContentView.swift`와 `baro_ssacApp.swift`를 지운다.
3. File → Add Package Dependencies… → Add Local… → 이 폴더(`baro-ssac`) 선택. 타깃에 `BaroSsacCore`, `BaroSsacMac`을 추가한다.
4. `Sources/BaroSsacApp/`의 `ScanViewModel.swift`, `ContentView.swift`, `DonutChart.swift`, `BaroSsacApp.swift`를 앱 타깃에 추가한다 (`main.swift`는 제외). `BaroSsacApp.swift`의 `struct BaroSsacApp` 위에 `@main`을 붙인다.
5. **Signing & Capabilities에서 App Sandbox를 제거한다.** 샌드박스가 켜져 있으면 홈 폴더가 컨테이너로 바뀌어 아무것도 찾지 못한다. (이 때문에 App Store 배포는 불가능하고, Developer ID 서명 + 공증으로 직접 배포한다.)
6. Product → Archive → Distribute App → Direct Distribution (Developer ID + 공증). 결과를 `.dmg`로 묶는다.

전체 디스크 접근 권한: iPhone 백업 폴더 등은 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에 앱을 추가해야 보인다. 권한이 없으면 해당 항목은 "권한이 없어 건너뜀"으로 표시된다.

## 다음 테스트 목록

- [ ] `RunningAppsPort`: 실행 중인 앱의 캐시 폴더는 "실행 중"으로 표시하고 기본 선택에서 제외 (`NSWorkspace.runningApplications`)
- [ ] 캐시 규칙에 "최근 1시간 안에 쓰인 항목은 건너뜀"
- [ ] 목록에 종류별 설명을 작은 글씨로 항상 표시
- [ ] 일반 청소 앱 확장: Spotlight(`NSMetadataQuery`)의 `kMDItemLastUsedDate`로 오래 열지 않은 대용량 문서·다운로드, 미사용 앱과 그 찌꺼기 탐지. 사용자 파일은 절대 기본 선택하지 않고 항목마다 이유를 표시
- [ ] `SnapshotPort`: `tmutil listlocalsnapshots /` 파싱 및 삭제
