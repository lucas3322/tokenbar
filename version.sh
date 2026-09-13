#!/bin/bash
# Sobe a versão do app, no espírito do `npm version`.
#   ./version.sh patch    1.1.0 -> 1.1.1   (correções)
#   ./version.sh minor    1.1.0 -> 1.2.0   (recursos novos)
#   ./version.sh major    1.1.0 -> 2.0.0   (quebra de compatibilidade)
#   ./version.sh 2.3.1    define exatamente
# Sem --no-git, cria o commit e a tag correspondentes.
set -euo pipefail
cd "$(dirname "$0")"

CURRENT="$(cat VERSION)"
IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "${1:-}" in
  patch) NEW="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) NEW="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEW="$((MAJOR + 1)).0.0" ;;
  [0-9]*.[0-9]*.[0-9]*) NEW="$1" ;;
  *) echo "uso: ./version.sh patch|minor|major|X.Y.Z [--no-git]"; exit 1 ;;
esac

echo "$NEW" > VERSION
echo "$CURRENT -> $NEW"

if [ "${2:-}" != "--no-git" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  git add VERSION
  git commit -q -m "Versão $NEW"
  git tag -a "v$NEW" -m "Versão $NEW"
  echo "✓ commit e tag v$NEW criados"
fi

./build.sh
