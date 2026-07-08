- This is the only AGENTS.md, there are no recursive AGENTS.md
- When you are working on a bug, first create a standalone file that
  reproduces the bug and verify it fails in the expected way.  Use this to
  test if your changes work.  Once the change is passing, find an appropriate
  test file to add the test to and make sure to follow local conventions on
  the test file.
- If you are running the real test suite, DO NOT run the entire test suite.
  Instead run only a single test case, e.g., 'python test/test_torch.py TestTorch.test_dir'
- Do NOT run setup.py, you do not have a working build environment
- Do NOT run pre-commit, it is not setup
- To run lint, run 'lintrunner -a' (which will autoapply changes)
- Do NOT attempt to install dependencies, you do not have Internet access
- Do NOT create summary files unless explicitly asked
- When you are ready to make a PR, do exactly these steps:
  - git stash -u
  - git reset --hard $(cat /tmp/orig_work.txt) # NB: reset to the LOCAL branch, do NOT fetch
  - git stash pop
  - Resolve conflicts if necessary

## Cursor Cloud specific instructions

The bullets above describe a different (prebuilt, offline) agent image. The Cursor
Cloud environment is different, and the notes below take precedence for it:

- This environment HAS internet access and PyTorch is built **from source** into a
  Python virtualenv at `/workspace/.venv` (CPU-only: `USE_CUDA=0`). Activate it with
  `source /workspace/.venv/bin/activate` (or call `/workspace/.venv/bin/python`
  directly). The build + venv are captured in the VM snapshot, so `import torch`
  works on startup without rebuilding. The startup update script only refreshes the
  Python deps in `requirements.txt`; it does NOT rebuild the C++ extension.
- Editable install: pure-Python changes under `torch/` are picked up immediately (no
  rebuild). Only changes to C++/CUDA sources (`aten/`, `c10/`, `torch/csrc/`, etc.)
  require recompiling. To rebuild after C++ changes, run (from `/workspace`, venv
  active): `CC=gcc CXX=g++ USE_CUDA=0 CMAKE_C_COMPILER_LAUNCHER=ccache
  CMAKE_CXX_COMPILER_LAUNCHER=ccache MAX_JOBS=8 BUILD_TEST=0 pip install
  --no-build-isolation -e .`. `ccache` is installed, so incremental rebuilds are
  fast. A clean full build takes a long time.
- Gotcha: the system default `cc`/`c++` (`/etc/alternatives`) point to **Clang**,
  whose libstdc++/headers are broken here. Always force `CC=gcc CXX=g++` for any
  native build or the CMake compiler check fails with `cannot find -lstdc++`.
- Lint: `lintrunner` is installed and initialized (linters cached under `.lintbin/`).
  Run `lintrunner -a` (autofix) or target one linter, e.g.
  `lintrunner --take RUFF <file>`. Known caveat: the `FLAKE8` adapter's unpinned
  `setuptools` resolves to a version that dropped `pkg_resources`, breaking the
  `flake8-logging-format` plugin. It is fixed here by downgrading setuptools inside
  the adapter's cached uv env. If FLAKE8 ever fails again with
  `No module named 'pkg_resources'`, re-apply:
  `uv pip install --python "$(ls -d ~/.cache/uv/environments-v2/flake8-linter-*|head -1)/bin/python3" "setuptools<81"`.
- Tests: run a single test case (never the whole suite), e.g.
  `python test/test_torch.py TestTorch.test_dir`. `expecttest` and `hypothesis` are
  installed.
