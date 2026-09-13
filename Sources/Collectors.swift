import Foundation

enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var claudeProjects: URL { home.appendingPathComponent(".claude/projects") }
    static var codexSessions: URL { home.appendingPathComponent(".codex/sessions") }
}

/// Janela mantida em cache. Uma folga sobre os 7 dias do limite semanal.
let retentionWindow: TimeInterval = 9 * 86_400

enum FileScan {
    /// Lista arquivos .jsonl sob um diretório, modificados depois de `cutoff`.
    static func recentJSONL(under root: URL, modifiedAfter cutoff: Date) -> [(path: String, mtime: Date)] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [(String, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate,
                  mtime > cutoff else { continue }
            found.append((url.path, mtime))
        }
        return found.sorted { $0.1 > $1.1 }
    }
}

/// Helpers de JSON — os logs são grandes, então filtramos por substring antes de desserializar.
enum JSON {
    static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func int(_ dict: [String: Any]?, _ key: String) -> Int {
        (dict?[key] as? NSNumber)?.intValue ?? 0
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoPlain = ISO8601DateFormatter()

    static func date(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        return iso.date(from: text) ?? isoPlain.date(from: text)
    }
}

// MARK: - Claude Code

enum ClaudeCollector {
    /// Lê os transcripts do Claude Code e devolve um snapshot com uso e limites estimados.
    static func collect(cache: TokenCache) -> ProviderSnapshot {
        var snapshot = ProviderSnapshot(name: "Claude Code")
        let cutoff = Date().addingTimeInterval(-retentionWindow)
        let files = FileScan.recentJSONL(under: Paths.claudeProjects, modifiedAfter: cutoff)

        guard FileManager.default.fileExists(atPath: Paths.claudeProjects.path) else {
            snapshot.note = "~/.claude/projects não encontrado"
            return snapshot
        }
        snapshot.available = true

        for (path, _) in files {
            var state = cache.files[path] ?? FileState()
            state.offset = LineReader.readNewLines(path: path, from: state.offset) { line in
                // Um 429 de limite de sessão é a única medida exata do teto que existe localmente.
                if line.contains("\"rateLimitType\"") {
                    if let root = JSON.object(line),
                       let quota = root["quotaLimits"] as? [String: Any],
                       quota["rateLimitType"] as? String == "five_hour",
                       quota["status"] as? String == "rejected",
                       let timestamp = JSON.date(root["timestamp"]) {
                        state.limitHits.append(timestamp.timeIntervalSince1970)
                    }
                    return
                }
                // Só linhas de resposta do modelo carregam contagem de tokens.
                guard line.contains("\"usage\""), line.contains("\"assistant\"") else { return }
                guard let root = JSON.object(line),
                      root["type"] as? String == "assistant",
                      let message = root["message"] as? [String: Any],
                      let usageDict = message["usage"] as? [String: Any],
                      let timestamp = JSON.date(root["timestamp"]) else { return }

                // Cada resposta aparece uma vez por requestId; sidechains de subagente contam também.
                let identity = "\(root["requestId"] as? String ?? "")|\(message["id"] as? String ?? "")"
                if identity != "|" {
                    if state.seen.contains(identity) { return }
                    state.seen.insert(identity)
                }

                var model = message["model"] as? String ?? "desconhecido"
                if usageDict["speed"] as? String == "fast" { model += "|fast" }

                let creation = usageDict["cache_creation"] as? [String: Any]
                var usage = RawUsage()
                usage.input = JSON.int(usageDict, "input_tokens")
                usage.output = JSON.int(usageDict, "output_tokens")
                usage.cacheRead = JSON.int(usageDict, "cache_read_input_tokens")
                usage.cacheWrite5m = JSON.int(creation, "ephemeral_5m_input_tokens")
                usage.cacheWrite1h = JSON.int(creation, "ephemeral_1h_input_tokens")
                if creation == nil {
                    usage.cacheWrite5m = JSON.int(usageDict, "cache_creation_input_tokens")
                }
                guard usage.total > 0 else { return }
                state.add(at: timestamp, model: model, usage: usage)
            }
            state.size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0) ?? 0
            cache.files[path] = state
        }

        let timeline = cache.timeline(since: cutoff, pathPrefix: Paths.claudeProjects.path)
        snapshot.today = aggregate(timeline, since: Calendar.current.startOfDay(for: Date()))
        let weekly = weeklyLimit(timeline: timeline)
        // "Semana" aqui é o ciclo de cobrança real, não 7 dias para trás.
        snapshot.week = weekly.used

        let blocks = fiveHourBlocks(from: timeline)
        let hits = cache.limitHits(since: cutoff, pathPrefix: Paths.claudeProjects.path)
        if let current = blocks.last, current.isActive {
            snapshot.currentBlock = current.aggregate
            snapshot.sessionLimit = estimateSessionLimit(current: current, history: blocks, hits: hits)
        } else {
            snapshot.sessionLimit = LimitGauge(usedPercent: 0, resetsAt: nil, exact: false, label: "sem bloco ativo")
        }
        snapshot.weeklyLimit = weekly.gauge
        snapshot.activeSession = activeSession(files: files)
        return snapshot
    }

    private static func aggregate(_ timeline: [(date: Date, model: String, usage: RawUsage)], since: Date) -> Aggregate {
        var out = Aggregate()
        for row in timeline where row.date >= since { out.add(model: row.model, row.usage) }
        return out
    }

    /// Reconstrói as janelas de 5h. A janela abre no **instante exato** da primeira atividade
    /// e fecha 5h depois — confirmado contra o painel de Uso do app (primeira mensagem 19:40,
    /// reset anunciado 00:40). Não arredondar é essencial: `Calendar.date(bySetting:)`
    /// arredondaria para a hora seguinte e jogaria fora o início da janela.
    private static func fiveHourBlocks(from timeline: [(date: Date, model: String, usage: RawUsage)]) -> [Block] {
        var blocks: [Block] = []
        for row in timeline {
            if var last = blocks.last, row.date < last.end {
                last.aggregate.add(model: row.model, row.usage)
                blocks[blocks.count - 1] = last
                continue
            }
            var aggregate = Aggregate()
            aggregate.add(model: row.model, row.usage)
            blocks.append(Block(start: row.date,
                                end: row.date.addingTimeInterval(5 * 3_600),
                                aggregate: aggregate))
        }
        return blocks
    }

    /// O Claude Code não grava o percentual do limite antes de você bater nele. Duas fontes de teto,
    /// em ordem de confiança: um teto fixado no config, um bloco que realmente levou 429, ou o
    /// maior bloco já observado.
    private static func estimateSessionLimit(current: Block, history: [Block], hits: [Date]) -> LimitGauge {
        let past = history.dropLast()
        var ceiling = Config.shared.claudeSessionCostCeiling ?? 0
        var label = ceiling > 0 ? "teto do config" : ""

        if ceiling == 0 {
            // Blocos que foram recusados por limite revelam o teto real.
            let rejected = past.filter { block in
                hits.contains { $0 >= block.start && $0 < block.end }
            }.map(\.aggregate.cost)
            if let proven = rejected.min(), proven > 0 {
                ceiling = proven
                label = "calibrado por limite atingido"
            }
        }
        if ceiling == 0, let peak = past.map(\.aggregate.cost).max(), peak > 0 {
            ceiling = peak
            label = "estimado pelo pico"
        }
        guard ceiling > 0 else {
            return LimitGauge(usedPercent: 0, resetsAt: current.end, exact: false, label: "sem histórico p/ calibrar")
        }
        return LimitGauge(usedPercent: min(current.aggregate.cost / ceiling * 100, 999),
                          resetsAt: current.end, exact: false, label: label)
    }

    /// O limite semanal reseta em dia e hora fixos da semana (no app: quinta, 12:00), não numa
    /// janela rolante de 7 dias. Somar 7 dias para trás inflava o consumo em ~2,7x.
    static func weeklyWindowStart(now: Date = Date()) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let weekday = Config.shared.claudeWeeklyResetWeekday
        let hour = Config.shared.claudeWeeklyResetHour

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        components.second = 0
        // Última ocorrência do marco semanal antes de agora.
        guard let previous = calendar.nextDate(after: now,
                                               matching: components,
                                               matchingPolicy: .nextTime,
                                               direction: .backward) else {
            return now.addingTimeInterval(-7 * 86_400)
        }
        return previous
    }

    private static func weeklyLimit(timeline: [(date: Date, model: String, usage: RawUsage)]) -> (gauge: LimitGauge?, used: Aggregate) {
        let start = weeklyWindowStart()
        var used = Aggregate()
        for row in timeline where row.date >= start { used.add(model: row.model, row.usage) }

        let reset = start.addingTimeInterval(7 * 86_400)
        guard let ceiling = Config.shared.claudeWeeklyCostCeiling, ceiling > 0 else {
            return (nil, used)
        }
        return (LimitGauge(usedPercent: min(used.cost / ceiling * 100, 999),
                           resetsAt: reset, exact: false, label: "teto do config"), used)
    }

    /// Sessão viva = transcript tocado nos últimos 3 minutos.
    private static func activeSession(files: [(path: String, mtime: Date)]) -> ActiveSession? {
        guard let recent = files.first, recent.mtime > Date().addingTimeInterval(-180) else { return nil }
        guard let handle = FileHandle(forReadingAtPath: recent.path) else { return nil }
        defer { try? handle.close() }

        let size = (try? FileManager.default.attributesOfItem(atPath: recent.path)[.size] as? Int ?? 0) ?? 0
        let tailSize = min(size, 2 << 20)
        try? handle.seek(toOffset: UInt64(max(0, size - tailSize)))
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"usage\""),
                  let root = JSON.object(String(line)),
                  root["type"] as? String == "assistant",
                  let message = root["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else { continue }

            let model = message["model"] as? String ?? "desconhecido"
            let used = JSON.int(usageDict, "input_tokens")
                + JSON.int(usageDict, "cache_read_input_tokens")
                + JSON.int(usageDict, "cache_creation_input_tokens")
            let project = (root["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? URL(fileURLWithPath: recent.path).deletingLastPathComponent().lastPathComponent
            return ActiveSession(project: project, model: model, contextUsed: used,
                                 contextWindow: Pricing.contextWindow(for: model))
        }
        return nil
    }
}

// MARK: - Codex

enum CodexCollector {
    /// O Codex grava os limites reais vindos do servidor, então aqui não há estimativa.
    static func collect(cache: TokenCache) -> ProviderSnapshot {
        var snapshot = ProviderSnapshot(name: "Codex")
        let cutoff = Date().addingTimeInterval(-retentionWindow)

        guard FileManager.default.fileExists(atPath: Paths.codexSessions.path) else {
            snapshot.note = "~/.codex/sessions não encontrado"
            return snapshot
        }
        snapshot.available = true
        let files = FileScan.recentJSONL(under: Paths.codexSessions, modifiedAfter: cutoff)

        for (path, _) in files {
            var state = cache.files[path] ?? FileState()
            var currentModel = "gpt-5"
            state.offset = LineReader.readNewLines(path: path, from: state.offset) { line in
                if line.contains("\"turn_context\"") {
                    if let root = JSON.object(line),
                       root["type"] as? String == "turn_context",
                       let payload = root["payload"] as? [String: Any],
                       let model = payload["model"] as? String {
                        currentModel = model
                    }
                    return
                }
                guard line.contains("\"token_usage_record\""),
                      let root = JSON.object(line),
                      root["type"] as? String == "token_usage_record",
                      let payload = root["payload"] as? [String: Any],
                      let usageDict = payload["usage"] as? [String: Any],
                      let timestamp = JSON.date(root["timestamp"]) else { return }

                // Uma resposta pode ser registrada mais de uma vez; o response_id desempata.
                if let responseID = payload["response_id"] as? String {
                    if state.seen.contains(responseID) { return }
                    state.seen.insert(responseID)
                }

                var usage = RawUsage()
                let cached = JSON.int(usageDict, "cached_input_tokens")
                // `input_tokens` já inclui os cacheados; separamos para precificar certo.
                usage.input = max(0, JSON.int(usageDict, "input_tokens") - cached)
                usage.cacheRead = cached
                usage.cacheWrite5m = JSON.int(usageDict, "cache_write_input_tokens")
                usage.output = JSON.int(usageDict, "output_tokens")
                guard usage.total > 0 else { return }
                state.add(at: timestamp, model: currentModel, usage: usage)
            }
            cache.files[path] = state
        }

        let timeline = cache.timeline(since: cutoff, pathPrefix: Paths.codexSessions.path)
        var today = Aggregate(), week = Aggregate()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        for row in timeline {
            if row.date >= startOfDay { today.add(model: row.model, row.usage) }
            if row.date >= weekAgo { week.add(model: row.model, row.usage) }
        }
        snapshot.today = today
        snapshot.week = week

        if let latest = files.first { applyLiveState(from: latest, to: &snapshot) }
        return snapshot
    }

    /// Lê o fim do rollout mais recente: ali estão os percentuais de limite e o uso da sessão.
    private static func applyLiveState(from file: (path: String, mtime: Date), to snapshot: inout ProviderSnapshot) {
        guard let handle = FileHandle(forReadingAtPath: file.path) else { return }
        defer { try? handle.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0) ?? 0
        try? handle.seek(toOffset: UInt64(max(0, size - (4 << 20))))
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return }

        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"token_count\""),
                  let root = JSON.object(String(line)),
                  let payload = root["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else { continue }

            if let limits = payload["rate_limits"] as? [String: Any] {
                snapshot.plan = limits["plan_type"] as? String
                snapshot.sessionLimit = gauge(from: limits["primary"], fallbackLabel: "janela de 5h")
                snapshot.weeklyLimit = gauge(from: limits["secondary"], fallbackLabel: "janela semanal")
            }
            if let info = payload["info"] as? [String: Any] {
                if let totals = info["total_token_usage"] as? [String: Any] {
                    var usage = RawUsage()
                    let cached = JSON.int(totals, "cached_input_tokens")
                    usage.input = max(0, JSON.int(totals, "input_tokens") - cached)
                    usage.cacheRead = cached
                    usage.output = JSON.int(totals, "output_tokens")
                    snapshot.currentBlock.add(model: "gpt", usage)
                }
                if let last = info["last_token_usage"] as? [String: Any] {
                    let window = JSON.int(info, "model_context_window")
                    let project = URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
                    if file.mtime > Date().addingTimeInterval(-180) {
                        snapshot.activeSession = ActiveSession(
                            project: String(project.prefix(28)),
                            model: snapshot.plan.map { "Codex (\($0))" } ?? "Codex",
                            contextUsed: JSON.int(last, "input_tokens"),
                            contextWindow: window > 0 ? window : 272_000
                        )
                    }
                }
            }
            return
        }
    }

    private static func gauge(from raw: Any?, fallbackLabel: String) -> LimitGauge? {
        guard let dict = raw as? [String: Any],
              let percent = (dict["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let minutes = JSON.int(dict, "window_minutes")
        let resets = (dict["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let label = minutes > 0 ? windowLabel(minutes: minutes) : fallbackLabel

        // O Codex só grava o percentual quando faz uma requisição. Se a janela já virou
        // desde o último registro, aquele número é de um período que não existe mais —
        // e como nenhuma requisição nova apareceu, o consumo da janela atual é zero.
        if let resets, resets <= Date() {
            return LimitGauge(usedPercent: 0, resetsAt: nil, exact: false, label: "janela renovada")
        }

        return LimitGauge(usedPercent: percent, resetsAt: resets, exact: true, label: label)
    }

    private static func windowLabel(minutes: Int) -> String {
        if minutes % 1440 == 0 { return "janela de \(minutes / 1440)d" }
        if minutes % 60 == 0 { return "janela de \(minutes / 60)h" }
        return "janela de \(minutes)min"
    }
}
