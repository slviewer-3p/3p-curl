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

CURL_VERSION=7.24.0
CURL_SOURCE_DIR="curl"

# load autbuild provided shell functions and variables
eval "$("$AUTOBUILD" source_environment)"

top="$(pwd)"
stage="$(pwd)/stage"

# See if there's anything wrong with the checked out or
# generated files.  Main test is to confirm that c-ares
# is defeated and we're using a threaded resolver.
check_damage ()
{
    case "$1" in
        "windows")
            echo "Verifying Ares is disabled"
            grep 'USE_ARES\s*1' lib/config-win32.h | grep '^/\*'
            grep 'USE_ARES\s*1' src/config-win32.h | grep '^/\*'
        ;;

        "darwin")
            echo "Verifying Ares is disabled"
            egrep 'USE_THREADS_POSIX[[:space:]]+1' lib/curl_config.h
            egrep 'USE_THREADS_POSIX[[:space:]]+1' src/curl_config.h
        ;;

        "linux")
            echo "Verifying Ares is disabled"
            egrep 'USE_THREADS_POSIX[[:space:]]+1' lib/curl_config.h
            egrep 'USE_THREADS_POSIX[[:space:]]+1' src/curl_config.h
        ;;
    esac
}

pushd "$CURL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            check_damage "$AUTOBUILD_PLATFORM"
            packages="$(cygpath -m "$stage/packages")"
            load_vsvars
            pushd lib
            nmake /f Makefile.vc10 CFG=debug-ssl-zlib \
                OPENSSL_PATH="$packages/include/openssl" \
                ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlibd.lib" \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                LIB="$LIB;$packages/lib/debug" \
                LINDEN_LIBPATH="$packages/lib/debug"
            nmake /f Makefile.vc10 CFG=release-ssl-zlib \
                OPENSSL_PATH="$packages/include/openssl" \
                ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlib.lib" \
                INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                LIB="$LIB;$packages/lib/release" \
                LINDEN_LIBPATH="$packages/lib/release" 
            popd

            mkdir -p "$stage/lib"/{debug,release}
            cp "lib/debug-ssl-zlib/libcurld.lib" "$stage/lib/debug/libcurld.lib"
            cp "lib/release-ssl-zlib/libcurl.lib" "$stage/lib/release/libcurl.lib"

            mkdir -p "$stage/include"
            cp -a "include/curl/" "$stage/include/"
        ;;

        "darwin")
            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/lib/debug"
            cp -R "$stage"/packages/include/zlib/*.h "$stage/packages/include/"
            opts='-arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.5.sdk -mmacosx-version-min=10.5'

            # Release configure and build
            CFLAGS="$opts" CXXFLAGS="$opts" LDFLAGS="$opts" ./configure  --disable-ldap --disable-ldaps  \
                --prefix="$stage" --enable-threaded-resolver --with-ssl="$stage/packages" \
                --with-zlib="$stage/packages"
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install
            cp "$stage/lib/libcurl.a" "$stage/lib/release"

            # Debug configure and build
            CFLAGS="$opts" CXXFLAGS="$opts" LDFLAGS="$opts" ./configure  --disable-ldap --disable-ldaps  \
                --prefix="$stage" --enable-threaded-resolver --with-ssl="$stage/packages" \
                --with-zlib="$stage/packages" --enable-debug
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install
            cp "$stage/lib/libcurl.a" "$stage/lib/debug"
        ;;

        "linux")
            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/lib/debug"

            # This moves libraries like libssl.so.1.0.0 and libcrypto.so.1.0.0 into the stage/lib dir to help with the build
            # but not realy sure why this is required.  It seems to be related to a mysterious path referenced by libtool.
            mkdir -p "$stage/lib"
            cp -a "$stage/packages/lib/release"/lib*.so* "$stage/lib"

            # Release configure and build
            cp -a "$stage"/packages/lib/release/{*.a,*.so*} "$stage/packages/lib"
            cp -a "$stage"/packages/include/zlib/*.h "$stage/packages/include"
            CFLAGS=-m32 CXXFLAGS=-m32 ./configure --disable-ldap --disable-ldaps --prefix="$stage" \
                --prefix="$stage" --enable-threaded-resolver --with-ssl="$stage/packages" \
                --with-zlib="$stage/packages"
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install
            cp "$stage/lib/libcurl.a" "$stage/lib/release"

            # Debug configure and build
            cp -a "$stage"/packages/lib/release/{*.a,*.so*} "$stage/packages/lib"
            cp -a "$stage"/packages/include/zlib/*.h "$stage/packages/include"
            CFLAGS=-m32 CXXFLAGS=-m32 ./configure --disable-ldap --disable-ldaps --prefix="$stage" \
                --prefix="$stage" --enable-threaded-resolver --with-ssl="$stage/packages" \
                --with-zlib="$stage/packages" --enable-debug
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install
            cp "$stage/lib/libcurl.a" "$stage/lib/debug"

            # Since we moved some extra stuff to the stage/lib, move curl out, remove everything, then put curl back
            # again not really sure why this whole regamarole is required but this at least cleans it up afterwards.
            mkdir -p "$stage/tmp"
            cp -a "$stage"/lib/libcurl*.so* "$stage/tmp"
            rm -rf "$stage"/lib/lib*.so*
            cp -a "$stage"/tmp/libcurl*.so* "$stage/lib"
            rm -rf "$stage/tmp"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/curl.txt"
popd

pass

