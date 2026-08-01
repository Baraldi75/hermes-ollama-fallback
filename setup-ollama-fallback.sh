#!/usr/bin/env bash
#
# setup-ollama-fallback.sh
# ---------------------------------------------------------------------------
# Configura o Hermes Agent com uma cadeia de FALLBACK (ou opcionalmente
# PRIMARY via Ollama) da seguinte forma:
#
#   Fallback chain:
#     1. nvidia/nemotron-3-ultra-550b-a55b:free  (via openrouter)
#     2. hermes3:8b      (via custom -> Ollama no Proxmox 192.168.31.2:11434)
#     3. deepseek-r1:8b  (via custom -> Ollama no Proxmox 192.168.31.2:11434)
#
# O OpenRouter usa a OPENROUTER_API_KEY ja presente no .env do Hermes
# (o Hermes a resolve automaticamente - nenhuma chave e hardcoded aqui).
# O Ollama self-hosted fica no Proxmox (192.168.31.2:11434), CPU-only.
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
MODEL_1="hermes3:8b"      # primario do fallback Ollama (128K nativo)
MODEL_2="deepseek-r1:8b"  # segundo da cadeia Ollama (128K nativo)

# >>> Primeiro fallback via OpenRouter <<<
OR_PROVIDER="openrouter"
OR_MODEL="nvidia/nemotron-3-ultra-550b-a55b:free"

CONFIG="${HERMES_HOME:-$HOME/.hermes}/config.yaml"

echo "=== Ollama + OpenRouter fallback setup (Proxmox: $OLLAMA_HOST) ==="

# 0. Verifica alcanchabilidade do Ollama (nao bloqueia se a rede ainda nao foi ligada)
echo ">> testando Ollama em $OLLAMA_API ..."
if curl -s --max-time 8 "$OLLAMA_API" >/dev/null 2>&1; then
  echo "   Ollama respondeu OK."
else
  echo "   AVISO: Ollama em $OLLAMA_HOST nao respondeu. Continuando (configure a rede/Proxmox primeiro)."
fi

# 0b. Avisa sobre a chave do OpenRouter (usada automaticamente pelo Hermes)
if grep -q "^OPENROUTER_API_KEY=" "${HERMES_HOME:-$HOME/.hermes}/.env" 2>/dev/null; then
  echo "   OPENROUTER_API_KEY detectada no .env (sera usada para o fallback do Nemotron)."
else
  echo "   AVISO: OPENROUTER_API_KEY nao encontrada no .env. O fallback openrouter vai falhar sem ela."
  echo "          Pegue uma em https://openrouter.ai/keys e adicione ao .env do Hermes."
fi

# 1. Backup do config antes de mexer
BACKUP="${CONFIG}.bak.$(date +%s)"
cp "$CONFIG" "$BACKUP"
echo ">> backup do config: $BACKUP"

# 2. Injeta o bloco fallback_providers como YAML real (o 'config set' nao lida com listas)
python3 - "$CONFIG" "$OLLAMA_BASE_URL" "$MODEL_1" "$MODEL_2" "$OR_PROVIDER" "$OR_MODEL" <<'PY'
import sys

path, base_url, m1, m2, orp, orm = sys.argv[1:7]

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

# Ordem: OpenRouter (Nemotron) primeiro, depois os dois Ollama do Proxmox.
block = [
    "",
    "fallback_providers:",
    f"  - provider: {orp}",
    f"    model: {orm}",
    "  - provider: custom",
    f"    model: {m1}",
    f"    base_url: {base_url}",
    "  - provider: custom",
    f"    model: {m2}",
    f"    base_url: {base_url}",
]
with open(path, "w") as f:
    f.write("\n".join(cleaned + block) + "\n")
print(">> fallback_providers gravado no config.yaml (openrouter primeiro, depois Ollama)")
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
