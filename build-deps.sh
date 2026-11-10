#!/bin/sh -e
# Builds the C libraries CPython's optional modules need (zlib, bz2, lzma, sqlite3) for
# wasm32-wasip1 and installs them into the WASI SDK's sysroot with pkg-config files, which
# is where CPython's WASI build looks for them (Platforms/WASI/_build.py).
cd "$(dirname "$0")"
. ./versions.env
SDK="$(pwd)/${WASI_SDK_DIR}"
SYSROOT="${SDK}/share/wasi-sysroot"
CC="${SDK}/bin/clang --target=wasm32-wasip1 --sysroot=${SYSROOT}"
AR="${SDK}/bin/llvm-ar"
RANLIB="${SDK}/bin/llvm-ranlib"
CFLAGS="-O2 -fPIC"
PKGDIR="${SYSROOT}/lib/pkgconfig"
mkdir -p deps "${PKGDIR}" "${SYSROOT}/include" "${SYSROOT}/lib"

fetch() { # url sha256 file
  [ -f "deps/$3" ] || curl -sSL "$1" -o "deps/$3"
  echo "$2  deps/$3" | shasum -a 256 -c -
}

pc() { # name version libs [private libs]
  cat > "${PKGDIR}/$1.pc" <<EOF
prefix=${SYSROOT}
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: $1
Description: $1 for wasm32-wasip1
Version: $2
Libs: -L\${libdir} $3
Libs.private: $4
Cflags: -I\${includedir}
EOF
}

# zlib
fetch "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" "${ZLIB_SHA256}" zlib.tar.gz
rm -rf deps/zlib && mkdir deps/zlib && tar xzf deps/zlib.tar.gz -C deps/zlib --strip-components=1
(cd deps/zlib && for f in adler32 crc32 deflate infback inffast inflate inftrees trees zutil compress uncompr gzclose gzlib gzread gzwrite; do
  ${CC} ${CFLAGS} -DHAVE_UNISTD_H -DZ_HAVE_UNISTD_H -c "$f.c" -o "$f.o"; done && ${AR} rcs libz.a *.o)
cp deps/zlib/libz.a "${SYSROOT}/lib/" && cp deps/zlib/zlib.h deps/zlib/zconf.h "${SYSROOT}/include/"
pc zlib "${ZLIB_VERSION}" "-lz"

# bzip2
fetch "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz" "${BZIP2_SHA256}" bzip2.tar.gz
rm -rf deps/bzip2 && mkdir deps/bzip2 && tar xzf deps/bzip2.tar.gz -C deps/bzip2 --strip-components=1
(cd deps/bzip2 && for f in blocksort huffman crctable randtable compress decompress bzlib; do
  ${CC} ${CFLAGS} -D_FILE_OFFSET_BITS=64 -c "$f.c" -o "$f.o"; done && ${AR} rcs libbz2.a *.o)
cp deps/bzip2/libbz2.a "${SYSROOT}/lib/" && cp deps/bzip2/bzlib.h "${SYSROOT}/include/"
pc bzip2 "${BZIP2_VERSION}" "-lbz2"

# xz (liblzma only)
fetch "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.gz" "${XZ_SHA256}" xz.tar.gz
rm -rf deps/xz && mkdir deps/xz && tar xzf deps/xz.tar.gz -C deps/xz --strip-components=1
(cd deps/xz && CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" CFLAGS="${CFLAGS}" ./configure --host=wasm32-wasi --prefix=/ \
    --disable-shared --enable-static --disable-threads --disable-xz --disable-xzdec --disable-lzmadec \
    --disable-lzmainfo --disable-lzma-links --disable-scripts --disable-doc --disable-nls >/dev/null \
  && make -C src/liblzma -j8 >/dev/null && make -C src/liblzma install DESTDIR="$(pwd)/out" >/dev/null)
cp deps/xz/out/lib/liblzma.a "${SYSROOT}/lib/" && cp -R deps/xz/out/include/lzma.h deps/xz/out/include/lzma "${SYSROOT}/include/"
pc liblzma "${XZ_VERSION}" "-llzma"

# SQLite (amalgamation). No threads, mmap, WAL shared memory or loadable extensions on WASI.
fetch "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-autoconf-${SQLITE_VERSION}.tar.gz" "${SQLITE_SHA256}" sqlite.tar.gz
rm -rf deps/sqlite && mkdir deps/sqlite && tar xzf deps/sqlite.tar.gz -C deps/sqlite --strip-components=1
(cd deps/sqlite && ${CC} ${CFLAGS} -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_WAL \
    -DSQLITE_MAX_MMAP_SIZE=0 -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_DEFAULT_LOCKING_MODE=1 -D_WASI_EMULATED_GETPID \
    -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_MATH_FUNCTIONS -c sqlite3.c -o sqlite3.o && ${AR} rcs libsqlite3.a sqlite3.o)
cp deps/sqlite/libsqlite3.a "${SYSROOT}/lib/" && cp deps/sqlite/sqlite3.h deps/sqlite/sqlite3ext.h "${SYSROOT}/include/"
pc sqlite3 "${SQLITE_VERSION}" "-lsqlite3" "-lwasi-emulated-getpid"

echo "deps installed into ${SYSROOT}"
