#!/bin/bash

cd "$(dirname "$0")"

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

# load autbuild provided shell functions and variables
eval "$("$AUTOBUILD" source_environment)"

top="$(pwd)"
stage="$(pwd)/stage"

pushd "$CURL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            packages="$(cygpath -m "$stage/packages")"
            load_vsvars

            pushd lib
            nmake /f Makefile.vc10 CFG=debug-ssl-zlib \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl;$packages/include/ares" \
                LIB="$LIB;$packages/lib/debug"
            nmake /f Makefile.vc10 CFG=release-ssl-zlib \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl;$packages/include/ares" \
                LIB="$LIB;$packages/lib/release"
            popd

            mkdir -p "$stage/lib"/{debug,release}
            cp "lib/debug-ssl-zlib/libcurld.lib" "$stage/lib/debug/libcurld.lib"
            cp "lib/release-ssl-zlib/libcurl.lib" "$stage/lib/release/libcurl.lib"

            mkdir -p "$stage/include"
            cp -a "include/curl/" "$stage/include/"
        ;;
        "darwin")
            cp -R "$stage/packages/lib/release/" "$stage/packages/lib/"
            cp -R "$stage/packages/include/ares/" "$stage/packages/include/"
            opts='-arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.5.sdk'
            CFLAGS="$opts" CXXFLAGS="$opts" ./configure  --disable-ldap --disable-ldaps  \
                --prefix="$stage" --enable-ares="$stage/packages" --with-ssl="$stage/packages" \
                --with-zlib="$stage/packages"
            make
            make install
            mkdir -p "$stage/lib/release"
            cp "$stage/lib/libcurl.a" "$stage/lib/release"
        ;;
        "linux")
            CFLAGS=-m32 CXXFLAGS=-m32 ./configure --disable-ldap --disable-ldaps --with-ssl --prefix="$stage"
            make
            make install
            mkdir -p "$stage/lib/release"
            cp "$stage/lib/libcurl.a" "$stage/lib/release"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/curl.txt"
popd

pass

