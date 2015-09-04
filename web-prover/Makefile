.PHONY: all distrib src_distrib levels

BUILD_DIR=build


all: cabal.sandbox.config
	cabal install -j --disable-library-profiling

cabal.sandbox.config:
	mkdir -p $(BUILD_DIR)
	cabal sandbox --sandbox=$(BUILD_DIR) init
	if [ -e ../why3 ];                       \
          then cabal sandbox add-source ../why3; \
          else cabal sandbox add-source why3;    \
        fi

# This is useful for copying to execution environment
distrib: all
	scripts/package storm-proto \
            build/bin \
            wp_lib \
            web_src \
            scripts

# This is useful for building on another machine
src-distrib:
	scripts/package storm-proto-src \
            LICENSE* \
            Makefile \
            Storm2.cabal \
            scripts \
            exes \
            src \
            stats \
            web_src \
            wp_alloc \
            wp_lib \
            ../why3


levels:
	tar czvf levels.tar.gz levels

