#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-public.ecr.aws/sam/build-python3.12:latest}"
ARCH="${ARCH:-x86_64}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"

ZIP_PATH="${ZIP_PATH:-bundle.zip}"
APP_DIR="${APP_DIR:-iqana_demo}"
REQ_FILE="${REQ_FILE:-requirements.deploy.txt}"
BUILD_DIR="${BUILD_DIR:-.lambda-build}"

rm -rf "${BUILD_DIR}" "${ZIP_PATH}"

docker run --rm --platform "${DOCKER_PLATFORM}" \
  -v "$PWD":/var/task -w /var/task \
  "${IMAGE}" bash -eu -o pipefail -c "
    python3 -m venv .venv-build
    . .venv-build/bin/activate
    python -m pip install --upgrade pip
    pip install --target ${BUILD_DIR} -r ${REQ_FILE}
    pip install --target ${BUILD_DIR} .
    # === NEW: copy your source tree explicitly so handler file is definitely present ===
    cp -R ${APP_DIR} ${BUILD_DIR}/
    # trim cruft
    find ${BUILD_DIR} -type d -name __pycache__ -prune -exec rm -rf {} +
    find ${BUILD_DIR} -type f -name '*.pyc' -delete
    (cd ${BUILD_DIR} && zip -qr ../${ZIP_PATH} .)
  "

# sanity: ensure handler is in the zip
unzip -l "${ZIP_PATH}" | grep -E 'iqana_demo/api/lambda_handler\.py' >/dev/null || {
  echo 'ERROR: handler iqana_demo/api/lambda_handler.py not found in zip' >&2; exit 2; }

echo "Built ${ZIP_PATH} for ${ARCH}"
