# hermes-ollama-fallback

Skill + script de setup para o **Hermes Agent** usar o **Ollama self-hosted no Proxmox** como *fallback* (ou *primário*) do modelo.

Endereço fixo do Proxmox usado em tudo abaixo: **`192.168.31.2:11434`**
(é sempre o mesmo na sua instalação — ajuste a variável no script se mudar).

---

## O que este repositório contém

| Arquivo | Para que serve |
|---|---|
| `.hermes/skills/configuration/ollama-fallback/SKILL.md` | O skill do Hermes (procedimento documentado). |
| `setup-ollama-fallback.sh` | Script bash que aplica TUDO automaticamente (idempotente, faz backup do config). |
| `README.md` | Este arquivo. |

---

## Pré-requisitos (na máquina onde roda o Hermes)

1. Hermes já instalado e funcionando com um provider principal (ex.: nous / openrouter / openai).
2. O Ollama do Proxmox acessível de onde o Hermes está. Teste:
   ```bash
   curl -s http://192.168.31.2:11434/api/tags
   ```
   Tem que responder JSON (mesmo que `"models":[]`).
3. Modelos de fallback já baixados no servidor Ollama. Se faltar algum:
   ```bash
   curl -X POST http://192.168.31.2:11434/api/pull -H "Content-Type: application/json" \
     -d '{"name":"hermes3:8b","stream":false}'
   curl -X POST http://192.168.31.2:11434/api/pull -H "Content-Type: application/json" \
     -d '{"name":"deepseek-r1:8b","stream":false}'
   ```

---

## Como importar/usar de forma automática (recomendado)

### Opção A — deixar o próprio Hermes rodar o script
1. Clone ou copie este repo para a máquina alvo.
2. Pergunte ao Hermes: **"rode setup-ollama-fallback.sh"** (ou cole o conteúdo do script).
3. O Hermes executa e deixa o config pronto. Valide:
   ```bash
   hermes fallback list
   ```
4. Teste: force uma falha do primário (ou aponte o primário pra uma URL inválida temporariamente) e veja o Hermes cair pro Ollama.

### Opção B — rodar manualmente no shell
```bash
bash setup-ollama-fallback.sh            # adiciona fallback (mantém seu primário atual)
# ou
bash setup-ollama-fallback.sh --primary  # faz o Ollama ser o provider primário
```

O script:
- faz backup do `config.yaml` antes de mexer;
- injeta o bloco `fallback_providers` como **YAML real** (o `hermes config set` não lida com listas — essa é a pegadinha);
- ajusta `model.ollama_num_ctx=131072` e `agent.reasoning_effort=""` (obrigatório, senão o Ollama antigo dá HTTP 400 "does not support thinking");
- valida com `hermes fallback list`.

### Opção C — instalar o skill e pedir ao Hermes
Copie a pasta `.hermes/skills/configuration/ollama-fallback/` para
`~/.hermes/skills/configuration/ollama-fallback/` e peça: **"use o skill ollama-fallback"**.

---

## Configuração aplicada (resumo)

```yaml
model:
  provider: nous                     # seu primário atual (não mexido, a menos que use --primary)
  default: tencent/hy3:free
  base_url: https://inference-api.nousresearch.com/v1
  ollama_num_ctx: 131072             # global, só afeta a rota custom/Ollama
agent:
  reasoning_effort: ""               # vazio OBRIGATÓRIO (global)

fallback_providers:
  - provider: custom
    model: hermes3:8b
    base_url: http://192.168.31.2:11434/v1
  - provider: custom
    model: deepseek-r1:8b
    base_url: http://192.168.31.2:11434/v1
```

---

## Pegadinhas que este setup contorna (descobertas na prática)

1. **Provider tem que ser `custom`** apontando pro endpoint OpenAI-compatible `http://192.168.31.2:11434/v1`. O Hermes não tem plugin `ollama` nativo (só `ollama-cloud`).
2. **Hermes exige ≥ 64K de contexto.** Se o modelo anunciar menos, o Hermes aborta na inicialização. `hermes3:8b`/`deepseek-r1:8b` têm 128K nativo → use `131072`. Para um modelo menor sem 128K, use `65536` (64K mínimo).
3. **`agent.reasoning_effort` DEVE ficar vazio (`""`).** Com `medium` (default), o Hermes manda `reasoning_effort` e o Ollama antigo rejeita com HTTP 400 "does not support thinking". Vazio → `reasoning_config=None` → o plugin custom não manda o campo. ⚠️ Isso desliga o thinking **globalmente** (também no primário na nuvem). Se o seu primário usa reasoning, atualize o Ollama ou mantenha um primário que não dependa disso.
4. **`hermes config set fallback_providers '[...]'` NÃO funciona** — salva a lista como string e o Hermes ignora. Por isso o script edita o `config.yaml` direto (com backup).
5. O `patch`/edição direta do `config.yaml` por ferramenta é bloqueado por segurança no Hermes, por isso usamos um script python/bash que roda no shell da máquina (com backup antes).

---

## Notas

- Sem limite de fallbacks — a cadeia é uma lista ordenada; o Hermes tenta cada um até um funcionar. 2–3 é prático.
- O fallback só dispara em erro de rate-limit / overload / conexão do primário (não em erro de conteúdo).
- Ollama neste Proxmox é CPU-only e lento (8B ~2 min/resposta). Use como reserva, não como cargo principal, salvo com `--primary`.
- Para adicionar mais fallbacks, repita o bloco `- provider: custom / model: X / base_url: ...` no `config.yaml`.

## Como atualizar este repo

```bash
cp /root/.hermes/skills/configuration/ollama-fallback/SKILL.md .hermes/skills/configuration/ollama-fallback/SKILL.md
git add -A && git commit -m "update" && git push
```
