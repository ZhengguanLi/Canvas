import Foundation

struct GitStatus: Equatable, Sendable {
    var branch: String
    var changedFiles: Int
    var isWorktree: Bool
    var error: String? = nil
    var summary: String {
        if let error { return L10n.tr(error) }
        return "\(branch) · \(changedFiles == 0 ? L10n.tr("干净") : L10n.format("%d 项变更", changedFiles))\(isWorktree ? " · worktree" : "")"
    }

    static func parse(_ text: String, isWorktree: Bool) -> GitStatus {
        let records = text.contains("\0") ? text.split(separator: "\0", omittingEmptySubsequences: true) : text.split(separator: "\n")
        var branch = "HEAD"
        var count = 0
        var skipRenameSource = false
        for record in records {
            if record.hasPrefix("## ") {
                var name = String(record.dropFirst(3))
                for prefix in ["No commits yet on ", "Initial commit on "] where name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
                branch = name.components(separatedBy: "...").first ?? name
            } else if skipRenameSource {
                skipRenameSource = false
            } else {
                count += 1
                skipRenameSource = text.contains("\0") && record.prefix(2).contains(where: { $0 == "R" || $0 == "C" })
            }
        }
        return GitStatus(branch: branch, changedFiles: count, isWorktree: isWorktree)
    }

    static func read(at directory: URL) -> GitStatus {
        do {
            let result = try ProcessRunner.run(executable: "/usr/bin/git", arguments: ["status", "--porcelain=v1", "--branch", "-z", "--untracked-files=normal"], directory: directory)
            guard result.status == 0 else { return GitStatus(branch: "", changedFiles: 0, isWorktree: false, error: "非 Git 仓库 / 不可读取") }
            let gitDir = try ProcessRunner.run(executable: "/usr/bin/git", arguments: ["rev-parse", "--absolute-git-dir"], directory: directory)
            let common = try ProcessRunner.run(executable: "/usr/bin/git", arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"], directory: directory)
            return parse(result.output, isWorktree: gitDir.status == 0 && common.status == 0 && gitDir.output != common.output)
        } catch {
            return GitStatus(branch: "", changedFiles: 0, isWorktree: false, error: "Git 状态不可用")
        }
    }
}
