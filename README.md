# baro-ssac (바로싹)

macOS 저장 공간을 정리하는 데스크톱 앱. 시스템 데이터(캐시·로그·개발 도구 찌꺼기), 사용자 파일(문서·사진·음악·동영상·다운로드), 응용 프로그램을 한 곳에서 보고 휴지통으로 보낸다.

## 화면

왼쪽 사이드바에 **시스템 데이터 · 문서 · 사진 · 음악 · 동영상 · 다운로드 · 중복 파일 · 응용 프로그램**. 스캔하면 각 항목 옆에 크기가 표시된다.

- **시스템 데이터**: 캐시·로그·개발 도구 찌꺼기. 도넛(원 = 디스크 전체)과 종류별 목록.
- **문서·사진·음악·동영상·다운로드**: "정리 추천"과 "전체(크기순)" 두 가지 보기. 추천 이유를 항목마다 표시한다.
  - 중복: 내용이 같은 파일. 크기 → 앞·뒤 1MB 표본 해시 → 전체 SHA-256 순으로 좁혀 비싼 읽기를 줄인다. 다운로드 폴더 밖, 더 오래된 사본을 원본으로 남긴다.
  - 설치 파일: 다운로드 폴더의 .dmg / .pkg / .mpkg / .xip / .iso
  - 오래 안 연 큰 파일: 100MB 이상이고 1년 넘게 열지 않음 (Spotlight 마지막 사용일, 없으면 수정일)
  - 문서 = ~/Documents + ~/Desktop. 1MB 미만 파일은 목록에 올리지 않고 합계에만 더한다.
  - 행을 우클릭하면 Finder에서 보기 / 열기.
- **중복 파일**: 내용이 같은 파일을 묶음으로 보여 준다. 묶음마다 원본(남김)과 사본을 표시하고, "사본 모두 선택"으로 원본만 남길 수 있다. 원본까지 모두 지우려 하면 확인 창에서 경고한다. 사이드바에는 사본을 지우면 확보되는 크기가 표시된다.
- **응용 프로그램**: 관련 파일까지 합친 크기순. "삭제…"를 누르면 앱과 그 앱이 남긴 파일(Application Support, Containers, Preferences, Caches 등)을 골라 휴지통으로 보낸다. 번들 ID로 찾은 파일은 기본 선택, 이름으로 찾은 파일은 확인 후 직접 선택.

## 원칙

- 허용 목록 방식: `DefaultRules`에 정의된 경로만 다루고, 규칙마다 `exclude` 패턴으로 iCloud 동기화 상태 같은 민감한 캐시는 뺀다.
- 기본은 dry-run. 실제 정리는 Finder 휴지통 이동(`FileManager.trashItem`)이라 되돌릴 수 있다.
- 규칙 밖 경로, `..` 우회 경로, 다른 규칙 이름을 붙인 항목은 정리 요청이 와도 거부한다.
- 규칙의 세분성(`Granularity`)이 정리 단위를 정한다: `.root`(통째로), `.children`(앱별 폴더), `.files`(파일 단위 나이 판단).
- 위험도 HIGH는 경로별로 명시적 확인(`confirmedPaths`)이 있어야만 정리한다.
- 정리 직전에 경로가 아직 존재하고 심볼릭 링크가 아닌지 다시 확인한다(`.stale`).
- 사용자 파일은 추천이 있어도 **절대 기본 선택하지 않는다.** 휴지통으로 보내기 전에 항상 확인 창을 띄운다.
- 사진 보관함·음악 보관함·iMovie·Final Cut 라이브러리는 크기만 보여 주고 선택할 수 없다 (일부만 지우면 라이브러리가 깨진다). 그 안의 파일도 마찬가지.
- macOS 기본 앱(`com.apple.*`)과 실행 중인 앱은 지우지 않는다. 앱 관련 파일은 정해진 ~/Library 하위 폴더 안만 허용한다. 여러 앱이 함께 쓰는 Group Containers는 건드리지 않는다.
- iCloud에만 있고 Mac에 내려받지 않은 파일은 할당 크기가 0이라 목록과 중복 검사에서 빠진다 (해시하려다 내려받지 않는다).
- 실행 중인 앱의 캐시(폴더 이름이 번들 ID이거나 `번들ID.`로 시작)는 "실행 중"으로 표시하고 기본 선택에서 뺀다. 정리 시점에도 실행 중이면 사용자가 골랐어도 보내지 않는다(`.inUse`).

## 구조

```
Sources/
├── BaroSsacCore/       # Foundation 외 의존 없음. Linux에서도 테스트됨
│   ├── Domain/           # Models·DefaultRules(캐시 규칙), Files(사용자 파일), Apps(앱·관련 파일), AppMatching
│   ├── Application/      # Ports, ScanUseCase·CleanUseCase(캐시), FileScanUseCase, AppScanUseCase, TrashFilesUseCase
│   └── Presentation/     # Presenter(시스템 데이터), FilesPresenter, AppsPresenter
├── BaroSsacMac/        # macOS 어댑터: LocalFileSystem, LocalFileWalker, SHA256ContentHash, LocalAppCatalog,
│                       #   SpotlightMetadata, FinderTrash, LocalDisk, WorkspaceRunningApps, AppContainer
└── BaroSsacApp/        # SwiftUI: RootView(사이드바), SystemDataView, FilesView, AppsView, 각 ViewModel
Tests/BaroSsacCoreTests/ # XCTest. 인메모리 파일시스템·가짜 순회기·가짜 해시 사용
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
4. `Sources/BaroSsacApp/`의 `.swift` 파일을 모두 앱 타깃에 추가한다 (`main.swift`는 제외). `BaroSsacApp.swift`의 `struct BaroSsacApp` 위에 `@main`을 붙인다.
5. **Signing & Capabilities에서 App Sandbox를 제거한다.** 샌드박스가 켜져 있으면 홈 폴더가 컨테이너로 바뀌어 아무것도 찾지 못한다. (이 때문에 App Store 배포는 불가능하고, Developer ID 서명 + 공증으로 직접 배포한다.)
6. Product → Archive → Distribute App → Direct Distribution (Developer ID + 공증). 결과를 `.dmg`로 묶는다.

전체 디스크 접근 권한: iPhone 백업 폴더 등은 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에 앱을 추가해야 보인다. 권한이 없으면 해당 항목은 "권한이 없어 건너뜀"으로 표시된다.

## 다음 테스트 목록

- [ ] 캐시 규칙에 "최근 1시간 안에 쓰인 항목은 건너뜀"
- [ ] 목록에 종류별 설명을 작은 글씨로 항상 표시
- [ ] Docker: `docker system df` 로 비울 수 있는 양 표시, `docker system prune` 실행 (파일 직접 삭제 대신 명령 기반 포트)
- [ ] 사용자가 판단 기준(기간·크기)을 바꿀 수 있게
- [ ] `SnapshotPort`: `tmutil listlocalsnapshots /` 파싱 및 삭제
