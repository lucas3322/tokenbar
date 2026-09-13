#!/bin/bash
# Embarca o instalador da versão atual na landing e registra a versão no
# versions.json. Rode depois de ./version.sh, antes de subir para o Railway.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
ZIP="dist/TokenBar-$VERSION-AppleSilicon.zip"

[ -f "$ZIP" ] || ./dist.sh >/dev/null

# Só a versão corrente fica no repositório: cada .zip pesa ~1 MB e o histórico
# do git guarda todas as anteriores de qualquer forma.
rm -f landing/download/*.zip
cp "$ZIP" landing/download/

TAMANHO=$(du -k "$ZIP" | cut -f1)
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

python3 - "$VERSION" "$TAMANHO" "$SHA" <<'PY'
import json, sys, os, datetime, subprocess

versao, tamanho_kb, sha = sys.argv[1], int(sys.argv[2]), sys.argv[3]
caminho = "landing/versions.json"
dados = json.load(open(caminho)) if os.path.exists(caminho) else {"versoes": []}

# As notas saem do corpo do commit da tag, se houver — assim a fonte da verdade
# do que mudou continua sendo o histórico, não um arquivo editado à mão.
notas = []
try:
    corpo = subprocess.run(["git", "tag", "-l", "--format=%(contents:body)", f"v{versao}"],
                           capture_output=True, text=True).stdout.strip()
    notas = [l.lstrip("- ").strip() for l in corpo.split("\n") if l.strip()]
except Exception:
    pass

entrada = {
    "versao": versao,
    "data": datetime.date.today().isoformat(),
    "arquivo": f"download/TokenBar-{versao}-AppleSilicon.zip",
    "tamanhoKB": tamanho_kb,
    "sha256": sha,
    "notas": notas,
}

# Notas escritas à mão têm precedência: o corpo da tag costuma estar vazio,
# e apagar o changelog a cada sync seria pior do que não ter sync.
anterior = next((v for v in dados["versoes"] if v["versao"] == versao), None)
if anterior and anterior.get("notas") and not notas:
    entrada["notas"] = anterior["notas"]
    entrada["titulo"] = anterior.get("titulo", "")
elif anterior:
    entrada["titulo"] = anterior.get("titulo", "")

dados["versoes"] = [v for v in dados["versoes"] if v["versao"] != versao]
dados["versoes"].insert(0, entrada)
dados["atual"] = versao
json.dump(dados, open(caminho, "w"), indent=2, ensure_ascii=False)
print(f"✓ versions.json atualizado — {versao} ({tamanho_kb} KB)")
PY

echo "✓ instalador embarcado em landing/download/"
