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
        // "Semana" aqui é a janela do limite semanal, não 7 dias para trás.
        snapshot.week = weeklyUsage(timeline: timeline)
        snapshot.weekIsCycle = true

        let blocks = fiveHourBlocks(from: timeline)
        if let current = blocks.last, current.isActive {
            snapshot.currentBlock = current.aggregate
            snapshot.sessionWindow = (current.start, current.end)
        }
        snapshot.weeklyWindow = (weeklyWindowStart(), weeklyWindowStart().addingTimeInterval(7 * 86_400))

        // Percentual contra um teto que se corrige sozinho — ver Ceiling.
        var teto = Ceiling.carregar()
        let recusas = cache.limitHits(since: cutoff, pathPrefix: Paths.claudeProjects.path)

        // Primeira execução: parte do maior consumo já observado, que é um piso conhecido
        // do limite real. Sem isso o teto nasceria igual ao consumo atual e o painel
        // abriria em 100% para todo mundo.
        if teto.sessao == 0, let pico = blocks.dropLast().map(\.aggregate.cost).max(), pico > 0 {
            teto.sessao = pico * 1.02
            teto.salvar()
        }
        if teto.semanal == 0 {
            // Semente: o ciclo anterior, já fechado. Usar o ciclo em curso colocaria o
            // teto no consumo de agora e abriria o painel em 100%.
            let anterior = aggregate(timeline,
                                     since: weeklyWindowStart().addingTimeInterval(-7 * 86_400),
                                     until: weeklyWindowStart())
            if anterior.cost > 0 { teto.semanal = anterior.cost * 1.02; teto.salvar() }
        }

        // O teto aprende apenas com janelas ENCERRADAS. Aprender durante a janela em
        // curso faria o teto perseguir o consumo: o anel ficaria grudado em ~98% o
        // tempo todo e a escala mudaria a cada leitura.
        func houveRecusa(_ de: Date, _ ate: Date) -> Bool {
            recusas.contains { $0 >= de && $0 < ate }
        }
        for bloco in blocks {
            // Janelas encerradas ensinam o teto normalmente. A janela em curso só serve
            // como piso: se ela já gastou X sem recusa, o limite é no mínimo X.
            teto.aprender(custo: bloco.aggregate.cost,
                          recusado: !bloco.isActive && houveRecusa(bloco.start, bloco.end),
                          paraSessao: true)
        }
        let inicioCiclo = weeklyWindowStart()
        let cicloAnterior = aggregate(timeline,
                                      since: inicioCiclo.addingTimeInterval(-7 * 86_400),
                                      until: inicioCiclo)
        teto.aprender(custo: cicloAnterior.cost, recusado: false, paraSessao: false)
        teto.aprender(custo: snapshot.week.cost, recusado: false, paraSessao: false)

        if let janela = snapshot.sessionWindow {
            snapshot.sessionLimit = medidor(custo: snapshot.currentBlock.cost,
                                            teto: teto.valor(paraSessao: true),
                                            reset: janela.end,
                                            exato: teto.sessaoExata)
        }
        if let janela = snapshot.weeklyWindow {
            snapshot.weeklyLimit = medidor(custo: snapshot.week.cost,
                                           teto: teto.valor(paraSessao: false),
                                           reset: janela.end,
                                           exato: teto.semanalExata)
        }

        snapshot.activeSession = activeSession(files: files)
        return snapshot
    }

    private static func aggregate(_ timeline: [(date: Date, model: String, usage: RawUsage)],
                                  since: Date, until: Date = .distantFuture) -> Aggregate {
        var out = Aggregate()
        for row in timeline where row.date >= since && row.date < until { out.add(model: row.model, row.usage) }
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

    /// Monta o medidor, ou nada quando ainda não há teto para comparar.
    ///
    /// Quando o consumo alcança o teto conhecido, o percentual para em 100% e o rótulo
    /// diz por quê: o app nunca viu uma janela maior, então não tem escala para além
    /// disso. Continuar subindo daria um número inventado — foi assim que apareceu 114%.
    private static func medidor(custo: Double, teto: Double, reset: Date, exato: Bool) -> LimitGauge? {
        guard teto > 0 else { return nil }
        let percentual = min(custo / teto * 100, 100)
        let rotulo: String
        if custo >= teto { rotulo = "no limite do que já foi visto — acerte nos Ajustes" }
        else if exato { rotulo = "calibrado pelo número oficial" }
        else { rotulo = "teto aprendido" }
        return LimitGauge(usedPercent: percentual, resetsAt: reset, exact: false, label: rotulo)
    }

    private static func weeklyUsage(timeline: [(date: Date, model: String, usage: RawUsage)]) -> Aggregate {
        let start = weeklyWindowStart()
        var used = Aggregate()
        for row in timeline where row.date >= start { used.add(model: row.model, row.usage) }
        return used
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

        // Os limites vêm antes do agregado: é o servidor quem diz quando a janela
        // semanal começou, e sem isso restaria somar 7 dias corridos — que mediria
        // coisa diferente do cartão do Claude, ali do lado.
        applyLiveState(from: files, to: &snapshot)

        let inicioSemana = snapshot.weeklyWindowStart ?? Date().addingTimeInterval(-7 * 86_400)
        snapshot.weekIsCycle = snapshot.weeklyWindowStart != nil

        var today = Aggregate(), week = Aggregate()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        for row in timeline {
            if row.date >= startOfDay { today.add(model: row.model, row.usage) }
            if row.date >= inicioSemana { week.add(model: row.model, row.usage) }
        }
        snapshot.today = today
        snapshot.week = week

        return snapshot
    }

    /// Lê o fim dos rollouts recentes atrás do estado de limites mais novo.
    ///
    /// Dois cuidados que o caminho ingênuo erra:
    ///
    /// 1. A data de modificação do arquivo não diz a idade do conteúdo. O Codex reabre
    ///    sessões antigas, então um arquivo tocado hoje pode ter como último registro algo
    ///    de duas semanas atrás. Por isso os candidatos são comparados pelo timestamp do
    ///    próprio registro, não pela ordem dos arquivos.
    /// 2. Ao atingir o limite, o Codex grava `rate_limits` com os campos nulos. Registros
    ///    assim são ignorados, e a busca continua para trás.
    private static func applyLiveState(from files: [(path: String, mtime: Date)], to snapshot: inout ProviderSnapshot) {
        var melhorLimite: (quando: Date, limits: [String: Any])?
        var melhorUso: (quando: Date, info: [String: Any], arquivo: (path: String, mtime: Date))?

        for arquivo in files.prefix(8) {
            guard let texto = tail(of: arquivo.path, bytes: 4 << 20) else { continue }

            for linha in texto.split(separator: "\n").reversed() {
                guard linha.contains("\"token_count\""),
                      let root = JSON.object(String(linha)),
                      let quando = JSON.date(root["timestamp"]),
                      let payload = root["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count" else { continue }

                if let info = payload["info"] as? [String: Any],
                   melhorUso == nil || quando > melhorUso!.quando {
                    melhorUso = (quando, info, arquivo)
                }

                if let limits = payload["rate_limits"] as? [String: Any],
                   temPercentual(limits["primary"]) || temPercentual(limits["secondary"]),
                   melhorLimite == nil || quando > melhorLimite!.quando {
                    melhorLimite = (quando, limits)
                }

                // Dentro de um arquivo as linhas são cronológicas: o primeiro registro
                // aproveitável vindo do fim já é o mais novo daquele arquivo.
                break
            }
        }

        if let melhorUso { aplicarUso(info: melhorUso.info, arquivo: melhorUso.arquivo, to: &snapshot) }

        guard let melhorLimite else { return }
        let limits = melhorLimite.limits
        snapshot.plan = limits["plan_type"] as? String
        snapshot.sessionLimit = gauge(from: limits["primary"], fallbackLabel: "janela de 5h")
        snapshot.weeklyLimit = gauge(from: limits["secondary"], fallbackLabel: "janela semanal")

        if let secundaria = limits["secondary"] as? [String: Any],
           let reset = (secundaria["resets_at"] as? NSNumber)?.doubleValue,
           case let minutos = JSON.int(secundaria, "window_minutes"), minutos > 0 {
            let inicio = Date(timeIntervalSince1970: reset - Double(minutos) * 60)
            if inicio <= Date() { snapshot.weeklyWindowStart = inicio }
        }
    }

    /// Últimos `bytes` de um arquivo, como texto.
    private static func tail(of path: String, bytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0) ?? 0
        try? handle.seek(toOffset: UInt64(max(0, size - bytes)))
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func aplicarUso(info: [String: Any], arquivo: (path: String, mtime: Date), to snapshot: inout ProviderSnapshot) {
        if let totals = info["total_token_usage"] as? [String: Any] {
            var usage = RawUsage()
            let cached = JSON.int(totals, "cached_input_tokens")
            usage.input = max(0, JSON.int(totals, "input_tokens") - cached)
            usage.cacheRead = cached
            usage.output = JSON.int(totals, "output_tokens")
            snapshot.currentBlock.add(model: "gpt", usage)
        }
        if let last = info["last_token_usage"] as? [String: Any],
           arquivo.mtime > Date().addingTimeInterval(-180) {
            let window = JSON.int(info, "model_context_window")
            let projeto = URL(fileURLWithPath: arquivo.path).deletingPathExtension().lastPathComponent
            snapshot.activeSession = ActiveSession(
                project: String(projeto.prefix(28)),
                model: snapshot.plan.map { "Codex (\($0))" } ?? "Codex",
                contextUsed: JSON.int(last, "input_tokens"),
                contextWindow: window > 0 ? window : 272_000
            )
        }
    }

    /// O servidor informou o percentual neste registro? Independe de a janela ter vencido.
    private static func temPercentual(_ raw: Any?) -> Bool {
        guard let dict = raw as? [String: Any] else { return false }
        return (dict["used_percent"] as? NSNumber) != nil
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
            // A janela virou, mas sem requisição nova o servidor não informou nada sobre
            // a atual. Zero seria um palpite com cara de medida — melhor dizer que não sabe.
            return nil
        }

        return LimitGauge(usedPercent: percent, resetsAt: resets, exact: true, label: label)
    }

    private static func windowLabel(minutes: Int) -> String {
        if minutes % 1440 == 0 { return "janela de \(minutes / 1440)d" }
        if minutes % 60 == 0 { return "janela de \(minutes / 60)h" }
        return "janela de \(minutes)min"
    }
}
