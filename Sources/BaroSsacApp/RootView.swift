#if os(macOS)
import BaroSsacCore
import SwiftUI

internal enum SidebarItem: Hashable {
	case systemData
	case files(FileCategory)
	case duplicates
	case applications
}

/// 사이드바: 시스템 데이터 / 문서 · 사진 · 음악 · 동영상 · 다운로드 · 중복 파일 / 응용 프로그램
/// 스캔 후 크기 배지 표시 (Mail 읽지 않은 수 방식)
internal struct RootView: View {
	@ObservedObject var system: ScanViewModel
	@ObservedObject var files: FilesViewModel
	@ObservedObject var apps: AppsViewModel
	@State private var selection: SidebarItem? = .systemData

	var body: some View {
		NavigationSplitView {
			List(selection: $selection) {
				Section("정리") {
					link(.systemData, "시스템 데이터", icon: "internaldrive", badge: systemSize)
				}
				Section("파일") {
					ForEach(FileCategory.allCases, id: \.self) { category in
						link(
							.files(category),
							category.title,
							icon: FilesView.icon(category),
							badge: fileSize(category)
						)
					}
					link(.duplicates, "중복 파일", icon: "doc.on.doc", badge: duplicatesSize)
				}
				Section("앱") {
					link(.applications, "응용 프로그램", icon: "square.grid.2x2", badge: appsSize)
				}
			}
			.navigationSplitViewColumnWidth(min: 200, ideal: 230)
		} detail: {
			detail(selection ?? .systemData)
				// 선택 변경 시 상세 화면 재생성 | 미지정 시 사이드바 강조만 바뀌고 상세 미갱신
				// (2026-11-02 사용자 화면에서 확인)
				.id(selection)
		}
		.frame(minWidth: 940, minHeight: 620)
		.onAppear { NSApp.activate(ignoringOtherApps: true) }
	}

	@ViewBuilder
	private func detail(_ item: SidebarItem) -> some View {
		switch item {
		case .systemData:
			SystemDataView(model: system)
		case let .files(category):
			FilesView(category: category, model: files)
		case .duplicates:
			DuplicatesView(model: files)
		case .applications:
			AppsView(model: apps)
		}
	}

	private func link(_ item: SidebarItem, _ title: String, icon: String, badge: String?) -> some View {
		Label(title, systemImage: icon)
			.badge(badge.map { Text($0).monospacedDigit() })
			.tag(item)
	}

	private var systemSize: String? {
		system.hasScanned ? system.presenter.totalText : nil
	}

	private func fileSize(_ category: FileCategory) -> String? {
		files.hasScanned ? formatSize(files.presenter.totalBytes(category)) : nil
	}

	/// 중복 파일 배지: 사본 제거 시 확보 용량
	private var duplicatesSize: String? {
		files.hasScanned ? formatSize(files.presenter.duplicateReclaimableBytes) : nil
	}

	private var appsSize: String? {
		apps.presenter.isLoaded ? formatSize(apps.presenter.totalBytes) : nil
	}
}
#endif
