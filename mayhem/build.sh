#!/usr/bin/env bash
# mayhem/build.sh — build the amphtml C++ validator (validator/cpp: htmlparser + engine) without
# bazel, against apt's abseil/protobuf/re2, and link the fuzz harnesses + upstream's gtest suite.
# Idempotent and offline: everything it needs is in the tree or installed by mayhem/Dockerfile.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

V="$SRC/validator"
B="$SRC/mayhem/build"          # gitignored by mayhem/.gitignore
GEN="$B/gen"
mkdir -p "$GEN" "$B/tools" "$B/fuzz" "$B/test"

ABSL_MODS="absl_flags absl_flags_parse absl_status absl_strings absl_str_format absl_synchronization absl_cord absl_hash absl_raw_hash_set absl_statusor"
LIBS="$(pkg-config --static --libs re2 $ABSL_MODS) $(pkg-config --libs protobuf) -lpthread"
CXXSTD="-std=c++17 -include cstdint -I$V -I$GEN -w $(pkg-config --cflags re2 $ABSL_MODS protobuf)"

# 1) Generated sources: protobuf messages, then the embedded binary rules (validator_pb.h), exactly
#    as validator/BUILD + cpp/engine/BUILD (validator-convert, embed_data) produce them.
gen_if_newer() { # out in... : true when out is missing or older than any input
  local out="$1"; shift
  [ -e "$out" ] || return 0
  for f in "$@"; do [ "$f" -nt "$out" ] && return 0; done
  return 1
}
PROTOS="validator.proto cpp/htmlparser/css/parse-css.proto cpp/htmlparser/css/parse-css-urls.proto"
if gen_if_newer "$GEN/validator.pb.cc" $(cd "$V" && echo $PROTOS | sed "s#[^ ]*#$V/&#g"); then
  (cd "$V" && protoc -I. --cpp_out="$GEN" $PROTOS)
fi

HP_SRCS="$(cd "$V" && ls cpp/htmlparser/*.cc cpp/htmlparser/css/*.cc cpp/htmlparser/json/*.cc | grep -v '_test\.cc$' | grep -v 'parse-css-urls\.cc$')"
# parse-css-urls.cc is left out: it calls LOG_IF, which cpp/htmlparser/glog_polyfill.h does not
# define, so it does not compile upstream either (nothing else in the validator depends on it).
ENGINE_SRCS="cpp/engine/error-formatter.cc cpp/engine/keyframes-parse-css.cc cpp/engine/parse-layout.cc
cpp/engine/parse-layout-sizes.cc cpp/engine/parse-srcset.cc cpp/engine/parse-viewport.cc
cpp/engine/type-identifier.cc cpp/engine/utf8-util.cc cpp/engine/validator-internal.cc"
PB_SRCS="$GEN/validator.pb.cc $GEN/cpp/htmlparser/css/parse-css.pb.cc"

# compile <objdir> <flags> <src...> — parallel, incremental (rebuild when the source or any
# project header is newer than the object).
NEWEST_HDR="$(find "$V/cpp" "$GEN" -name '*.h' -newer "$B/.stamp" 2>/dev/null | head -1 || true)"
[ -e "$B/.stamp" ] || NEWEST_HDR=force
compile() {
  local od="$1" flags="$2" force="$NEWEST_HDR"; shift 2
  # Flag changes (e.g. --build-arg SANITIZER_FLAGS=...) invalidate every object in the dir.
  if [ "$(cat "$od/.flags" 2>/dev/null)" != "$CXX $CXXSTD $flags" ]; then force=flags; fi
  for s in "$@"; do
    case "$s" in /*) p="$s";; *) p="$V/$s";; esac
    o="$od/$(echo "${p#$SRC/}" | tr '/' '_').o"
    if [ -n "$force" ] || [ ! -e "$o" ] || [ "$p" -nt "$o" ]; then echo "$p $o"; fi
  done | xargs -r -P"$MAYHEM_JOBS" -n2 sh -c "$CXX $CXXSTD $flags -c \"\$0\" -o \"\$1\""
  echo "$CXX $CXXSTD $flags" > "$od/.flags"
}
objs() { ls "$1"/*.o; }

# Tools (plain flags): validator-convert (protoascii -> binary pb), embed header generator.
compile "$B/tools" "-O1" $HP_SRCS $PB_SRCS cpp/engine/validator-convert.cc
"$CXX" -O1 "$B"/tools/*.o -o "$B/tools/validator-convert" $LIBS
"$CXX" $CXXSTD -O1 "$V/cpp/engine/scripts/filecontents_to_cpp_header.cc" -o "$B/tools/embed" $LIBS
# validator.protoascii = main + css + svg + every extensions/*/validator-*.protoascii (bazel glob order).
EXT="$(ls "$SRC"/extensions/*/validator-*.protoascii | LC_ALL=C sort)"
if gen_if_newer "$GEN/cpp/engine/validator_pb.h" "$V"/validator-{main,css,svg}.protoascii $EXT; then
  cat "$V/validator-main.protoascii" "$V/validator-css.protoascii" "$V/validator-svg.protoascii" $EXT > "$B/validator.protoascii"
  "$B/tools/validator-convert" "$B/validator.protoascii" "$B/validator.pb"
  mkdir -p "$GEN/cpp/engine"
  "$B/tools/embed" "$B/validator.pb" "$GEN/cpp/engine/validator_pb.h" amp::validator::data kValidatorProtoBytes
fi
NEWEST_HDR="$(find "$V/cpp" "$GEN" -name '*.h' -newer "$B/.stamp" 2>/dev/null | head -1 || true)"
[ -e "$B/.stamp" ] || NEWEST_HDR=force

# 2) Sanitized, instrumented project + harnesses.
# abseil changes its swisstable layout under ASan (ABSL_SWISSTABLE_ENABLE_GENERATIONS), so the
# fuzz build links an abseil + re2 compiled with the same $SANITIZER_FLAGS (no coverage: they are
# not fuzzed themselves) from the pinned sources in /opt/toolchains/deps, out of tree under $B.
ABSL_SRC="$(ls -d /opt/toolchains/deps/abseil-*/src)"; RE2_SRC="$(ls -d /opt/toolchains/deps/re2-*/src)"
DP="$B/deps/prefix"
DEP_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1"
cmake -S "$ABSL_SRC" -B "$B/deps/absl" -G Ninja -DCMAKE_BUILD_TYPE=None -DCMAKE_CXX_STANDARD=17 \
  -DBUILD_SHARED_LIBS=OFF -DABSL_PROPAGATE_CXX_STD=ON -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX="$DP" \
  -DCMAKE_CXX_FLAGS="$DEP_FLAGS" -DCMAKE_C_FLAGS="$DEP_FLAGS" >/dev/null
cmake --build "$B/deps/absl" -j"$MAYHEM_JOBS" >/dev/null && cmake --install "$B/deps/absl" >/dev/null
cmake -S "$RE2_SRC" -B "$B/deps/re2" -G Ninja -DCMAKE_BUILD_TYPE=None -DCMAKE_CXX_STANDARD=17 \
  -DBUILD_SHARED_LIBS=OFF -DRE2_BUILD_TESTING=OFF -DCMAKE_PREFIX_PATH="$DP" -DCMAKE_INSTALL_PREFIX="$DP" \
  -DCMAKE_CXX_FLAGS="$DEP_FLAGS" >/dev/null
cmake --build "$B/deps/re2" -j"$MAYHEM_JOBS" >/dev/null && cmake --install "$B/deps/re2" >/dev/null
PLAIN_PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"
export PKG_CONFIG_PATH="$DP/lib/pkgconfig"
CXXSTD="-std=c++17 -include cstdint -I$V -I$GEN -w $(pkg-config --cflags re2 $ABSL_MODS) $(PKG_CONFIG_PATH=$PLAIN_PKG_CONFIG_PATH pkg-config --cflags protobuf)"
LIBS="$(pkg-config --static --libs re2 $ABSL_MODS) $(PKG_CONFIG_PATH=$PLAIN_PKG_CONFIG_PATH pkg-config --libs protobuf) -lpthread"
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link"
mkdir -p "$B/fuzz/lib" "$B/fuzz/h"
compile "$B/fuzz/lib" "$FUZZ_FLAGS" $HP_SRCS $ENGINE_SRCS $PB_SRCS
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/fuzz/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/fuzz/lsan_off.o"
HARNESSES="$(cd "$SRC/mayhem/harnesses" && ls *.cc | sed 's/\.cc$//')"
compile "$B/fuzz/h" "$FUZZ_FLAGS" $(for h in $HARNESSES; do echo "$SRC/mayhem/harnesses/$h.cc"; done)
LIBOBJS="$(objs "$B/fuzz/lib")"
for h in $HARNESSES; do
  ho="$B/fuzz/h/mayhem_harnesses_$h.cc.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$ho" $LIBOBJS "$B/fuzz/lsan_off.o" -o "$SRC/$h" $LIBS &
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$ho" "$B/fuzz/standalone_main.o" $LIBOBJS "$B/fuzz/lsan_off.o" -o "$SRC/$h-standalone" $LIBS
  wait $!
done

# 3) Upstream's own gtest suite, normal flags (the test.sh oracle), against the plain deps.
export PKG_CONFIG_PATH="$PLAIN_PKG_CONFIG_PATH"
# -include iterator: casetable.h calls std::begin/std::end on C arrays without including
# <iterator>; strings.cc gets it transitively, casetable_test.cc (which includes it first) does not.
CXXSTD="-std=c++17 -include cstdint -include iterator -I$V -I$GEN -w $(pkg-config --cflags re2 $ABSL_MODS protobuf)"
LIBS="$(pkg-config --static --libs re2 $ABSL_MODS) $(pkg-config --libs protobuf) -lpthread"
# Every validator/cpp/**/*_test.cc except css/parse-css-urls_test (its library does not compile,
# see HP_SRCS above). validators/{ipaddress,supported_media_query}_test have no BUILD rule upstream
# but test the checked-in generated grammar validators, so they run too.
TESTS="cpp/htmlparser/tokenizer_test cpp/htmlparser/parser_test cpp/htmlparser/strings_test
cpp/htmlparser/renderer_test cpp/htmlparser/url_test cpp/htmlparser/allocator_test
cpp/htmlparser/atomutil_test cpp/htmlparser/casetable_test cpp/htmlparser/doctype_test
cpp/htmlparser/entity_test cpp/htmlparser/fileutil_test cpp/htmlparser/htmldataset_test
cpp/htmlparser/node_test cpp/htmlparser/utf8_test
cpp/htmlparser/json/json_test cpp/htmlparser/json/types_test
cpp/htmlparser/css/parse-css_test cpp/htmlparser/css/amp4ads-parse-css_test
cpp/htmlparser/validators/json_test cpp/htmlparser/validators/ipaddress_test
cpp/htmlparser/validators/supported_media_query_test
cpp/engine/parse-srcset_test cpp/engine/parse-layout_test cpp/engine/parse-viewport_test
cpp/engine/utf8-util_test cpp/engine/parse-layout-sizes_test cpp/engine/error-formatter_test
cpp/engine/keyframes-parse-css_test cpp/engine/type-identifier_test cpp/engine/validator_test"
mkdir -p "$B/test/lib" "$B/test/t" "$B/test/bin"
compile "$B/test/lib" "-O1 $COVERAGE_FLAGS" $HP_SRCS $ENGINE_SRCS $PB_SRCS cpp/engine/testing-utils.cc
compile "$B/test/t" "-O1 $COVERAGE_FLAGS" $(for t in $TESTS; do echo "$t.cc"; done)
TLIB="$(objs "$B/test/lib")"
for t in $TESTS; do
  n="$(basename "$t")"
  # validators/json_test would collide with json/json_test: prefix the validators/ suites.
  case "$t" in */validators/*) n="validators_$n";; esac
  $CXX -O1 $COVERAGE_FLAGS "$B/test/t/validator_${t//\//_}.cc.o" $TLIB -o "$B/test/bin/$n" \
    $(pkg-config --libs gtest_main gmock) $LIBS &
  pids="${pids:-} $!"
done
for p in $pids; do wait "$p"; done
touch "$B/.stamp"
echo "build.sh: done"
