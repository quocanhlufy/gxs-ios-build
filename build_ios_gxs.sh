#!/bin/bash
# GxS (Girl x Senpai): libtolua.a for iOS (arm64, iOS 13+), built on macOS with Xcode (Codemagic does it: codemagic.yaml).
# Same sources and choices as the Windows / Android builds (tolua_runtime build_win64_gxs.sh, build_android_gxs.sh):
# LuaJIT 2.1 with GC64, tolua + pb + lpeg + struct + cjson + luasocket, and lsqlite3 0.9.6 + SQLite 3.54.0 linked in
# (require("sqlite3"), exported as luaopen_lsqlite3). iOS forbids writable+executable memory: LuaJIT's JIT is off,
# the interpreter runs everything.
#   bash build_ios_gxs.sh        -> out/libtolua.a
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
MIN=13.0
FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN"
OLD="-Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-implicit-int -Wno-deprecated-non-prototype"
SQL="$ROOT/sqlite/sqlite-amalgamation-3540000"
OBJ="$ROOT/out/obj"
rm -rf out && mkdir -p "$OBJ"

# LuaJIT: host tools (minilua, buildvm) with the Mac's own clang, the library for the iPhone
(cd tolua/luajit-2.1 && make clean >/dev/null && make -j4 BUILDMODE=static HOST_CC="clang" \
  CROSS="" STATIC_CC="$CC $FLAGS" DYNAMIC_CC="$CC $FLAGS -fPIC" TARGET_LD="$CC $FLAGS" \
  TARGET_AR="$(xcrun --sdk iphoneos -f ar) rcus" TARGET_STRIP="$(xcrun --sdk iphoneos -f strip)" \
  TARGET_FLAGS="$FLAGS" TARGET_SYS=iOS XCFLAGS="-DLUAJIT_ENABLE_GC64 -DLUAJIT_DISABLE_JIT" amalg)
cp tolua/luajit-2.1/src/libluajit.a out/libluajit.a
(cd tolua/luajit-2.1 && make clean >/dev/null)

# SQLite is C99 and large: compiled on its own
"$CC" $FLAGS -O2 -c "$SQL/sqlite3.c" -o "$OBJ/sqlite3.o" -DSQLITE_THREADSAFE=1
cd tolua
for f in tolua.c int64.c uint64.c pb.c lpeg.c struct.c \
  cjson/strbuf.c cjson/lua_cjson.c cjson/fpconv.c \
  luasocket/auxiliar.c luasocket/buffer.c luasocket/except.c luasocket/inet.c luasocket/io.c luasocket/luasocket.c \
  luasocket/mime.c luasocket/options.c luasocket/select.c luasocket/tcp.c luasocket/timeout.c luasocket/udp.c luasocket/usocket.c \
  ../sqlite/lsqlite3/lsqlite3.c; do
  "$CC" $FLAGS -O2 -std=gnu99 $OLD -I. -Iluajit-2.1/src -Iluasocket -I"$SQL" -c "$f" -o "$OBJ/$(basename "${f%.c}").o"
done
cd "$ROOT"
# one static library: tolua's objects + LuaJIT's
libtool -static -o out/libtolua.a "$OBJ"/*.o out/libluajit.a
xcrun --sdk iphoneos lipo -info out/libtolua.a
nm -gU out/libtolua.a 2>/dev/null | grep -E " _(luaopen_lsqlite3|luaL_newstate|tolua_openlibs)$" || true
echo "built out/libtolua.a"
