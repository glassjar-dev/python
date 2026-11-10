#!/bin/sh -e
# Packages a finished WASI build into what the engine downloads:
#   dist/python.wasm        the interpreter, without DWARF
#   dist/python-stdlib.tar.gz  usr/local/lib/python315.zip (precompiled .pyc, stored
#                              uncompressed so imports never inflate) plus the os.py and
#                              lib-dynload landmarks getpath uses to find the prefix
cd "$(dirname "$0")"
. ./versions.env
SDK="$(pwd)/${WASI_SDK_DIR}"
MINOR="${CPYTHON_VERSION%.*}"                      # 3.15
TAG="$(echo "${MINOR}" | tr -d .)"                 # 315
BUILD="cpython/cross-build/wasm32-wasip1"
STAGE="$(pwd)/stage"
LIB="${STAGE}/usr/local/lib/python${MINOR}"
rm -rf "${STAGE}" dist && mkdir -p "${LIB}" dist

# Standard library sources, minus what cannot work in a browser sandbox (no processes,
# terminals, GUI or package installs) and the test suite.
rsync -a --exclude '__pycache__' \
  --exclude '/test/' --exclude '/idlelib/' --exclude '/tkinter/' --exclude '/turtledemo/' \
  --exclude '/turtle.py' --exclude '/ensurepip/' --exclude '/venv/' --exclude '/curses/' \
  --exclude '/multiprocessing/' --exclude '/profiling/' \
  cpython/Lib/ "${LIB}/"
# Build-time configuration, with this checkout's path replaced so builds on different
# machines produce the same bytes.
for f in "${BUILD}"/build/lib.wasi-wasm32-"${MINOR}"/_sysconfigdata_*.py "${BUILD}"/build/lib.wasi-wasm32-"${MINOR}"/_sysconfig_vars_*.json; do
  sed "s#$(pwd)#/build#g" "$f" > "${LIB}/$(basename "$f")"
done

# Compile with the interpreter itself, at the paths it runs from, so tracebacks and the
# debugger see /usr/local/lib/python3.15/... for library code.
wasmtime run --env PYTHONDONTWRITEBYTECODE=1 --dir "${STAGE}::/" "${BUILD}/python.wasm" -m compileall -b -q --invalidation-mode unchecked-hash "/usr/local/lib/python${MINOR}" || true
python3 - "${LIB}" "${STAGE}/usr/local/lib/python${TAG}.zip" <<'EOF'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
count = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_STORED) as z:
    for dirpath, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d != '__pycache__')
        for name in sorted(files):
            if name.endswith('.pyc') or (name.endswith('.json') and name.startswith('_sysconfig')):
                path = os.path.join(dirpath, name)
                info = zipfile.ZipInfo(os.path.relpath(path, src), date_time=(2026, 1, 1, 0, 0, 0))
                with open(path, 'rb') as f:
                    z.writestr(info, f.read())
                count += 1
print(f'{count} modules in {os.path.basename(out)}')
EOF
# Keep only the landmarks beside the zip.
find "${LIB}" -mindepth 1 -maxdepth 1 ! -name os.py -exec rm -rf {} +
mkdir -p "${LIB}/lib-dynload" && touch "${LIB}/lib-dynload/.empty"
python3 - "${STAGE}" dist/python-stdlib.tar.gz <<'EOF2'
import gzip, os, sys, tarfile
stage, out = sys.argv[1], sys.argv[2]
def normalize(info):
    info.uid = info.gid = 0
    info.uname = info.gname = ''
    info.mtime = 0
    return info
with open(out, 'wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', compresslevel=9, mtime=0) as gz, \
        tarfile.open(fileobj=gz, mode='w', format=tarfile.USTAR_FORMAT) as tar:
    for dirpath, dirs, files in os.walk(os.path.join(stage, 'usr')):
        dirs.sort()
        rel = os.path.relpath(dirpath, stage)
        tar.add(dirpath, arcname=rel, recursive=False, filter=normalize)
        for name in sorted(files):
            tar.add(os.path.join(dirpath, name), arcname=os.path.join(rel, name), filter=normalize)
EOF2

"${SDK}/bin/llvm-strip" --strip-debug -o dist/python.wasm "${BUILD}/python.wasm"
ls -l dist
shasum -a 256 dist/*
