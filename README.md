# TokenBar

Acompanhe quanto você já consumiu do **Claude Code** e do **Codex** direto na barra de menus
do macOS. Passe o mouse no ícone e um painel desce com os limites, o consumo do dia, o custo
estimado e a sessão que está rodando.

```
CC 24%  CX 4%      ← barra de menus: quanto já foi usado da janela de 5h de cada ferramenta
```

App nativo (AppKit + SwiftUI). Não faz conexão de rede, não lê credenciais e não envia nada
para lugar nenhum — tudo vem dos logs que as duas ferramentas já gravam na sua máquina.

**Requisitos:** macOS 14 ou superior · Mac com Apple Silicon (M1 em diante) · usar Claude Code
e/ou Codex localmente.

---

## Instalação

### Se você recebeu o app pronto (`TokenBar-1.0-AppleSilicon.zip`)

1. Descompacte e arraste `TokenBar.app` para a pasta **Aplicativos**.
2. Na primeira abertura o macOS vai bloquear, dizendo que o app é de um desenvolvedor não
   identificado. Isso acontece porque ele não é assinado por uma conta paga da Apple. Libere
   com um comando, uma única vez:

   ```bash
   xattr -dr com.apple.quarantine /Applications/TokenBar.app
   ```

   Sem terminal: clique com o botão direito no app → **Abrir** → **Abrir**. Se ainda assim
   não abrir, vá em **Ajustes do Sistema → Privacidade e Segurança** e clique em
   *Abrir Mesmo Assim*.

3. Abra o app. O ícone aparece na barra de menus.

### Se você recebeu o código-fonte (`TokenBar-1.0-fonte.tar.gz`)

Esta rota não passa pelo bloqueio do macOS, porque o app é compilado na sua própria máquina.

```bash
xcode-select --install     # só se você ainda não tiver as ferramentas de linha de comando
tar -xzf TokenBar-1.0-fonte.tar.gz
cd tokenbar
./install.sh
```

`install.sh` compila, instala em `~/Applications` e faz o app abrir junto com o login.
Não é preciso ter o Xcode — as ferramentas de linha de comando bastam.

### Desinstalar

```bash
./uninstall.sh
```

Remove o app, o início automático, o cache e a configuração.

---

## Como usar

**Passe o mouse** no ícone da barra de menus e o painel desce sozinho. Clicar também abre e
fecha. Ele some quando você tira o mouse dali.

No topo ficam três anéis com os limites. Abaixo, três abas:

| Aba | O que mostra |
|---|---|
| **Ajustes** | Início no login, calibração, configuração, sair e desinstalar |
| **Visão geral** | Consumo do dia e do ciclo das duas ferramentas lado a lado, quanto veio de cache, qual sessão está ativa e o total somado |
| **Claude** | Limites, sessão ativa com a janela de contexto, tokens abertos por entrada/saída/cache e o consumo por modelo |
| **Codex** | O mesmo, com os percentuais exatos e o plano da conta |

O número na barra é o percentual da janela de 5h: fica **branco** até 60%, **laranja** a
partir de 60% e **vermelho** a partir de 85%.

Um ✨ ao lado de um limite significa que aquele número é estimado (veja abaixo).

---

## Os números são confiáveis?

Depende da ferramenta, e o app deixa isso explícito em vez de fingir precisão.

| | Codex | Claude Code |
|---|---|---|
| Limite de 5h | **exato** — vem do servidor | estimado ✨ |
| Limite semanal | **exato** — vem do servidor | estimado ✨, precisa de calibração |
| Tokens e custo | calculado dos logs | calculado dos logs |

O Codex grava nos próprios logs um evento com o percentual real de uso e o horário do reset.
É o mesmo número que o `/status` dele mostra.

O Claude Code **não** grava isso: o percentual só aparece no log depois que a API recusa uma
requisição por limite. Então o app converte seu consumo em custo e compara com um teto. Para
esse número bater com a realidade, calibre uma vez (leva um minuto) — veja a seção seguinte.

---

## Calibrar o Claude (recomendado)

Faça isso pela própria aba **Ajustes** do painel:

1. Abra o app do Claude em **Configurações → Uso**.
2. No TokenBar, vá em **Ajustes → Calibrar o Claude**, digite o percentual que o app está
   mostrando e clique em **Calibrar**. O teto é calculado e gravado sozinho.

Repita quando os dois números divergirem. **Não é "calibrar uma vez e esquecer"**: o teto muda
quando a Anthropic concede bônus temporários, quando seu plano muda, e a própria conversão de
consumo em percentual tem uma margem — medições ao longo de uma mesma sessão renderam tetos
entre $43 e $53. Recalibrar leva cinco segundos.

Quem preferir editar na mão, o arquivo é `~/.tokenbar/config.json`:

```bash
cp config.example.json ~/.tokenbar/config.json
```

```json
{
  "claudeSessionCostCeiling": 53.62,
  "claudeWeeklyCostCeiling": 533.0,
  "claudeWeeklyResetWeekday": 5,
  "claudeWeeklyResetHour": 12
}
```

O teto depende do seu plano (Pro, Max, Equipe), então cada pessoa precisa calibrar o seu.

### Todas as opções de configuração

| Chave | Para quê | Padrão |
|---|---|---|
| `refreshSeconds` | intervalo de atualização | `20` |
| `hoverDelaySeconds` | atraso até o painel abrir no hover | `0.25` |
| `claudeSessionCostCeiling` | teto em USD da janela de 5h | calibra pelo seu pico |
| `claudeWeeklyCostCeiling` | teto em USD do ciclo semanal | sem percentual |
| `claudeWeeklyResetWeekday` | dia do reset semanal (1=domingo … 5=quinta) | `5` |
| `claudeWeeklyResetHour` | hora do reset semanal | `12` |
| `openaiPrices` | preços por milhão de tokens dos modelos OpenAI | tabela embutida |

O arquivo é lido a cada atualização — não precisa reiniciar o app.

---

## Como as janelas de limite funcionam

Verificado contra o painel de Uso do app do Claude:

- **Sessão (5h):** abre no instante exato da primeira mensagem e fecha 5h depois. Não é
  arredondada para a hora cheia. Como o app agrupa em blocos de 5 minutos, o horário de reset
  pode aparecer até 5 minutos adiante do real.
- **Semanal:** reseta em dia e hora fixos da semana, **não** é uma janela rolante de 7 dias.
  Confira o seu em Configurações → Uso e ajuste no config.

---

## De onde vêm os dados

| | Caminho |
|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` |
| Codex | `~/.codex/sessions/**/*.jsonl` |
| Cache e config do TokenBar | `~/.tokenbar/` |

Esses logs passam de 1 GB, então nada é lido duas vezes: cada arquivo é percorrido de forma
incremental a partir do último byte já visto, e o resultado fica resumido em blocos de 5
minutos no cache. A primeira execução leva cerca de 45 segundos varrendo os últimos 9 dias;
as atualizações seguintes levam **cerca de 0,2 segundo**.

Os preços da Anthropic estão embutidos no app, com os multiplicadores padrão de cache
(leitura 0,1x, escrita 1,25x em 5min e 2x em 1h). Os preços da OpenAI ficam no config porque
mudam com frequência. Modelos fora da tabela são cobrados pelo tier principal, para o custo
total não sumir sem aviso.

---

## Problemas comuns

**O ícone não aparece na barra.** Sua barra pode estar cheia (comum em Mac com notch).
Esconda outros ícones ou use um organizador de barra de menus. Confirme que está rodando com
`pgrep -fl TokenBar`.

**Os percentuais do Claude estão errados.** Falta calibrar — veja a seção acima. Os do Codex
não precisam de calibração.

**Aparece "0%" ou "–" logo depois de instalar.** A primeira varredura leva ~45s. Depois disso
é instantâneo.

**Abri e o macOS disse que o app está danificado.** É o bloqueio de quarentena, não corrupção.
Rode o comando `xattr` da seção de instalação.

**Quero conferir sem mexer no mouse.** `./TokenBar.app/Contents/MacOS/TokenBar --preview`
abre o painel numa posição fixa.

---

## Compartilhar com outras pessoas

```bash
./dist.sh
```

Gera em `dist/` o app compactado, o código-fonte e um `LEIA-ME.txt` com as instruções de
instalação. O `.app` é empacotado com `ditto` — o `zip` comum corrompe um bundle do macOS.

O app é assinado ad-hoc, sem conta paga da Apple, por isso o passo do `xattr` na máquina de
quem recebe. Para distribuir sem nenhum atrito seria preciso Developer ID e notarização
(conta Apple Developer, US$ 99/ano).

---

## Estrutura do projeto

```
Sources/
  main.swift        ícone da barra, hover, ciclo de vida do app
  HUD.swift         painel flutuante (sem borda, translúcido, animação de descida)
  Views.swift       as três abas
  Ring.swift        anéis de progresso do topo
  Collectors.swift  leitura dos logs do Claude e do Codex
  Cache.swift       leitura incremental e cache em blocos
  Pricing.swift     tabela de preços e janelas de contexto
  Config.swift      leitura de ~/.tokenbar/config.json
  Models.swift      tipos do snapshot
  Format.swift      formatação de tokens, dinheiro e tempo
tools/makeicon/     gerador do ícone do app, desenhado por código
build.sh            compila o TokenBar.app
install.sh          compila, instala e habilita no login
uninstall.sh        remove tudo
dist.sh             gera os pacotes para compartilhar
```

Compilado com `swiftc` direto, sem Xcode e sem nenhuma dependência externa.
