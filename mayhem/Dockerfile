# syntax=docker/dockerfile:1.7
# Commit image for amphtml's C++ validator (validator/cpp). Upstream builds it with bazel, which
# fetches abseil and re2 at pinned commits (validator/WORKSPACE); those two are built here, once,
# from the same pinned archives into /opt/toolchains/deps, so mayhem/build.sh runs offline.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

USER root
# protobuf 3.21 (no abseil dependency) and gtest/gmock come from apt.
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
      libprotobuf-dev protobuf-compiler libgtest-dev libgmock-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*

# abseil + re2 at validator/WORKSPACE's pinned commits and sha256s, static, C++17 (so
# absl::string_view is std::string_view, as the bazel build has it), DWARF 3, uninstrumented.
ARG ABSL_REV=fc44fa053cc91193d2bb60fb9356bcecb301242e
ARG ABSL_SHA256=050071396c0483035c9545daaaf953a47449b971978631db040cd31bcb2d3dde
ARG RE2_REV=87d09ef4f0307e53f1d3796843f4b90d41cfccaa
ARG RE2_SHA256=e9e9cd5902c711131825f7dd45dfdb063555171d8d26300b336aace5f97215ef
RUN set -eux; unset SOURCE_DATE_EPOCH || true; \
    A=/opt/toolchains/deps/abseil-${ABSL_REV}; R=/opt/toolchains/deps/re2-${RE2_REV}; \
    mkdir -p "$A/src" "$R/src" /tmp/dep; cd /tmp/dep; \
    curl -fsSL -o absl.zip https://github.com/abseil/abseil-cpp/archive/${ABSL_REV}.zip; \
    echo "${ABSL_SHA256}  absl.zip" | sha256sum -c -; \
    curl -fsSL -o re2.zip https://github.com/google/re2/archive/${RE2_REV}.zip; \
    echo "${RE2_SHA256}  re2.zip" | sha256sum -c -; \
    unzip -q absl.zip && cp -a abseil-cpp-${ABSL_REV}/. "$A/src/"; \
    unzip -q re2.zip && cp -a re2-${RE2_REV}/. "$R/src/"; \
    cmake -S "$A/src" -B /tmp/dep/absl-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_CXX_STANDARD=17 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF \
      -DABSL_PROPAGATE_CXX_STD=ON -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX="$A" \
      -DCMAKE_CXX_FLAGS="-g -gdwarf-3" -DCMAKE_C_FLAGS="-g -gdwarf-3"; \
    cmake --build /tmp/dep/absl-build -j"$(nproc)"; cmake --install /tmp/dep/absl-build; \
    cmake -S "$R/src" -B /tmp/dep/re2-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_CXX_STANDARD=17 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF \
      -DRE2_BUILD_TESTING=OFF -DCMAKE_PREFIX_PATH="$A" -DCMAKE_INSTALL_PREFIX="$R" \
      -DCMAKE_CXX_FLAGS="-g -gdwarf-3"; \
    cmake --build /tmp/dep/re2-build -j"$(nproc)"; cmake --install /tmp/dep/re2-build; \
    cd /; rm -rf /tmp/dep; chmod -R a+rX /opt/toolchains/deps
ENV PKG_CONFIG_PATH=/opt/toolchains/deps/re2-87d09ef4f0307e53f1d3796843f4b90d41cfccaa/lib/pkgconfig:/opt/toolchains/deps/abseil-fc44fa053cc91193d2bb60fb9356bcecb301242e/lib/pkgconfig

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
