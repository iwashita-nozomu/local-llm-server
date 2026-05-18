<!--
@dependency-start
responsibility Documents repo-local llama.cpp serving layout for the LocalLLM harness.
upstream design ../README.md local LLM runtime entrypoint
upstream design ../../../local/skills/local-llm-harness/SKILL.md local-only harness boundary
downstream environment env.example provides llama.cpp environment defaults
downstream implementation ../../../python/local_llm_agent/mcp_server.py consumes llama.cpp endpoint settings
@dependency-end
-->

# llama.cpp Runtime

This directory records CPU-first `llama.cpp` model and artifact layout notes.
The executable runtime is the combined MCP/LLM container built from
`vendor/local-llm-server/Dockerfile`; this directory is intentionally not part of
AgentCanon.

## Directory Contract

Expected local runtime layout:

```text
vendor/local-llm-server/llama-cpp/
├── README.md
├── env.example
├── models/      # local GGUF files, ignored by git when populated
├── runtime/     # llama-server logs and pid files, ignored by git when populated
└── cache/       # transient download/cache files, ignored by git when populated
```

Keep large GGUF files out of git. Store them under `.state/local-llm/models/`
or `vendor/local-llm-server/llama-cpp/models/` only after confirming local ignore
rules for the chosen path.

## Recommended First Model

Use a Qwen3 4B instruct GGUF quantization first:

- Profile id: `qwen3-4b-instruct-2507-llama-cpp`
- Runtime: `llama-server`
- Quantization target: `Q4_K_M` first, `Q5_K_M` if latency is acceptable
- Context target: `8192` by default, higher only after live smoke

## Container Start Shape

Build and run the LocalLLM MCP container. It starts `llama-server` internally
and then exposes the MCP stdio process:

```bash
make local-llm-mcp-container-build
docker run --rm -i \
  --env-file vendor/local-llm-server/env.example \
  -p 127.0.0.1:8080:8080 \
  -v "$PWD/.state/local-llm/models:/models:ro" \
  local-llm-mcp
```

The harness talks to:

```text
LOCAL_LLM_BASE_URL=http://127.0.0.1:8080/v1
LOCAL_LLM_MODEL=qwen3-4b-instruct-2507
```

## Offline Harness Check

The first implementation does not require a downloaded model:

```bash
make local-llm-mcp-tools
make local-llm-mcp-health
make local-llm-mcp-container-health
```
