# Local LLM Runtime
<!--
@dependency-start
responsibility Documents local LLM runtime configuration for coding-agent experiments.
upstream design ../../docker/README.md docker runtime guidance
downstream design model-selection.md local model selection rationale
downstream implementation ../../experiments/local-llm-agent/experimentcode.py probes llama.cpp-compatible endpoints
downstream implementation ../../tools/ci/check_fresh_clone.sh excludes model caches from clone overlays
downstream environment ../../.dockerignore excludes local model artifacts from Docker build context
downstream environment ../../docker/codex-container-profiles.toml forwards local LLM environment variables
@dependency-end
-->

This vendored repository is the LocalLLM server runtime source of truth. The
wrapper repository keeps experiment harnesses, MCP tool code, and CLI clients in
the main tree, while `vendor/local-llm-server/` owns the llama.cpp server image,
entrypoint, environment defaults, and model catalog. The runtime source of truth
is `vendor/local-llm-server/Dockerfile`: one LocalLLM MCP
container starts `llama-server` internally and exposes the MCP stdio process in
the foreground.

## Decision

- Use `llama.cpp` / `llama-server` as the first this-PC serving target.
- Keep vLLM as a future GPU-host comparison path, not the default local path.
- Use `LOCAL_LLM_*` variables inside the MCP container as the boundary between
  `llama-server` and MCP tool code.
- Keep devcontainers development-only. The development image must be able to
  build and run this MCP container for validation, but it is not the inference
  runtime.
- Use `experiments/local-llm-agent/` for prompt/response experiments.
- Keep LocalLLM-specific skill packets under `local/skills/`; do not share them
  through AgentCanon or `.agents/skills/`.

## Endpoint Environment

Start from the example file:

```bash
cp vendor/local-llm-server/env.example .state/local-llm.env
```

Edit `.state/local-llm.env`. The MCP container consumes this file through
`docker run --env-file`; shell commands can still source it explicitly:

```bash
set -a
. .state/local-llm.env
set +a
```

Minimum variables for the combined MCP/LLM container:

```bash
export LOCAL_LLM_BASE_URL=http://127.0.0.1:8080/v1
export LOCAL_LLM_PROFILE=qwen3-4b-instruct-2507-llama-cpp
export LOCAL_LLM_MODEL=qwen3-4b-instruct-2507
export LOCAL_LLM_GGUF_PATH=/models/qwen3-4b-instruct-2507-q4_k_m.gguf
```

The LocalLLM MCP container reads these variables directly.

## MCP/LLM Container

Build the LocalLLM MCP container:

```bash
make local-llm-mcp-container-build
```

The image builds `llama.cpp` for the current CPU-only target with OpenMP,
OpenBLAS, LTO, and Haswell/AVX2 release flags. Runtime defaults are tuned for
single-user CLI use: `LOCAL_LLM_THREADS=28`, `LOCAL_LLM_THREADS_BATCH=28`,
`LOCAL_LLM_THREADS_HTTP=4`, `LOCAL_LLM_OMP_THREADS=28`,
`LOCAL_LLM_PARALLEL=1`, and `LOCAL_LLM_BLAS_THREADS=1`.

Runtime CPU placement can be adjusted without rebuilding:

```bash
LOCAL_LLM_THREADS=56
LOCAL_LLM_THREADS_BATCH=56
LOCAL_LLM_OMP_THREADS=56
LOCAL_LLM_CPU_RANGE=0-55
LOCAL_LLM_CPU_STRICT=1
LOCAL_LLM_PRIO=2
LOCAL_LLM_POLL=100
LOCAL_LLM_OMP_WAIT_POLICY=ACTIVE
```

Do not assume more threads are faster. On this host the physical-core baseline
is 28 threads; 56 threads uses SMT and must be measured. `LOCAL_LLM_POLL=100`
and `LOCAL_LLM_OMP_WAIT_POLICY=ACTIVE` can reduce wait latency but will burn CPU
while idle.

Run the actual container in offline health mode. This is the development
container smoke target: it validates that the dev environment can build and
start the MCP container without requiring a GGUF model download.

```bash
make local-llm-mcp-container-health
```

Run the real MCP container with `llama-server` enabled after the GGUF file is
mounted:

```bash
make local-llm-mcp-container-run
```

The container writes `llama-server` logs under `/runtime` so MCP stdio remains
clean JSON-RPC.

List the repo-local MCP tools without a live model:

```bash
make local-llm-mcp-tools
```

Run an offline host-side health check:

```bash
make local-llm-mcp-health
```

SSH dispatch is available through `local_llm.ssh_exec`, but it defaults to
dry-run and only executes commands listed in `LOCAL_LLM_SSH_ALLOWED_COMMANDS`.
Use SSH for allowlisted operational dispatch only; do not install host-local
LLM runtime dependencies through SSH.

## Harness Smoke

Validate the managed experiment shape without a running model:

```bash
make local-llm-smoke
```

Probe a real endpoint after `LOCAL_LLM_BASE_URL` and `LOCAL_LLM_MODEL` are set:

```bash
make local-llm-probe
```

The probe writes canonical experiment artifacts under:

```text
experiments/local-llm-agent/result/<run_name>/
experiments/report/<run_name>.md
```

## Model Catalog

The repo-local shortlist lives in `models.toml`; the reasoning and hardware
tiers live in `model-selection.md`.

## Model Artifact Storage

Keep GGUF and other model weight files outside repository copies. The canonical
host cache for this repo is `.state/local-llm/models/`, mounted into the MCP
container as `/models`. That cache is ignored by git, excluded from Docker build
contexts, and excluded from fresh-clone/test overlays.

Do not put model binaries under tracked experiment results or template fixture
copies. Reports should record the model id, quantization, source URL or catalog
entry, file size, checksum when available, and the cache path used for the run.
If a container or test needs a model, download or mount it into the cache at
runtime instead of copying it with the repo workspace.

## MCP Tool CLI

Use the repo-local MCP entrypoint for direct one-shot checks. It does not use
Codex skills, `.codex/agents`, or vendor config.

```bash
make local-llm-mcp-tools
make local-llm-mcp-health
make local-llm-chat ARGS='{"prompt":"Suggest a search strategy for a noisy optimization objective."}'
```

## Interactive CLI

Use the Rust CLI for direct terminal chat with the running llama.cpp server:

```bash
make local-llm-cli-build
make local-llm-cli
make local-llm-cli ARGS='-- "Return exactly: ok"'
```

The CLI reads `.state/local-llm.env` by default. If direct HTTP access to
`LOCAL_LLM_BASE_URL` is not reachable from the development shell, it falls back
to `docker exec` through `.state/local-llm/container.name`.

The interactive REPL is line-oriented. Use `/paste` and finish with `/send` to
submit multiline context as one message, or `/file PATH` to submit a UTF-8 file
as one message. Use `/status` to inspect the selected Docker container, current
resource use, and recent `llama-server` token timings without sending another
prompt.

Model swapping is intentionally catalog-driven. Change `LOCAL_LLM_PROFILE` or
`LOCAL_LLM_MODEL` without editing Codex or AgentCanon configuration.

AgentCanon remains a development harness for this repository. The local LLM
runtime code lives in `python/local_llm_agent/`, with model profiles in
`vendor/local-llm-server/models.toml`.
