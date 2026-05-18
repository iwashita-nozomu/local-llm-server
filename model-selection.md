# Local LLM Model Selection
<!--
@dependency-start
responsibility Documents local LLM model selection for coding-agent experiments.
upstream design README.md local LLM runtime entrypoint
downstream environment models.toml machine-readable model catalog
downstream implementation ../../experiments/local-llm-agent/cases.py probes coding-agent behavior
@dependency-end
-->

This selection is for local coding-agent experiments, not for replacing the
repo's default Codex model policy.

## Primary Recommendation

For this PC, use a Qwen3 4B instruct GGUF through `llama.cpp` /
`llama-server` as the default target. The host currently exposes no NVIDIA GPU
through `nvidia-smi`, but has enough CPU threads and RAM for CPU-first
inference. Keep the first acceptance gate focused on endpoint wiring,
repeatability, and MCP tool behavior rather than large-model quality.

Use `qwen3-4b-instruct-2507-llama-cpp` as the default local profile. Try the
8B profile only after the 4B profile passes smoke and latency is acceptable.

## Remote Or GPU Capability Targets

Use `Qwen/Qwen3-Coder-480B-A35B-Instruct` as the main capability target when
hardware or a local serving host can support it. Qwen's official July 22, 2025
announcement describes it as a 480B parameter MoE model with 35B active
parameters, 256K native context, and agentic coding training aimed at
multi-turn tool interaction.

Use `zai-org/GLM-4.5-Air-FP8` as the first practical large local target when
the host has H100/H200-class GPU capacity but not enough room for the larger
Qwen target. The GLM-4.5 model card describes GLM-4.5-Air as 106B total and
12B active, MIT-licensed, with vLLM/SGLang examples and tool/reasoning parser
support.

Use a small instruct model only for wiring smoke. The smoke model is not an
acceptance target for coding-agent quality; it is only for endpoint, logging,
and managed-run validation.

## Hardware Tiers

| Tier | Use | Candidate | Notes |
| ---- | --- | --------- | ----- |
| CPU default | This PC endpoint and MCP harness | `qwen3-4b-instruct-2507-llama-cpp` | Validates local llama.cpp harness and basic chat. |
| CPU comparison | This PC quality/latency comparison | `qwen3-8b-instruct-2507-llama-cpp` | Try only after the 4B profile is stable. |
| Smoke | Endpoint wiring | `Qwen/Qwen2.5-Coder-7B-Instruct` or another small local HTTP-served model | Validates harness only. |
| Practical large | Local agent trials | `zai-org/GLM-4.5-Air-FP8` | GLM card lists FP8 Air inference on H100 x2 or H200 x1 for full-featured inference, and more GPUs for full 128K context. |
| Capability target | Serious coding-agent eval | `Qwen/Qwen3-Coder-480B-A35B-Instruct` | Best fit for agentic coding experiments if model serving capacity exists. |
| Comparison target | Secondary large model | `moonshotai/Kimi-K2-Instruct` family | Kimi K2 paper reports 1T total and 32B active; useful as a comparison, not first setup target. |

## Serving Boundary

Use the combined LocalLLM MCP container as the default boundary on this PC:

```bash
make local-llm-mcp-container-build
docker run --rm -i \
  --env-file vendor/local-llm-server/env.example \
  -p 127.0.0.1:8080:8080 \
  -v "$PWD/.state/local-llm/models:/models:ro" \
  local-llm-mcp
```

The container starts `llama-server` internally and keeps MCP stdio as the
foreground process. Use `make local-llm-mcp-container-health` from the
development container to prove that the dev image can build and run the target
MCP container before a GGUF model is downloaded.

Use vLLM only for future GPU-host comparison runs:


```bash
vllm serve Qwen/Qwen3-Coder-480B-A35B-Instruct \
  --host 0.0.0.0 \
  --port 8000 \
  --dtype auto \
  --served-model-name "${LOCAL_LLM_MODEL:-Qwen/Qwen3-Coder-480B-A35B-Instruct}" \
  --generation-config vllm
```

For GLM-4.5-Air, start with the model-card parser flags:

```bash
vllm serve zai-org/GLM-4.5-Air-FP8 \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size "${LOCAL_LLM_TENSOR_PARALLEL_SIZE:-1}" \
  --tool-call-parser glm45 \
  --reasoning-parser glm45 \
  --enable-auto-tool-choice \
  --served-model-name glm-4.5-air-fp8
```

## Experiment Protocol

Run `make local-llm-smoke` first. It exercises the managed-run path in offline
mode and should pass without a model server.

Run `make local-llm-probe` only after a real endpoint is up. The probe checks:

- basic instruction following;
- JSON-ish command planning;
- patch-oriented coding response;
- tool-use phrasing stability.

Do not compare models from ad hoc chat transcripts. Use managed experiment
runs so `summary.json`, `cases.jsonl`, `run_manifest.json`, and the report
stub stay together.

## Sources

- Qwen3-Coder official blog, 2025-07-22:
  <https://qwenlm.github.io/blog/qwen3-coder/>
- GLM-4.5 model card:
  <https://huggingface.co/zai-org/GLM-4.5>
- GLM-4.5 arXiv report:
  <https://arxiv.org/abs/2508.06471>
- Kimi K2 arXiv report:
  <https://arxiv.org/abs/2507.20534>
