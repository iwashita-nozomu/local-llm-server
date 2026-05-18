# @dependency-start
# responsibility Builds the repo-local LocalLLM MCP container with llama.cpp inside.
# upstream design README.md documents the LocalLLM runtime boundary.
# upstream design model-selection.md selects the default this-PC model profile.
# upstream design ../../docker/README.md documents development-container Docker usage.
# upstream implementation ../../python/local_llm_agent/mcp_server.py provides the MCP stdio process.
# downstream environment env.example provides runtime defaults.
# downstream implementation ../../Makefile exposes build/run smoke targets.
# @dependency-end

ARG PYTHON_VERSION=3.11

FROM debian:bookworm-slim AS llama-builder

ARG LLAMA_CPP_REF=master
ARG LLAMA_CPU_MARCH=haswell
ARG LLAMA_CPU_MTUNE=haswell

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libcurl4-openssl-dev \
        libopenblas-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp /src/llama.cpp \
    && cd /src/llama.cpp \
    && git fetch --depth 1 origin "${LLAMA_CPP_REF}" \
    && git checkout FETCH_HEAD \
    && cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG -march=${LLAMA_CPU_MARCH} -mtune=${LLAMA_CPU_MTUNE}" \
        -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -march=${LLAMA_CPU_MARCH} -mtune=${LLAMA_CPU_MTUNE}" \
        -DLLAMA_CURL=ON \
        -DGGML_BLAS=ON \
        -DGGML_BLAS_VENDOR=OpenBLAS \
        -DGGML_LTO=ON \
        -DGGML_NATIVE=ON \
        -DGGML_OPENMP=ON \
    && cmake --build build --target llama-server -j "$(nproc)"

FROM python:${PYTHON_VERSION}-slim-bookworm AS local-llm-mcp

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libopenblas0-pthread \
        libgomp1 \
        openssh-client \
        tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY --from=llama-builder /src/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=llama-builder /src/llama.cpp/build/bin/lib*.so* /usr/local/lib/
COPY python/local_llm_agent /workspace/python/local_llm_agent
COPY vendor/local-llm-server/models.toml /workspace/vendor/local-llm-server/models.toml
COPY vendor/local-llm-server/entrypoint.sh /workspace/vendor/local-llm-server/entrypoint.sh

ENV PYTHONPATH=/workspace/python \
    LD_LIBRARY_PATH=/usr/local/lib \
    LOCAL_LLM_BASE_URL=http://127.0.0.1:8080/v1 \
    LOCAL_LLM_PROFILE=qwen3-4b-instruct-2507-llama-cpp \
    LOCAL_LLM_MODEL=qwen3-4b-instruct-2507 \
    LOCAL_LLM_CATALOG_PATH=/workspace/vendor/local-llm-server/models.toml \
    LOCAL_LLM_HOST=0.0.0.0 \
    LOCAL_LLM_PORT=8080 \
    LOCAL_LLM_GGUF_PATH=/models/qwen3-4b-instruct-2507-q4_k_m.gguf \
    LOCAL_LLM_CONTEXT_TOKENS=8192 \
    LOCAL_LLM_THREADS=28 \
    LOCAL_LLM_THREADS_BATCH=28 \
    LOCAL_LLM_THREADS_HTTP=4 \
    LOCAL_LLM_OMP_THREADS=28 \
    LOCAL_LLM_OMP_DYNAMIC=FALSE \
    LOCAL_LLM_OMP_WAIT_POLICY=PASSIVE \
    LOCAL_LLM_BLAS_THREADS=1 \
    LOCAL_LLM_PARALLEL=1 \
    LOCAL_LLM_BATCH_SIZE=2048 \
    LOCAL_LLM_UBATCH_SIZE=512 \
    LOCAL_LLM_POLL=0 \
    LOCAL_LLM_POLL_BATCH=0 \
    LOCAL_LLM_START_SERVER=1 \
    LOCAL_LLM_READY_TIMEOUT_SECONDS=120 \
    OPENBLAS_NUM_THREADS=1 \
    OMP_PROC_BIND=close \
    OMP_PLACES=cores

RUN mkdir -p /models /runtime \
    && chmod +x /workspace/vendor/local-llm-server/entrypoint.sh

EXPOSE 8080
VOLUME ["/models", "/runtime"]

ENTRYPOINT ["tini", "--"]
CMD ["/workspace/vendor/local-llm-server/entrypoint.sh"]
