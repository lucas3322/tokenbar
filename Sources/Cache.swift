import Foundation

/// Estado persistido de um arquivo de log já lido, para não reprocessar 500 MB a cada refresh.
struct FileState: Codable {
    var offset: Int = 0
    var size: Int = 0
    /// Baldes de 5 minutos: índice do balde -> modelo -> tokens.
    var buckets: [Int: [String: RawUsage]] = [:]
    /// Identificadores já contabilizados, para não somar a mesma resposta duas vezes.
    var seen: Set<String> = []
    /// Momentos em que a API recusou por limite de sessão (429). Calibração exata do teto.
    var limitHits: [Double] = []

    mutating func add(at timestamp: Date, model: String, usage: RawUsage) {
        let bucket = Int(timestamp.timeIntervalSince1970) / TokenCache.bucketSeconds
        buckets[bucket, default: [:]][model, default: RawUsage()] += usage
    }

    /// Descarta baldes e IDs fora da janela de interesse para o arquivo não crescer sem limite.
    mutating func prune(before cutoff: Date) {
        let limit = Int(cutoff.timeIntervalSince1970) / TokenCache.bucketSeconds
        buckets = buckets.filter { $0.key >= limit }
        limitHits = limitHits.filter { $0 >= cutoff.timeIntervalSince1970 }
        if seen.count > 20_000 { seen = [] }
    }
}

final class TokenCache: Codable {
    static let bucketSeconds = 300
    static let version = 3

    var version: Int = TokenCache.version
    var files: [String: FileState] = [:]

    enum CodingKeys: String, CodingKey { case version, files }

    init() {}

    static var url: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokenbar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }

    static func load() -> TokenCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(TokenCache.self, from: data),
              cache.version == TokenCache.version else { return TokenCache() }
        return cache
    }

    func save(pruningBefore cutoff: Date) {
        for key in files.keys { files[key]?.prune(before: cutoff) }
        files = files.filter { !$0.value.buckets.isEmpty || $0.value.offset > 0 }
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: TokenCache.url, options: .atomic)
    }

    /// Instantes de 429 por limite de sessão, em ordem.
    func limitHits(since cutoff: Date, pathPrefix: String) -> [Date] {
        files.filter { $0.key.hasPrefix(pathPrefix) }
            .flatMap { $0.value.limitHits }
            .filter { $0 >= cutoff.timeIntervalSince1970 }
            .sorted()
            .map { Date(timeIntervalSince1970: $0) }
    }

    /// Junta os baldes de todos os arquivos numa linha do tempo ordenada.
    func timeline(since cutoff: Date, pathPrefix: String) -> [(date: Date, model: String, usage: RawUsage)] {
        let limit = Int(cutoff.timeIntervalSince1970) / TokenCache.bucketSeconds
        var rows: [(Date, String, RawUsage)] = []
        for (path, state) in files where path.hasPrefix(pathPrefix) {
            for (bucket, models) in state.buckets where bucket >= limit {
                let date = Date(timeIntervalSince1970: Double(bucket * TokenCache.bucketSeconds))
                for (model, usage) in models { rows.append((date, model, usage)) }
            }
        }
        return rows.sorted { $0.0 < $1.0 }.map { (date: $0.0, model: $0.1, usage: $0.2) }
    }
}

/// Leitura incremental de arquivos JSONL grandes: só lê os bytes novos desde a última passagem.
enum LineReader {
    /// Entrega cada linha completa nova e devolve o offset do fim da última linha completa.
    static func readNewLines(path: String, from offset: Int, handler: (String) -> Void) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let total = attrs[.size] as? Int else { return offset }

        // Arquivo truncado ou rotacionado: recomeça do zero.
        var start = offset
        if start > total { start = 0 }
        guard total > start, let handle = FileHandle(forReadingAtPath: path) else { return max(start, total) }
        defer { try? handle.close() }

        try? handle.seek(toOffset: UInt64(start))
        var position = start
        var leftover = Data()

        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            var data = leftover
            data.append(chunk)
            var lineStart = data.startIndex
            while let newline = data[lineStart...].firstIndex(of: 0x0A) {
                if newline > lineStart, let line = String(data: data[lineStart..<newline], encoding: .utf8) {
                    handler(line)
                }
                position += data.distance(from: lineStart, to: newline) + 1
                lineStart = data.index(after: newline)
            }
            leftover = Data(data[lineStart...])
            // Linha parcial gigante: evita segurar memória indefinidamente.
            if leftover.count > 64 << 20 { leftover.removeAll(); position = total }
        }
        return position
    }
}
