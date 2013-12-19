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

CURL_VERSION=7.34.0
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
        ;;

        "darwin")
            echo "Verifying Ares is disabled"
            egrep 'USE_THREADS_POSIX[[:space:]]+1' lib/curl_config.h
        ;;

        "linux")
            echo "Verifying Ares is disabled"
            egrep 'USE_THREADS_POSIX[[:space:]]+1' lib/curl_config.h
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

                # Debug target.  DLL for SSL, static archives
                # for libcurl and zlib.  (Config created by Linden Lab)
                nmake /f Makefile.vc10 CFG=debug-ssl-dll-zlib \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlibd.lib" \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/debug" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/debug"

                # Release target.  DLL for SSL, static archives
                # for libcurl and zlib.  (Config created by Linden Lab)
                nmake /f Makefile.vc10 CFG=release-ssl-dll-zlib \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlib.lib" \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/release" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/release" 

            popd

            pushd src
                # Real unit tests aren't running on Windows yet.  But
                # we can at least build the curl command itself and
                # invoke and inspect it a bit.

                # Target can be 'debug' or 'release' but CFG's
                # are always 'release-*' for the executable build.

                nmake /f Makefile.vc10 debug CFG=release-ssl-dll-zlib \
                    OPENSSL_PATH="$packages/include/openssl" \
                    ZLIB_PATH="$packages/include/zlib" ZLIB_NAME="zlibd.lib" \
                    INCLUDE="$INCLUDE;$packages/include;$packages/include/zlib;$packages/include/openssl" \
                    LIB="$LIB;$packages/lib/debug" \
                    LINDEN_INCPATH="$packages/include" \
                    LINDEN_LIBPATH="$packages/lib/debug" 
            popd

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                # Nothin' to do yet

                popd
            fi

            # Stage archives
            mkdir -p "${stage}"/lib/{debug,release}
            cp -a lib/debug-ssl-dll-zlib/libcurld.lib "${stage}"/lib/debug/libcurld.lib
            cp -a lib/release-ssl-dll-zlib/libcurl.lib "${stage}"/lib/release/libcurl.lib

            # Stage curl.exe and provide .dll's it needs
            mkdir -p "${stage}"/bin
            cp -af "${stage}"/packages/lib/debug/*.{dll,pdb} "${stage}"/bin/
            chmod +x-w "${stage}"/bin/*.dll   # correct package permissions
            cp -a src/curl.{exe,ilk,pdb} "${stage}"/bin/

            # Stage headers
            mkdir -p "${stage}"/include
            cp -a include/curl/ "${stage}"/include/

            # Run 'curl' as a sanity check
            echo "======================================================="
            echo "==    Verify expected versions of libraries below    =="
            echo "======================================================="
            "${stage}"/bin/curl.exe --version
            echo "======================================================="
            echo "======================================================="

            # Clean
            pushd lib
                nmake /f Makefile.vc10 clean
            popd
            pushd src
                nmake /f Makefile.vc10 clean
            popd
        ;;

        "darwin")
            opts="${TARGET_OPTS:--arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.7.sdk -mmacosx-version-min=10.6}"

            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/lib/debug"
            rm -rf Resources/ ../Resources tests/Resources/

            # Force libz static linkage by moving .dylibs out of the way
            for dylib in "$stage"/packages/lib/{debug,release}/libz*.dylib; do
                if [ -f "$dylib" ]; then
                    mv "$dylib" "$dylib".disable
                fi
            done

            # Debug configure and build

            # Make .dylib's usable during configure as well as unit tests
            mkdir -p Resources/
            ln -sf "${stage}"/packages/lib/debug/*.dylib Resources/
            mkdir -p ../Resources/
            ln -sf "${stage}"/packages/lib/debug/*.dylib ../Resources/
            mkdir -p tests/Resources/
            ln -sf "${stage}"/packages/lib/debug/*.dylib tests/Resources/

            # Curl configure has trouble finding zlib 'framework' that
            # it doesn't have with openssl.  We help it with CPPFLAGS.
            CFLAGS="$opts -gdwarf-2 -O0" CXXFLAGS="$opts -gdwarf-2 -O0" \
                LDFLAGS="-L../Resources/ -L\"$stage\"/packages/lib/debug" \
                CPPFLAGS="-I\"$stage\"/packages/include/zlib" \
                ./configure  --disable-ldap --disable-ldaps --enable-shared=no \
                --prefix="$stage" --libdir="${stage}"/lib/debug --enable-threaded-resolver \
                --with-ssl="${stage}/packages" --with-zlib="${stage}/packages" --without-libssh2
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install

            # conditionally run unit tests
            # Disabled here and below by default on Mac because they
            # trigger the Mac firewall dialog and that may make
            # automated builds unreliable.  During development,
            # explicitly inhibit the disable and run the tests.  They
            # matter.
            if [ "${DISABLE_UNIT_TESTS:-1}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 906.  It fails in the
                    # 7.33 distribution with our configuration options.  530 fails
                    # in TeamCity.  (Expect problems with the unit tests, they're
                    # very sensitive to environment.)
                    make quiet-test TEST_Q='-n !906 !530 !564 !584 !706 !1316'
                popd
            fi

            make distclean 
            rm -rf Resources/ ../Resources tests/Resources/

            # Release configure and build
            mkdir -p Resources/
            ln -sf "${stage}"/packages/lib/release/*.dylib Resources/
            mkdir -p ../Resources/
            ln -sf "${stage}"/packages/lib/release/*.dylib ../Resources/
            mkdir -p tests/Resources/
            ln -sf "${stage}"/packages/lib/release/*.dylib tests/Resources/

            CFLAGS="$opts -gdwarf-2" CXXFLAGS="$opts -gdwarf-2" \
                LDFLAGS="-L../Resources/ -L\"$stage\"/packages/lib/release" \
                CPPFLAGS="-I\"$stage\"/packages/include/zlib" \
                ./configure  --disable-ldap --disable-ldaps --enable-shared=no \
                --prefix="$stage" --libdir="${stage}"/lib/release --enable-threaded-resolver \
                --with-ssl="${stage}/packages" --with-zlib="${stage}/packages" --without-libssh2
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-1}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 906.  It fails in the
                    # 7.33 distribution with our configuration options.  530 fails
                    # in TeamCity.  (Expect problems with the unit tests, they're
                    # very sensitive to environment.)
                    make quiet-test TEST_Q='-n !906 !530 !564 !584 !706 !1316'
                popd
            fi

            make distclean 
            rm -rf Resources/ ../Resources tests/Resources/

            # Restore zlib .dylibs
            for dylib in "$stage/packages/lib"/{debug,release}/*.dylib.disable; do
                if [ -f "$dylib" ]; then
                    mv "$dylib" "${dylib%.disable}"
                fi
            done
        ;;

        "linux")
            # Prefer gcc-4.6 if available.
            if [[ -x /usr/bin/gcc-4.6 && -x /usr/bin/g++-4.6 ]]; then
                export CC=/usr/bin/gcc-4.6
                export CXX=/usr/bin/g++-4.6
            fi

            # Default target to 32-bit
            opts="${TARGET_OPTS:--m32}"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi
            
            # Force static linkage to libz by moving .sos out of the way
            for solibdir in "${stage}"/packages/lib/{debug,release}; do
                pushd "$solibdir"
                    for solib in libz*.so*; do
                        if [ -f "$solib" ]; then
                            mv -f "$solib" disable."$solib"
                        fi
                    done
                popd
            done
            
            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/lib/debug"

            # Debug configure and build
            CFLAGS="$opts -g -O0" CXXFLAGS="$opts -g -O0" LDFLAGS="-L\"$stage\"/packages/lib/debug" \
                ./configure --disable-ldap --disable-ldaps --prefix="$stage" --enable-shared=no \
                --prefix="$stage" --libdir="$stage"/lib/debug --enable-threaded-resolver \
                --with-ssl="$stage/packages/" --with-zlib="$stage/packages/" --without-libssh2
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 906.  It fails in the
                    # 7.33 distribution with our configuration options.  530 fails
                    # in TeamCity.  (Expect problems with the unit tests, they're
                    # very sensitive to environment.)
                    saved_path="$LD_LIBRARY_PATH"
                    export LD_LIBRARY_PATH="${stage}"/packages/lib/debug:"$LD_LIBRARY_PATH" 
                    make quiet-test TEST_Q='-n !906 !530 !564 !584'
                    export LD_LIBRARY_PATH="$saved_path"
                popd
            fi

            make distclean 

            # Release configure and build
            CFLAGS="$opts" CXXFLAGS="$opts" LDFLAGS="-L\"$stage\"/packages/lib/release" \
                ./configure --disable-ldap --disable-ldaps --prefix="$stage" --enable-shared=no \
                --prefix="$stage" --libdir="$stage"/lib/release --enable-threaded-resolver \
                --with-ssl="$stage/packages" --with-zlib="$stage/packages" --without-libssh2
            check_damage "$AUTOBUILD_PLATFORM"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                    # We hijack the 'quiet-test' target and redefine it as
                    # a no-valgrind test.  Also exclude test 906.  It fails in the
                    # 7.33 distribution with our configuration options.  530 fails
                    # in TeamCity.  (Expect problems with the unit tests, they're
                    # very sensitive to environment.)
                    saved_path="$LD_LIBRARY_PATH"
                    export LD_LIBRARY_PATH="${stage}"/packages/lib/release:"$LD_LIBRARY_PATH" 
                    make quiet-test TEST_Q='-n !906 !530 !564 !584'
                    export LD_LIBRARY_PATH="$saved_path"
                popd
            fi

            make distclean 

            # Restore libz .sos
            for solibdir in "${stage}"/packages/lib/{debug,release}; do
                pushd "$solibdir"
                    for solib in disable.*.so*; do
                        if [ -f "$solib" ]; then
                            mv -f "$solib" "${solib#disable.}"
                        fi
                    done
                popd
            done
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/curl.txt"
popd

pass

