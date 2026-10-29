import Foundation

public typealias ScanProgress = (_ done: Int, _ total: Int, _ rule: CleanupRule) -> Void

public struct ScanUseCase {
	private let fs: FileSystemPort
	private let clock: ClockPort

	public init(fs: FileSystemPort, clock: ClockPort) {
		self.fs = fs
		self.clock = clock
	}

	public func execute(_ rules: [CleanupRule], onProgress: ScanProgress? = nil) -> ScanReport {
		var report = ScanReport()
		for (index, rule) in rules.enumerated() {
			scan(rule, into: &report)
			onProgress?(index + 1, rules.count, rule)
		}
		return report
	}

	private func scan(_ rule: CleanupRule, into report: inout ScanReport) {
		guard fs.exists(rule.root) else {
			report.skipped.append(SkippedItem(path: rule.root, reason: .notFound))
			return
		}
		let cutoff = clock.now().addingTimeInterval(-Double(rule.minAgeDays) * 86_400)

		if rule.granularity == .root {
			consider(rule, rule.root, cutoff: cutoff, into: &report)
			return
		}
		let children: [String]
		do {
			children = try fs.listChildren(rule.root)
		} catch {
			report.skipped.append(SkippedItem(path: rule.root, reason: .permissionDenied))
			return
		}
		if rule.granularity == .children {
			for path in children {
				consider(rule, path, cutoff: cutoff, into: &report)
			}
		} else {
			walkFiles(rule, children, cutoff: cutoff, into: &report)
		}
	}

	private func walkFiles(_ rule: CleanupRule, _ paths: [String], cutoff: Date, into report: inout ScanReport) {
		var stack = Array(paths.reversed())
		while let path = stack.popLast() {
			if isExcluded(rule, path) {
				report.skipped.append(SkippedItem(path: path, reason: .excluded))
				continue
			}
			if fs.isDirectory(path) {
				do {
					stack.append(contentsOf: try fs.listChildren(path).reversed())
				} catch {
					report.skipped.append(SkippedItem(path: path, reason: .permissionDenied))
				}
				continue
			}
			consider(rule, path, cutoff: cutoff, into: &report)
		}
	}

	private func consider(_ rule: CleanupRule, _ path: String, cutoff: Date, into report: inout ScanReport) {
		if isExcluded(rule, path) {
			report.skipped.append(SkippedItem(path: path, reason: .excluded))
			return
		}
		let st: EntryStat
		do {
			st = try fs.stat(path)
		} catch {
			report.skipped.append(SkippedItem(path: path, reason: .permissionDenied))
			return
		}
		if st.isSymlink {
			report.skipped.append(SkippedItem(path: path, reason: .symlink))
		} else if rule.minAgeDays > 0 && st.modifiedAt > cutoff {
			report.skipped.append(SkippedItem(path: path, reason: .tooRecent))
		} else {
			report.items.append(ScanItem(ruleName: rule.name, path: path, sizeBytes: st.sizeBytes, risk: rule.risk))
		}
	}

	private func isExcluded(_ rule: CleanupRule, _ path: String) -> Bool {
		guard !rule.exclude.isEmpty, let rel = PathUtil.relative(path, to: rule.root), rel != "." else {
			return false
		}
		return rule.exclude.contains { PathUtil.matches($0, rel) }
	}
}
