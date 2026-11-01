#if os(macOS)
import BaroSsacCore
import SwiftUI

internal enum SidebarItem: Hashable {
	case systemData
	case files(FileCategory)
	case duplicates
	case applications
}

/// 왼쪽 사이드바: 시스템 데이터 / 문서·사진·음악·동영상·다운로드·중복 파일 / 응용 프로그램.
internal struct RootView: View {
	@ObservedObject var system: ScanViewModel
	@ObservedObject var files: FilesViewModel
	@ObservedObject var apps: AppsViewModel
	@State private var selection: SidebarItem? = .systemData

	var body: some View {
		NavigationSplitView {
			// NavigationLink(value:) 는 행 어디를 클릭해도 선택된다 (태그만 붙이면 빈 곳 클릭이 무시될 수 있다).
			List(selection: $selection) {
				Section("정리") {
					sidebarLink(.systemData, "시스템 데이터", icon: "internaldrive", size: systemSize)
				}
				Section("파일") {
					ForEach(FileCategory.allCases, id: \.self) { category in
						sidebarLink(
							.files(category),
							category.title,
							icon: Self.icon(category),
							size: fileSize(category)
						)
					}
					sidebarLink(.duplicates, "중복 파일", icon: "doc.on.doc", size: duplicatesSize)
				}
				Section("앱") {
					sidebarLink(.applications, "응용 프로그램", icon: "square.grid.2x2", size: appsSize)
				}
			}
			.navigationSplitViewColumnWidth(min: 200, ideal: 230)
		} detail: {
			switch selection ?? .systemData {
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
		.frame(minWidth: 900, minHeight: 600)
		.onAppear { NSApp.activate(ignoringOtherApps: true) }
	}

	private func sidebarLink(_ item: SidebarItem, _ title: String, icon: String, size: String?) -> some View {
		NavigationLink(value: item) {
			HStack {
				Label(title, systemImage: icon)
				Spacer()
				if let size {
					Text(size).font(.callout).monospacedDigit().foregroundStyle(.secondary)
				}
			}
			.contentShape(Rectangle())
		}
	}

	private var systemSize: String? {
		system.hasReport ? system.presenter.totalText : nil
	}

	private func fileSize(_ category: FileCategory) -> String? {
		files.presenter.hasReport ? formatSize(files.presenter.totalBytes(category)) : nil
	}

	/// 중복 파일은 '사본을 지우면 확보되는 크기'를 보여 준다.
	private var duplicatesSize: String? {
		files.presenter.hasReport ? formatSize(files.presenter.duplicateReclaimableBytes) : nil
	}

	private var appsSize: String? {
		apps.presenter.isLoaded ? formatSize(apps.presenter.totalBytes) : nil
	}

	private static func icon(_ category: FileCategory) -> String {
		switch category {
		case .documents: "doc"
		case .pictures: "photo"
		case .music: "music.note"
		case .movies: "film"
		case .downloads: "arrow.down.circle"
		}
	}
}
#endif
