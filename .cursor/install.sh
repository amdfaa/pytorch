#!/usr/bin/env bash
# Cursor Cloud environment setup for PyTorch (CPU-only development build).
#
# This is referenced by .cursor/environment.json as the "install" (update)
# command and runs on every cloud-agent boot. It is intentionally idempotent
# and self-contained so it works both:
#   * on a plain base image (it will do the full one-time source build), and
#   * on a saved snapshot that already contains the build (the heavy build is
#     skipped whenever `import torch` already succeeds).
#
# See AGENTS.md -> "Cursor Cloud specific instructions" for background.
set -euo pipefail

# Always operate from the repository root (this file lives in <root>/.cursor).
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "== [1/6] System build dependencies =="
# Non-fatal: base images usually have these; ignore if apt/sudo is unavailable.
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq || true
  sudo apt-get install -y --no-install-recommends \
    ccache python3-dev python3-venv build-essential || true
fi

echo "== [2/6] uv (used by lintrunner adapters) =="
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
  curl -LsSf https://astral.sh/uv/install.sh | sh || true
fi
export PATH="$HOME/.local/bin:$PATH"

echo "== [3/6] Python virtualenv + dev/build dependencies =="
if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
fi
.venv/bin/python -m pip install --upgrade pip >/dev/null
.venv/bin/python -m pip install -r requirements.txt

echo "== [4/6] git submodules (third_party/*) =="
git submodule update --init --recursive --jobs 4 || true

echo "== [5/6] Build CPU-only torch (only if not already importable) =="
if ! .venv/bin/python -c "import torch" >/dev/null 2>&1; then
  echo "   torch is not importable -> building from source (this is slow the first time)"
  # NOTE: the system default cc/c++ point to a Clang that cannot find libstdc++
  # here, so gcc/g++ must be forced explicitly. ccache makes rebuilds fast.
  CC=gcc CXX=g++ \
  USE_CUDA=0 USE_ROCM=0 USE_XPU=0 \
  CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache \
  MAX_JOBS="$(nproc)" BUILD_TEST=0 \
    .venv/bin/python -m pip install --no-build-isolation -e .
else
  echo "   torch already importable -> skipping source build"
fi

echo "== [6/6] Lint tooling (best-effort) =="
# Download the linter binaries once (clang-tidy, actionlint, ...).
if [ ! -d .lintbin ]; then
  .venv/bin/lintrunner init || true
fi
# Work around the FLAKE8 adapter pulling setuptools>=81, which dropped
# pkg_resources and breaks the flake8-logging-format plugin.
FLAKE8_ENV="$(ls -d "$HOME"/.cache/uv/environments-v2/flake8-linter-* 2>/dev/null | head -1 || true)"
if [ -n "${FLAKE8_ENV}" ] && [ -x "${FLAKE8_ENV}/bin/python3" ]; then
  uv pip install --python "${FLAKE8_ENV}/bin/python3" "setuptools<81" >/dev/null 2>&1 || true
fi

.venv/bin/python -c "import torch; print('torch', torch.__version__, '| CUDA available:', torch.cuda.is_available())"
echo "Environment ready."
