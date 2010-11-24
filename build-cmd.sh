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
            packages="$(cygpath -m "$stage/packages")"
            load_vsvars

            patch -p1 < "../000-rename-dbg-zlib-ares.patch"
            cd lib
            nmake /f Makefile.vc8 CFG=debug-ssl-zlib \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/openssl;$packages/libraries/include/ares" \
                LIB="$LIB;$packages/lib/debug"
            nmake /f Makefile.vc8 CFG=release-ssl-zlib \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/openssl;$packages/libraries/include/ares" \
                LIB="$LIB;$packages/lib/release"
            cd ..

            mkdir -p "$stage/lib"/{debug,release}
            cp "lib/debug-ssl-zlib/libcurld.lib" "$stage/lib/debug/libcurld.lib"
            cp "lib/release-ssl-zlib/libcurl.lib" "$stage/lib/release/libcurl.lib"

            mkdir -p "$stage/include"
            cp -a "include/curl/" "$stage/include/"

            legacy_include="libraries/include"
            legacy_lib_base="libraries/i686-win32"
            legacy_lib_debug="libraries/i686-win32/lib/debug"
            legacy_lib_release="libraries/i686-win32/lib/release"
        ;;
        "darwin")
            opts='-arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.4u.sdk'
            CFLAGS="$opts" CXXFLAGS="$opts" ./configure --prefix="$stage"
            make
            make install

            legacy_include="libraries/include"
            legacy_lib_base="libraries/universal-darwin"
            legacy_lib_debug="libraries/universal-darwin/lib_debug"
            legacy_lib_release="libraries/universal-darwin/lib_release"
        ;;
        "linux")
            CFLAGS=-m32 CXXFLAGS=-m32 ./configure --prefix="$stage"
            make
            make install

            legacy_include="libraries/include"
            legacy_lib_base="libraries/i686-linux"
            legacy_lib_debug="libraries/i686-linux/lib_debug"
            legacy_lib_release="libraries/i686-linux/lib_release_client"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/curl.txt"
popd

# *TODO - add a way to enable/disable this via BuildParams or something
if true ; then
    mkdir -p "$stage/$legacy_lib_base"

    mv "$stage/include" "$stage/$legacy_include"

    if [ -d "$stage/lib/debug" ] ; then
        mv "$stage/lib/debug" "$stage/$legacy_lib_debug"
    fi

    if [ -d "$stage/lib/release" ] ; then
        mv "$stage/lib/release" "$stage/$legacy_lib_release"
    else
        mkdir -p "$stage/$legacy_lib_release"
    fi

    mv "$stage/lib/"* "$stage/$legacy_lib_release"
fi

pass

