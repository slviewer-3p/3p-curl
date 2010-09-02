#!/bin/bash

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

CURL_VERSION=7.21.1
CURL_SOURCE_DIR="curl-$CURL_VERSION"
CURL_ARCHIVE="curl-$CURL_VERSION.tar.gz"

# load autbuild provided shell functions and variables
eval "$("$AUTOBUILD" source_environment)"

extract "$CURL_ARCHIVE"

top="$(pwd)"
stage="$(pwd)/stage"

pushd "$CURL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            packages="$(cygpath -m "$top/build-vc90/packages")"
            load_vsvars

            patch -p1 < "../000-rename-dbg-zlib.patch"
            cd lib
            nmake /f Makefile.vc8 CFG=debug-ssl-zlib \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/openssl" \
                LIB="$LIB;$packages/lib/debug"
            nmake /f Makefile.vc8 CFG=release-ssl-zlib \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/openssl" \
                LIB="$LIB;$packages/lib/release"
            cd ..

            mkdir -p "$stage/lib"/{debug,release}
            cp "lib/debug-ssl-zlib/libcurld.lib" "$stage/lib/debug/libcurld.lib"
            cp "lib/release-ssl-zlib/libcurl.lib" "$stage/lib/release/libcurl.lib"

            mkdir -p "$stage/include"
            cp -a "include/curl/" "$stage/include/"
        ;;
        *)
            ./configure --prefix="$stage"
            make
            make install
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/curl.txt"
popd

pass

