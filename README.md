# TokenBar

Indicador de consumo do **Claude Code** e do **Codex** na barra de menus do macOS.
Passe o mouse no ícone e um painel desce com limites, tokens, custo e a sessão ativa.

App nativo (AppKit + SwiftUI), compilado **sem Xcode** — só com os Command Line Tools.
Apple Silicon, macOS 14+.

```
CC 9%  CX 4%     ← barra de menus, percentual da janela de 5h de cada ferramenta
```

## Instalar

```bash
./install.sh
```

Copia o app para `~/Applications` e registra um LaunchAgent para subir no login.
Para remover tudo (app, início automático, cache e config): `./uninstall.sh`.

Para só compilar e testar sem instalar: `./build.sh && open TokenBar.app`.
`./TokenBar.app/Contents/MacOS/TokenBar --preview` abre o painel numa posição fixa,
útil para conferir o visual sem depender do mouse.

## De onde vêm os dados

Tudo é lido do disco. O app não faz nenhuma chamada de rede e não lê credenciais.

| | Codex | Claude Code |
|---|---|---|
| Origem | `~/.codex/sessions/**/*.jsonl` | `~/.claude/projects/**/*.jsonl` |
| Limite de 5h | **exato** (vem do servidor) | **estimado** |
| Limite semanal | **exato** (vem do servidor) | só com teto configurado |
| Tokens e custo | calculado dos logs | calculado dos logs |

O Codex grava nos rollouts um evento `token_count` com `rate_limits`, incluindo
`used_percent` e `resets_at` das janelas primária (5h) e secundária (semanal). É o número
real, o mesmo que o `/status` mostra.

O Claude Code **não** grava o percentual do limite — ele só aparece no log depois que a API
recusa uma requisição com 429. Por isso o percentual do Claude é derivado: o consumo é
convertido em custo e comparado com um teto. O teto vem, nesta ordem:

1. `claudeSessionCostCeiling` do config, se você definir;
2. o custo de um bloco de 5h que **realmente levou 429** (calibração exata, quando acontecer);
3. o seu maior bloco de 5h já observado.

Os valores estimados aparecem marcados com ✨ no painel. Se você souber seu teto real,
defina-o no config e o número vira confiável.

### Como as janelas funcionam

Conferido contra o painel **Configurações > Uso** do app do Claude:

- **Sessão (5h):** abre no *instante exato* da primeira atividade e fecha 5h depois. Não é
  arredondada para a hora cheia — o app confirmou: primeira mensagem 19:40, reset 00:40.
  O TokenBar agrupa em baldes de 5 min, então o horário de reset pode sair até 5 min adiante.
- **Semanal:** reseta em dia e hora fixos (na conta Equipe: quinta, 12:00), **não** é uma
  janela rolante de 7 dias. Ajuste em `claudeWeeklyResetWeekday` / `claudeWeeklyResetHour`.

Calibração feita em 12/09/2026 contra duas leituras do app (17% e 20% na sessão, 13% no
semanal): teto de sessão ~$45 e teto semanal ~$555. Atenção: esse teto semanal inclui o
bônus temporário de +50% que vale até 13/09 — depois disso, baixe para ~$370.

## Configuração

Opcional, em `~/.tokenbar/config.json`. Veja `config.example.json`:

```bash
cp config.example.json ~/.tokenbar/config.json
```

| Chave | Para quê |
|---|---|
| `refreshSeconds` | intervalo de atualização (padrão 20s) |
| `hoverDelaySeconds` | atraso até o painel abrir no hover (padrão 0,25s) |
| `claudeSessionCostCeiling` | teto em USD da janela de 5h do Claude |
| `claudeWeeklyCostCeiling` | teto em USD do ciclo semanal do Claude |
| `claudeWeeklyResetWeekday` | dia do reset semanal (1=domingo … 5=quinta) |
| `claudeWeeklyResetHour` | hora do reset semanal |
| `openaiPrices` | preços por MTok dos modelos OpenAI |

Os preços da Anthropic estão fixos no binário (`Sources/Pricing.swift`), com os
multiplicadores padrão de cache: leitura 0,1x e escrita 1,25x (5min) / 2x (1h).
Modelos OpenAI fora da tabela são precificados pelo tier principal, para o custo total
não sumir silenciosamente.

## Desempenho

Os logs somam mais de 1 GB, então nada é reprocessado duas vezes. Cada arquivo é lido de
forma incremental a partir do último byte já visto, e o resultado fica em baldes de 5
minutos no cache (`~/.tokenbar/cache.json`, alguns KB).

- primeira execução: ~45s (varre a janela de 9 dias)
- atualizações seguintes: **~0,2s**

## Compartilhar com outras pessoas

```bash
./dist.sh
```

Gera em `dist/`:

- `TokenBar-1.0-AppleSilicon.zip` — o app pronto (empacotado com `ditto`, que preserva
  o bundle; `zip` comum corrompe um `.app`)
- `TokenBar-1.0-fonte.tar.gz` — o código, para quem preferir compilar
- `LEIA-ME.txt` — instruções para quem receber

**Gatekeeper:** o app é assinado ad-hoc, sem conta paga de desenvolvedor da Apple, então
em outra máquina o macOS bloqueia na primeira abertura. Quem receber precisa rodar uma vez:

```bash
xattr -dr com.apple.quarantine /Applications/TokenBar.app
```

Ou compilar do fonte (`./install.sh`), que não passa pelo Gatekeeper. Para distribuir sem
nenhum atrito seria necessário Developer ID + notarização (conta Apple Developer, US$ 99/ano).

Requisitos de quem recebe: macOS 14+, Apple Silicon, e usar Claude Code e/ou Codex
localmente — o app lê os logs da própria máquina.

## Estrutura

```
Sources/
  main.swift        NSStatusItem, hover, ciclo de vida
  HUD.swift         painel flutuante (borderless, blur, animação de descida)
  Views.swift       abas: visão geral, Claude, Codex
  Ring.swift        anéis de progresso do topo
  Collectors.swift  leitura dos logs do Claude e do Codex
  Cache.swift       leitura incremental + cache em baldes
  Pricing.swift     tabela de preços e janelas de contexto
  Config.swift      ~/.tokenbar/config.json
  Models.swift      tipos do snapshot
  Format.swift      formatação de tokens, dinheiro e tempo
```
