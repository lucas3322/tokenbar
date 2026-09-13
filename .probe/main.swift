import Foundation
func tick(_ label: String, _ body: () -> Void) {
    let t = Date(); body()
    print(String(format: "  %-28s %.2fs", (label as NSString).utf8String!, Date().timeIntervalSince(t)))
}
var cache = TokenCache()
tick("load cache") { cache = TokenCache.load() }
let cutoff = Date().addingTimeInterval(-retentionWindow)
var cfiles: [(path: String, mtime: Date)] = []
var xfiles: [(path: String, mtime: Date)] = []
tick("scan claude dir") { cfiles = FileScan.recentJSONL(under: Paths.claudeProjects, modifiedAfter: cutoff) }
tick("scan codex dir") { xfiles = FileScan.recentJSONL(under: Paths.codexSessions, modifiedAfter: cutoff) }
print("  claude files \(cfiles.count), codex files \(xfiles.count)")
var bytes = 0
tick("read claude increments") {
    for (path, _) in cfiles {
        let before = cache.files[path]?.offset ?? 0
        let after = LineReader.readNewLines(path: path, from: before) { _ in }
        bytes += after - before
    }
}
print("  claude bytes lidos: \(bytes)")
bytes = 0
tick("read codex increments") {
    for (path, _) in xfiles {
        let before = cache.files[path]?.offset ?? 0
        let after = LineReader.readNewLines(path: path, from: before) { _ in }
        bytes += after - before
    }
}
print("  codex bytes lidos: \(bytes)")
tick("full claude collect") { _ = ClaudeCollector.collect(cache: cache) }
tick("full codex collect") { _ = CodexCollector.collect(cache: cache) }
tick("save cache") { cache.save(pruningBefore: cutoff) }
