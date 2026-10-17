import XCTest
@testable import ProjectCanvas

final class ProjectKindTests: XCTestCase {
    func testDetectsKindFromMarkerFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectKindTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func folder(_ files: [String]) throws -> URL {
            let url = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for file in files { FileManager.default.createFile(atPath: url.appendingPathComponent(file).path, contents: Data()) }
            return url
        }
        XCTAssertEqual(ProjectKind.detect(at: try folder(["Package.swift", "package.json"])), .swift)
        XCTAssertEqual(ProjectKind.detect(at: try folder(["package.json"])), .node)
        XCTAssertEqual(ProjectKind.detect(at: try folder(["pyproject.toml"])), .python)
        XCTAssertEqual(ProjectKind.detect(at: try folder(["App.xcodeproj"])), .xcode)
        XCTAssertEqual(ProjectKind.detect(at: try folder(["notes.txt"])), .folder)
        XCTAssertEqual(ProjectKind.detect(at: root.appendingPathComponent("missing")), .folder)
    }

    func testGitHealthAndChangeSummary() {
        XCTAssertEqual(GitStatus(branch: "main", changedFiles: 0, isWorktree: false).health, .clean)
        XCTAssertEqual(GitStatus(branch: "main", changedFiles: 3, isWorktree: true).health, .changed)
        XCTAssertEqual(GitStatus(branch: "", changedFiles: 0, isWorktree: false, error: "Git 状态不可用").health, .unavailable)
        let status = GitStatus(branch: "feature/x", changedFiles: 2, isWorktree: true)
        XCTAssertEqual(status.summary, "feature/x · " + status.changeSummary)
        XCTAssertTrue(status.changeSummary.hasSuffix(" · worktree"))
    }
}
