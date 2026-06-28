import Foundation

func makeTestDatabasePath() -> String {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir.appendingPathComponent("test.sqlite").path
}

func cleanupTestDatabase(path: String) {
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: directory)
}
