import AppKit
import CryptoKit
import Foundation

/// Busca, verifica e instala novas versões a partir das Releases do GitHub.
///
/// É a única parte do app que acessa a rede. Consulta apenas a API pública de
/// releases do repositório configurado, sem enviar credencial ou identificação, e
/// pode ser desligada nos Ajustes.
///
/// ATENÇÃO: depende do repositório ser público. Tornando-o privado, a API passa a
/// exigir autenticação e a verificação para de funcionar — o app avisa em vez de
/// falhar em silêncio.
@MainActor
final class Updater: ObservableObject {
    enum Estado: Equatable {
        case parado
        case verificando
        case atualizado(String)
        case disponivel(versao: String, url: URL, tamanho: Int)
        case baixando(Double)
        case instalando
        case erro(String)
    }

    @Published private(set) var estado: Estado = .parado
    @Published var verificarAutomaticamente: Bool = Config.shared.autoCheckUpdates {
        didSet { Config.escrever(chave: "autoCheckUpdates", valor: verificarAutomaticamente) }
    }

    private var timer: Timer?

    var versaoAtual: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func iniciar() {
        guard verificarAutomaticamente else { return }
        // Um respiro após a abertura: a primeira varredura de logs já ocupa a máquina.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            Task { await self?.verificar(silencioso: true) }
        }
        let intervalo = max(1.0, Config.shared.updateCheckHours) * 3_600
        timer = Timer.scheduledTimer(withTimeInterval: intervalo, repeats: true) { [weak self] _ in
            Task { await self?.verificar(silencioso: true) }
        }
    }

    // MARK: Verificação

    func verificar(silencioso: Bool = false) async {
        if case .baixando = estado { return }
        if case .instalando = estado { return }
        if !silencioso { estado = .verificando }

        let repo = Config.shared.updateRepo
        guard !repo.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            estado = .erro("repositório de atualização não configurado")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TokenBar/\(versaoAtual)", forHTTPHeaderField: "User-Agent")

        do {
            let (dados, resposta) = try await URLSession.shared.data(for: request)
            if let http = resposta as? HTTPURLResponse, http.statusCode != 200 {
                estado = .erro(http.statusCode == 404
                    ? "repositório privado ou sem releases"
                    : "GitHub respondeu \(http.statusCode)")
                return
            }
            guard let raiz = try JSONSerialization.jsonObject(with: dados) as? [String: Any],
                  let tag = raiz["tag_name"] as? String,
                  let ativos = raiz["assets"] as? [[String: Any]] else {
                estado = .erro("resposta inesperada do GitHub")
                return
            }

            let publicada = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Updater.maiorQue(publicada, versaoAtual) else {
                estado = .atualizado(versaoAtual)
                return
            }
            guard let zip = ativos.first(where: { ($0["name"] as? String)?.hasSuffix("-AppleSilicon.zip") == true }),
                  let endereco = zip["browser_download_url"] as? String,
                  let destino = URL(string: endereco) else {
                estado = .erro("a release \(tag) não traz o instalador")
                return
            }
            estado = .disponivel(versao: publicada,
                                 url: destino,
                                 tamanho: (zip["size"] as? NSNumber)?.intValue ?? 0)
        } catch {
            estado = silencioso ? .parado : .erro("sem conexão com o GitHub")
        }
    }

    /// Compara versões no formato X.Y.Z sem depender de comparação textual,
    /// em que "1.10.0" seria menor que "1.9.0".
    nonisolated static func maiorQue(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Instalação

    func baixarEInstalar() async {
        guard case let .disponivel(versao, url, _) = estado else { return }
        estado = .baixando(0)

        do {
            let (arquivo, resposta) = try await URLSession.shared.download(from: url)
            if let http = resposta as? HTTPURLResponse, http.statusCode != 200 {
                estado = .erro("download falhou (\(http.statusCode))")
                return
            }

            let temporario = FileManager.default.temporaryDirectory
                .appendingPathComponent("tokenbar-update-\(versao)", isDirectory: true)
            try? FileManager.default.removeItem(at: temporario)
            try FileManager.default.createDirectory(at: temporario, withIntermediateDirectories: true)

            let zip = temporario.appendingPathComponent("TokenBar.zip")
            try FileManager.default.moveItem(at: arquivo, to: zip)

            estado = .instalando

            // ditto preserva o bundle; unzip comum corrompe links e metadados.
            let extraido = temporario.appendingPathComponent("extraido", isDirectory: true)
            try executar("/usr/bin/ditto", ["-x", "-k", zip.path, extraido.path])

            let novo = extraido.appendingPathComponent("TokenBar.app")
            guard FileManager.default.fileExists(atPath: novo.path) else {
                estado = .erro("o pacote baixado não contém TokenBar.app")
                return
            }
            // Recusa instalar algo que não abre: melhor continuar na versão velha.
            guard let plist = NSDictionary(contentsOf: novo.appendingPathComponent("Contents/Info.plist")),
                  let baixada = plist["CFBundleShortVersionString"] as? String,
                  baixada == versao else {
                estado = .erro("o pacote baixado não é a versão \(versao)")
                return
            }

            trocarESairAsync(novo: novo, atual: Bundle.main.bundleURL)
        } catch {
            estado = .erro("falha ao instalar: \(error.localizedDescription)")
        }
    }

    /// O app não consegue se sobrescrever enquanto roda: um script espera a saída,
    /// troca os arquivos e abre a versão nova.
    private func trocarESairAsync(novo: URL, atual: URL) {
        let script = """
        for _ in $(seq 1 50); do
          /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null || break
          /bin/sleep 0.2
        done
        /bin/rm -rf '\(atual.path)'
        /usr/bin/ditto '\(novo.path)' '\(atual.path)'
        /usr/bin/xattr -dr com.apple.quarantine '\(atual.path)' 2>/dev/null
        /usr/bin/open '\(atual.path)'
        """
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/bin/sh")
        processo.arguments = ["-c", script]
        try? processo.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private func executar(_ caminho: String, _ argumentos: [String]) throws -> Int32 {
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: caminho)
        processo.arguments = argumentos
        try processo.run()
        processo.waitUntilExit()
        return processo.terminationStatus
    }
}
