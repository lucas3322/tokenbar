# TokenBar

Acompanhe quanto você já consumiu do **Claude Code** e do **Codex** direto na barra de menus
do macOS. Passe o mouse no ícone e um painel desce com os limites, o consumo do dia, o custo
estimado e a sessão que está rodando.

```
CC 24%  CX 4%      ← barra de menus: quanto já foi usado da janela de 5h de cada ferramenta
```

App nativo (AppKit + SwiftUI). Não lê credenciais e não envia dado algum — tudo vem dos logs
que as duas ferramentas já gravam na sua máquina. A única conexão de rede é a verificação de
versão nova, desligável nos Ajustes.

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

| | Codex | Claude Code |
|---|---|---|
| Percentual do limite | **exato**, vindo do servidor | estimado ✨, com teto que se corrige |
| Janela e horário de reset | exato | exato |
| Tokens e custo | exato | exato |

O Codex grava nos próprios registros o percentual real das janelas de 5h e semanal — o app
só lê. O Claude Code não grava: esse número só aparece depois que a API recusa uma requisição
por limite.

Para o Claude, o app converte o consumo em custo e compara com um teto. O que mudou na 1.5.1
é que **esse teto não é mais um número fixo** — fixá-lo foi o que produziu "114% usado" quando
o valor real era 9%. Agora ele se corrige com duas evidências tiradas dos próprios registros:

- **Passou sem ser recusado.** Se uma janela acumulou mais do que o teto e a API não recusou
  nada, o limite era maior: o teto sobe.
- **Foi recusado.** Um 429 por limite marca o ponto exato, e essa evidência pode baixar o teto.

O teto aprende apenas com **janelas encerradas**. Deixá-lo aprender durante a janela em curso
o faria perseguir o consumo: o anel ficaria colado em ~98% o tempo todo e a escala mudaria a
cada leitura — foi esse o comportamento de "valores bugando" das versões 1.5.0 e 1.5.1.

A janela em curso serve só como piso: se ela já gastou X sem recusa, o limite é no mínimo X.
Quando o consumo alcança o maior valor já visto, o anel para em 100% e diz "no limite do que
já foi visto" em vez de continuar subindo — foi assim que a 1.4 chegou a mostrar 114%.

O percentual da sessão de 5h se sustenta bem; o do ciclo semanal deriva mais, porque a relação
entre custo e limite não se mantém ao longo de dias. Para os dois, o acerto manual resolve.

Se quiser acertar na hora, os **Ajustes** têm o campo *Acertar o Claude*: você informa o
percentual que aparece em Configurações › Uso no app oficial e o teto é fixado por ele. O teto
aprendido fica em `~/.tokenbar/teto.json`; para travá-lo à mão, use `claudeSessionCostCeiling`
e `claudeWeeklyCostCeiling` no config.

### Todas as opções de configuração

| Chave | Para quê | Padrão |
|---|---|---|
| `refreshSeconds` | intervalo de atualização | `20` |
| `hoverDelaySeconds` | atraso até o painel abrir no hover | `0.25` |
| `claudeWeeklyResetWeekday` | dia do reset semanal (1=domingo … 5=quinta) | `5` |
| `claudeWeeklyResetHour` | hora do reset semanal | `12` |
| `claudeSessionCostCeiling` | fixa o teto da janela de 5h, desligando o aprendizado | aprendido |
| `claudeWeeklyCostCeiling` | fixa o teto do ciclo semanal | aprendido |
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

**O app não abre quando clico nele.** Provavelmente já está aberto: ele vive na barra de
menus, sem janela e sem ícone no Dock. Procure a leitura `CC …% CX …%` na barra. A partir da
1.3.2, clicar no app abre o painel em vez de não dar retorno nenhum.

**`build.sh` falha com "plugin for module SwiftUIMacros not found".** A partir da SDK 27 o
SwiftUI declara `@State` como macro, e o plugin que a expande só vem com o Xcode. O
`build.sh` detecta isso e recai na SDK mais nova anterior à 27 — a mensagem aparece no
build. Se não houver nenhuma instalada, é preciso instalar o Xcode.


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

## Avisos de limite

Nos **Ajustes**, o app avisa quando a janela de 5h passa de um limiar — 80% por padrão,
ajustável entre 60% e 95%. Vale para o Codex, que é quem informa o percentual real.

Dispara **uma vez por janela e por ferramenta**: o aviso serve para você decidir o que fazer,
não para repetir a cada atualização até o limite estourar. A janela já avisada fica registrada
em `~/.tokenbar/avisos.json`, então reiniciar o app não faz o aviso voltar.

O aviso é um banner desenhado pelo próprio app, no canto superior direito — clique nele para
abrir o painel. Não usa o Centro de Notificações do macOS: ele recusa aplicativos assinados
ad-hoc com `"Notifications are not allowed for this application"`, e sem conta paga de
desenvolvedor da Apple não há como contornar. O botão **Testar** mostra um exemplo.

| Chave do config | Para quê | Padrão |
|---|---|---|
| `notifyEnabled` | ligar os avisos | `true` |
| `notifyThreshold` | percentual que dispara | `80` |

## Atualização automática

Nos **Ajustes** o app verifica se há versão nova, baixa e se instala sozinho. A verificação
roda a cada 6 horas e pode ser desligada ali mesmo.

A fonte é a API pública de releases do repositório (`updateRepo` no config). **Isso exige que
o repositório permaneça público**: tornando-o privado, a API passa a pedir autenticação e o
app avisa que não conseguiu verificar, em vez de falhar em silêncio.

Antes de trocar o app instalado, o pacote baixado é conferido: precisa conter um
`TokenBar.app` cujo `Info.plist` declare exatamente a versão anunciada. A troca é feita por
um script que espera o processo sair, substitui o bundle e reabre — um app não consegue se
sobrescrever enquanto roda.

| Chave do config | Para quê | Padrão |
|---|---|---|
| `updateRepo` | repositório consultado | `lucas3322/tokenbar` |
| `autoCheckUpdates` | verificar sozinho | `true` |
| `updateCheckHours` | intervalo entre verificações | `6` |

## Versionamento

A versão vive num único lugar: o arquivo `VERSION`. O `build.sh` lê dali e escreve no
`Info.plist`, e o `dist.sh` usa no nome dos pacotes. O número de build é a contagem de
commits, então sempre cresce — que é o que o macOS espera para reconhecer uma atualização.

Para subir a versão, no espírito do `npm version`:

```bash
./version.sh patch     # 1.1.0 -> 1.1.1   correções
./version.sh minor     # 1.1.0 -> 1.2.0   recursos novos
./version.sh major     # 1.1.0 -> 2.0.0   quebra de compatibilidade
./version.sh 2.3.1     # define exatamente
```

Cada chamada grava o `VERSION`, cria o commit e a tag `vX.Y.Z`, e recompila. Use
`--no-git` para só trocar o número. A versão e o build aparecem na aba Ajustes, o que
permite confirmar qual binário está de fato rodando.

**Dependências:** o projeto não tem nenhuma, só frameworks do sistema. Se um dia precisar
de bibliotecas externas, o equivalente ao `package.json` é o `Package.swift` do Swift
Package Manager — enquanto não houver dependência, ele só adicionaria cerimônia.

## Publicação automática (CI)

Dois workflows do GitHub Actions, rodando em `macos-15` (Apple Silicon):

- **build** — a cada push e pull request, compila em máquina limpa e confere o bundle:
  binário arm64, ícone presente e versão do `Info.plist` igual à do arquivo `VERSION`.
- **release** — ao enviar uma tag `vX.Y.Z`, gera os pacotes e publica uma Release do GitHub
  com o app, o fonte e o `SHA256SUMS.txt`, já com as instruções de instalação nas notas.

O fluxo para lançar uma versão:

```bash
./version.sh minor        # grava VERSION, commita e cria a tag
git push origin main --follow-tags
```

O workflow recusa a publicação se a tag não bater com o arquivo `VERSION`, para não sair
uma Release `v1.3.0` contendo um app que se identifica como `1.2.1`.

## Landing page

`landing/` tem a página de download, servida pelo Caddy e publicada no Railway. Ela
hospeda o instalador por conta própria, então funciona com o repositório privado. O
changelog sai de `landing/versions.json`. Detalhes em [landing/README.md](landing/README.md).

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
VERSION             a versão do app, fonte única da verdade
build.sh            compila o TokenBar.app
version.sh          sobe a versão, cria commit e tag
install.sh          compila, instala e habilita no login
uninstall.sh        remove tudo
dist.sh             gera os pacotes para compartilhar
```

Compilado com `swiftc` direto, sem Xcode e sem nenhuma dependência externa.
