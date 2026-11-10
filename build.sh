#!/bin/sh -e
# Builds glassjar's CPython for wasm32-wasip1 end to end: WASI SDK, the C libraries for the
# optional modules, CPython itself (Platforms/WASI), then dist/ for the engine.
cd "$(dirname "$0")"
. ./versions.env
if [ ! -d "${WASI_SDK_DIR}" ]; then
  curl -sSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/${WASI_SDK_DIR}.tar.gz" -o wasi-sdk.tar.gz
  echo "${WASI_SDK_SHA256}  wasi-sdk.tar.gz" | shasum -a 256 -c -
  tar xzf wasi-sdk.tar.gz && rm wasi-sdk.tar.gz
fi
[ -d cpython ] || git clone -q --depth 1 --branch "v${CPYTHON_VERSION}" https://github.com/python/cpython.git cpython
./build-deps.sh
SDK="$(pwd)/${WASI_SDK_DIR}"
(cd cpython \
  && python3 Platforms/WASI build-python --quiet \
  && python3 Platforms/WASI configure-host --quiet --wasi-sdk "${SDK}" -- --prefix=/usr/local --without-system-libmpdec \
  && python3 Platforms/WASI make-host --quiet)
./package.sh
