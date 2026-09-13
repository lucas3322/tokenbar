#!/bin/bash
# Gera os pacotes para compartilhar o TokenBar.
# Sem conta de desenvolvedor Apple não dá para notarizar, então são duas rotas:
#   1. binário pronto  -> rápido, mas o Gatekeeper exige um passo manual
#   2. código-fonte    -> a pessoa compila na própria máquina, sem Gatekeeper
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0"
OUT="dist"
rm -rf "$OUT" && mkdir -p "$OUT"

./build.sh

# --- Rota 1: app compilado -------------------------------------------------
# ditto preserva symlinks e metadados do bundle; `zip` comum corrompe .app.
ditto -c -k --sequesterRsrc --keepParent TokenBar.app "$OUT/TokenBar-$VERSION-AppleSilicon.zip"

# --- Rota 2: código-fonte --------------------------------------------------
ditto -c -k --sequesterRsrc --keepParent \
  --exclude-list /dev/null \
  Sources "$OUT/.sources.zip" 2>/dev/null || true
rm -f "$OUT/.sources.zip"
tar --exclude='TokenBar.app' --exclude='dist' --exclude='.probe' \
    -czf "$OUT/TokenBar-$VERSION-fonte.tar.gz" \
    Sources tools Resources build.sh install.sh uninstall.sh dist.sh README.md config.example.json

cat > "$OUT/LEIA-ME.txt" <<'TXT'
TokenBar — consumo de tokens do Claude Code e do Codex na barra de menus
=======================================================================

Requisitos: macOS 14 ou superior, Mac com Apple Silicon (M1 em diante).
O app lê apenas os logs locais de quem o executa (~/.claude e ~/.codex).
Não faz nenhuma conexão de rede e não acessa credenciais.

--------------------------------------------------------------------------
OPÇÃO A — usar o app já compilado (mais rápido)
--------------------------------------------------------------------------
1. Descompacte TokenBar-1.0-AppleSilicon.zip
2. Arraste TokenBar.app para a pasta Aplicativos
3. O macOS vai recusar a abertura na primeira vez, porque o app não é
   assinado por uma conta paga de desenvolvedor da Apple. Para liberar,
   abra o Terminal e rode:

       xattr -dr com.apple.quarantine /Applications/TokenBar.app

4. Abra o app normalmente. O ícone aparece na barra de menus (ex.: CC 24% CX 4%).

Se preferir não usar o Terminal: clique com o botão direito no app >
Abrir > Abrir. Em versões recentes do macOS pode ser necessário ir em
Ajustes do Sistema > Privacidade e Segurança e clicar em "Abrir Mesmo Assim".

--------------------------------------------------------------------------
OPÇÃO B — compilar na própria máquina (sem bloqueio do Gatekeeper)
--------------------------------------------------------------------------
1. Instale as ferramentas de linha de comando, se ainda não tiver:

       xcode-select --install

2. Descompacte TokenBar-1.0-fonte.tar.gz e rode:

       ./install.sh

   Isso compila, instala em ~/Applications e faz o app subir junto com o login.
   Para remover tudo depois: ./uninstall.sh

--------------------------------------------------------------------------
Observações
--------------------------------------------------------------------------
- O percentual do Codex é exato (vem do servidor, gravado nos logs dele).
- O percentual do Claude é estimado: o Claude Code não expõe o limite
  localmente. Cada pessoa deve calibrar o próprio teto no arquivo
  ~/.tokenbar/config.json, comparando com Configurações > Uso no app do
  Claude. Veja config.example.json e o README.
- O ciclo semanal reseta em dia fixo, que varia por plano. Ajuste
  claudeWeeklyResetWeekday / claudeWeeklyResetHour no config.
TXT

echo
echo "✓ pacotes em $OUT/"
ls -lh "$OUT"
