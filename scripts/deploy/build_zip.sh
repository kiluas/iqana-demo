#!/usr/bin/env bash
set -euo pipefail

# ── Config via env (with sensible defaults) ───────────────────────────────────
ZIP_PATH="${ZIP_PATH:-bundle.zip}"              # final zip name
APP_DIR="${APP_DIR:-iqana_demo}"                # your package dir (root module)
REQ_FILE="${REQ_FILE:-requirements.deploy.txt}" # minimal runtime deps
BUILD_DIR="${BUILD_DIR:-.lambda-build}"         # staging dir
INCLUDE_BOTO3="${INCLUDE_BOTO3:-1}"             # 0 to exclude boto3 (use AWS-provided)

EXTRA_DIR="${EXTRA_DIR:-}"                      # optional: copy extra runtime files

# ── Guards ────────────────────────────────────────────────────────────────────
if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv is required. Install from https://docs.astral.sh/uv/ then retry." >&2
  exit 1
fi

if [ ! -d "${APP_DIR}" ]; then
  echo "ERROR: APP_DIR '${APP_DIR}' not found (expected your Python package dir)." >&2
  exit 1
fi

if [ ! -f "${REQ_FILE}" ]; then
  echo "ERROR: ${REQ_FILE} not found. Create it or set REQ_FILE to the right path." >&2
  exit 1
fi

# ── Clean build dir ───────────────────────────────────────────────────────────
rm -rf "${BUILD_DIR}" "${ZIP_PATH}"
mkdir -p "${BUILD_DIR}"

# ── Prepare a trimmed requirements file if excluding boto3 ────────────────────
REQ_USED="${REQ_FILE}"
if [ "${INCLUDE_BOTO3}" != "1" ]; then
  REQ_USED="${BUILD_DIR}/requirements.noboto3.txt"
  grep -Ev '^\s*boto3(\b|==|>=|~=)|^\s*botocore(\b|==|>=|~=)' "${REQ_FILE}" > "${REQ_USED}" || true
fi

# ── Install dependencies into the build dir ───────────────────────────────────
echo "Resolving and installing dependencies with uv into ${BUILD_DIR} ..."
uv pip install --no-cache --no-python-downloads \
  --target "${BUILD_DIR}" \
  -r "${REQ_USED}"

# ── Copy your application code into the build dir (ZIP root) ─────────────────
rsync -a --delete \
  --exclude '__pycache__' --exclude '*.pyc' \
  "${APP_DIR}/" "${BUILD_DIR}/${APP_DIR}/"

# Optional extras (config/templates/etc.)
if [ -n "${EXTRA_DIR}" ] && [ -d "${EXTRA_DIR}" ]; then
  rsync -a "${EXTRA_DIR}/" "${BUILD_DIR}/"
fi

# ── Trim caches ───────────────────────────────────────────────────────────────
find "${BUILD_DIR}" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "${BUILD_DIR}" -type f -name "*.pyc" -delete

# ── Zip it ────────────────────────────────────────────────────────────────────
(
  cd "${BUILD_DIR}"
  zip -qr "../${ZIP_PATH}" .
)
echo "Built ${ZIP_PATH}"

# ── Sanity check the handler is present ───────────────────────────────────────
unzip -l "${ZIP_PATH}" | grep -E 'iqana_demo/api/lambda_handler\.py' >/dev/null || {
  echo "ERROR: handler file iqana_demo/api/lambda_handler.py not found in ${ZIP_PATH}" >&2
  exit 2
}
