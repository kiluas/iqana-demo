#!/usr/bin/env bash
set -euo pipefail

ZIP_PATH="${ZIP_PATH:-bundle.zip}"
PY_SRC="${PY_SRC:-iqana_demo}"  # your package dir
HANDLER_EXTRA="${HANDLER_EXTRA:-}"  # e.g. "lambda_function.py" if needed
REQ_FILE="${REQ_FILE:-requirements.txt}"

# Clean build dir
rm -rf .lambda-build "${ZIP_PATH}"
mkdir -p .lambda-build

# 1) Install deps into build dir (prefer uv if available; fall back to pip)
if command -v uv >/dev/null 2>&1; then
  echo "Using uv to vendor dependencies..."
  uv pip install --system --target .lambda-build -r "${REQ_FILE}"
else
  echo "Using pip to vendor dependencies..."
  python -m pip install --upgrade pip
  pip install --target .lambda-build -r "${REQ_FILE}"
fi

# 2) Copy your application code
rsync -a --exclude '__pycache__' --exclude '*.pyc' "${PY_SRC}/" ".lambda-build/${PY_SRC}/"

# 3) (Optional) include a top-level handler file if your Lambda entrypoint isn’t inside the package
if [[ -n "${HANDLER_EXTRA}" && -f "${HANDLER_EXTRA}" ]]; then
  cp "${HANDLER_EXTRA}" ".lambda-build/${HANDLER_EXTRA}"
fi

# 4) Zip it up
( cd .lambda-build && zip -qr "../${ZIP_PATH}" . )
echo "Built ${ZIP_PATH}"



