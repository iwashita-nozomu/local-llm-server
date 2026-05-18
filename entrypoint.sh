#!/bin/sh
# @dependency-start
# responsibility Starts llama-server with repo-local runtime tuning knobs before launching the MCP stdio process.
# upstream environment Dockerfile packages this script in the LocalLLM container.
# upstream environment env.example documents the LOCAL_LLM_* variables consumed here.
# downstream implementation ../../python/local_llm_agent/mcp_server.py runs as the foreground MCP stdio process.
# @dependency-end
set -eu

mkdir -p /runtime
export OPENBLAS_NUM_THREADS="${LOCAL_LLM_BLAS_THREADS:-1}"
export OMP_NUM_THREADS="${LOCAL_LLM_OMP_THREADS:-${LOCAL_LLM_THREADS:-28}}"
export OMP_DYNAMIC="${LOCAL_LLM_OMP_DYNAMIC:-FALSE}"
export OMP_WAIT_POLICY="${LOCAL_LLM_OMP_WAIT_POLICY:-PASSIVE}"

if [ "${LOCAL_LLM_START_SERVER:-1}" = "1" ]; then
  set -- llama-server \
    --host "$LOCAL_LLM_HOST" \
    --port "$LOCAL_LLM_PORT" \
    --model "$LOCAL_LLM_GGUF_PATH" \
    --ctx-size "$LOCAL_LLM_CONTEXT_TOKENS" \
    --threads "$LOCAL_LLM_THREADS" \
    --threads-batch "${LOCAL_LLM_THREADS_BATCH:-$LOCAL_LLM_THREADS}" \
    --threads-http "${LOCAL_LLM_THREADS_HTTP:-4}" \
    --parallel "${LOCAL_LLM_PARALLEL:-1}" \
    --batch-size "${LOCAL_LLM_BATCH_SIZE:-2048}" \
    --ubatch-size "${LOCAL_LLM_UBATCH_SIZE:-512}"

  if [ -n "${LOCAL_LLM_CPU_RANGE:-}" ]; then
    set -- "$@" --cpu-range "$LOCAL_LLM_CPU_RANGE" --cpu-range-batch "$LOCAL_LLM_CPU_RANGE"
  fi
  if [ -n "${LOCAL_LLM_CPU_STRICT:-}" ]; then
    set -- "$@" --cpu-strict "$LOCAL_LLM_CPU_STRICT" --cpu-strict-batch "$LOCAL_LLM_CPU_STRICT"
  fi
  if [ -n "${LOCAL_LLM_PRIO:-}" ]; then
    set -- "$@" --prio "$LOCAL_LLM_PRIO"
  fi
  if [ -n "${LOCAL_LLM_PRIO_BATCH:-}" ]; then
    set -- "$@" --prio-batch "$LOCAL_LLM_PRIO_BATCH"
  fi
  if [ -n "${LOCAL_LLM_POLL:-}" ]; then
    set -- "$@" --poll "$LOCAL_LLM_POLL"
  fi
  if [ -n "${LOCAL_LLM_POLL_BATCH:-}" ]; then
    set -- "$@" --poll-batch "$LOCAL_LLM_POLL_BATCH"
  fi
  if [ -n "${LOCAL_LLM_NUMA:-}" ]; then
    set -- "$@" --numa "$LOCAL_LLM_NUMA"
  fi

  printf 'llama-server command:' >/runtime/llama-server.command
  printf ' %s' "$@" >>/runtime/llama-server.command
  printf '\n' >>/runtime/llama-server.command

  "$@" >/runtime/llama-server.log 2>&1 &
  server_pid=$!
  ready=0
  for _ in $(seq 1 "${LOCAL_LLM_READY_TIMEOUT_SECONDS:-120}"); do
    if curl -fsS "http://127.0.0.1:${LOCAL_LLM_PORT}/v1/models" >/dev/null 2>&1 ||
      curl -fsS "http://127.0.0.1:${LOCAL_LLM_PORT}/health" >/dev/null 2>&1; then
      ready=1
      break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat /runtime/llama-server.log >&2 || true
      exit 1
    fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "llama-server readiness timeout; MCP will still start" >&2
  fi
fi

exec python -m local_llm_agent.mcp_server --stdio
