#!/usr/bin/env bash
#
# setup-ollama-fallback.sh
# ---------------------------------------------------------------------------
# Configura o Hermes Agent para usar o Ollama self-hosted no Proxmox
# (192.168.31.2:11434) como FALLBACK (ou opcionalmente como PRIMARIO).
#
# Tudo que este script faz foi validado contra um Ollama real + Hermes CLI.
# Ele e idempotente: pode rodar quantas vezes quiser; faz backup do
# config.yaml antes de qualquer alteracao.
#
# Uso:
#   bash setup-ollama-fallback.sh            # adiciona o fallback (primary atual mantido)
#   bash setup-ollama-fallback.sh --primary  # faz o Ollama ser o provider primario
#
# Como "importar" no Hermes de forma automatica:
#   - Copie este script para a maquina alvo (ou esteja dentro deste repo).
#   - Pergunte ao Hermes: "rode setup-ollama-fallback.sh"  (ou cole o conteudo).
#   - O Hermes executa e deixa o config pronto; valide com 'hermes fallback list'.
# ---------------------------------------------------------------------------
set -euo pipefail

# >>> Enderecos fixos do Proxmox (sempre os mesmos) <<<
OLLAMA_HOST="192.168.31.2:11434"
OLLAMA_API="http://${OLLAMA_HOST}/api/tags"
OLLAMA_BASE_URL="http://${OLLAMA_HOST}/v1"
MODEL_1="hermes3:8b"      # primario do fallback (128K nativo)
MODEL_2="deepseek-r1:8b"  # segundo da cadeia (128K nativo)

CONFIG="${HERMES_HOME:-$HOME/.hermes}/config.yaml"

echo "=== Ollama fallback setup (Proxmox: $OLLAMA_HOST) ==="

# 0. Verifica alcanchabilidade do Ollama (nao bloqueia se a rede ainda nao foi ligada)
echo ">> testando Ollama em $OLLAMA_API ..."
if curl -s --max-time 8 "$OLLAMA_API" >/dev/null 2>&1; then
  echo "   Ollama respondeu OK."
else
  echo "   AVISO: Ollama em $OLLAMA_HOST nao respondeu. Continuando (configure a rede/Proxmox primeiro)."
fi

# 1. Backup do config antes de mexer
BACKUP="${CONFIG}.bak.$(date +%s)"
cp "$CONFIG" "$BACKUP"
echo ">> backup do config: $BACKUP"

# 2. Injeta o bloco fallback_providers como YAML real (o 'config set' nao lida com listas)
python3 - "$CONFIG" "$OLLAMA_BASE_URL" "$MODEL_1" "$MODEL_2" <<'PY'
import sys, os

path, base_url, m1, m2 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(path) as f:
    lines = f.read().split("\n")

# remove qualquer bloco fallback_providers existente (cabecalho + entradas indentadas)
cleaned, skip = [], False
for l in lines:
    if l.strip().startswith("fallback_providers:"):
        skip = True
        continue
    if skip:
        if l.startswith("  ") or l.strip() == "":
            continue
        skip = False
    cleaned.append(l)

while cleaned and cleaned[-1].strip() == "":
    cleaned.pop()

block = [
    "",
    "fallback_providers:",
    "  - provider: custom",
    f"    model: {m1}",
    f"    base_url: {base_url}",
    "  - provider: custom",
    f"    model: {m2}",
    f"    base_url: {base_url}",
]
with open(path, "w") as f:
    f.write("\n".join(cleaned + block) + "\n")
print(">> fallback_providers gravado no config.yaml")
PY

# 3. Ajustes globais obrigatorios para o Ollama antigo nao dar HTTP 400
echo ">> ajustando configs globais (ollama_num_ctx / reasoning_effort)"
hermes config set model.ollama_num_ctx 131072
hermes config set agent.reasoning_effort ""

# 4. (opcional) tornar o Ollama o primario
if [[ "${1:-}" == "--primary" ]]; then
  echo ">> modo --primary: Ollama sera o provider primario"
  hermes config set model.provider custom
  hermes config set model.base_url "$OLLAMA_BASE_URL"
  hermes config set model.default "$MODEL_1"
  hermes config set model.context_length 131072
fi

# 5. Valida
echo "=== validando com 'hermes fallback list' ==="
hermes fallback list || true
echo
echo "Pronto. Backup em: $BACKUP"
