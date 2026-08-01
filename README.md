# hermes-ollama-fallback

Hermes Agent skill que configura um servidor Ollama self-hosted/remoto como
fallback (ou provider primário) do Hermes.

## O que ele faz
Encapsula o procedimento validado de:
- apontar o Hermes para o endpoint OpenAI-compatible do Ollama (`/v1`)
- respeitar o limite mínimo de 64K de contexto do Hermes
- contornar o bug do `reasoning_effort` em Ollamas antigos (HTTP 400)
- adicionar `fallback_providers` corretamente no `config.yaml`

## Instalação
Copie a pasta `.hermes/skills/configuration/ollama-fallback/` para
`~/.hermes/skills/configuration/ollama-fallback/` na sua instalação do Hermes.

Depois peça ao Hermes: "use o skill ollama-fallback".

## Detalhes
Veja `SKILL.md` para o procedimento completo.
