#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

CURL_SOURCE_DIR="curl"
CURL_BUILD_DIR="build"

# load autobuild provided shell functions and variables
set +x
eval "$("$autobuild" source_environment)"
set -x

# set LL_BUILD and friends
set_build_variables convenience Release

top="$(pwd)"
stage="$(pwd)/stage"

ZLIB_INCLUDE="${stage}"/packages/include/zlib
OPENSSL_INCLUDE="${stage}"/packages/include/openssl

[ -f "$ZLIB_INCLUDE"/zlib.h ] || fail "You haven't installed the zlib package yet."
[ -f "$OPENSSL_INCLUDE"/ssl.h ] || fail "You haven't installed the openssl package yet."

LIBCURL_VERSION_HEADER_DIR="${CURL_SOURCE_DIR}"/include/curl
version=$(perl -ne 's/#define LIBCURL_VERSION "([^"]+)"/$1/ && print' "${LIBCURL_VERSION_HEADER_DIR}/curlver.h" | tr -d '\r' )
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/release/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}


# Restore all .dylibs
restore_dylibs ()
{
    for dylib in "$stage/packages/lib"/release/*.dylib.disable; do
        if [ -f "$dylib" ]; then
            mv "$dylib" "${dylib%.disable}"
        fi
    done
}

# See if there's anything wrong with the checked out or
# generated files.  Main test is to confirm that c-ares
# is defeated and we're using a threaded resolver.
check_damage ()
{
    case "$1" in
        windows*)
            #echo "Verifying Ares is disabled"
            #grep 'USE_ARES\s*1' lib/curl_config.h | grep '^/\*'
        ;;

        darwin*|linux*)
            echo "Verifying Ares is disabled"
            egrep 'USE_THREADS_POSIX[[:space:]]+1' lib/curl_config.h
        ;;
    esac
}

# Read the version of a particular installable package from autobuild.xml.
# Optional $2 specifies number of version-number parts to report.
get_installable_version ()
{
    set +x
    # This command dumps the autobuild.xml data for the specified installable
    # in Python literal syntax.
    pydata="$("$autobuild" installables print "$1")"
    # Now harvest the version key.
    # It's important to use ''' syntax because of newlines in output. Specify
    # raw literal syntax too in case of backslashes.
    # Use ast.literal_eval(), safer than plain builtin eval.
    # Once we have the Python dict, extract "version" key.
    # Split version number on '.'.
    # Keep up to $2 version-number parts.
    # Rejoin them on '.' again and print.
    # On Windows, change '\r\n' to plain '\n': the '\r' is NOT removed by
    # bash, so it becomes part of the string contents, which confuses both
    # scripted comparisons and human readers.
    python -c "from ast import literal_eval
print '.'.join(literal_eval(r'''$pydata''')['version'].split('.')[:${2:-}])" \
        | tr -d '\r'
    set -x
}

# Given an (e.g. version) string possibly containing periods, escape those
# periods with backslashes.
escape_dots ()
{
    echo "${1//./\\.}"
}

mkdir -p "$CURL_BUILD_DIR"

pushd "$CURL_BUILD_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
		
            packages="$(cygpath -m "$stage/packages")"
            load_vsvars

			if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
				then CMAKE_GEN="Visual Studio 12 2013"
				else CMAKE_GEN="Visual Studio 12 2013 Win64"
			fi

            cmake ../${CURL_SOURCE_DIR} -G"$CMAKE_GEN" -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"

            check_damage "$AUTOBUILD_PLATFORM"

            build_sln "CURL.sln" "Release|$AUTOBUILD_WIN_VSPLATFORM" "Install"
			
            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                pushd tests
                # Nothin' to do yet

                popd
            fi

           # Stage archives
           mkdir -p "${stage}/lib/release"
           mv "${stage}"/lib/libcurl.lib "${stage}"/lib/release/libcurl.lib

#           # Stage curl.exe and provide .dll's it needs
#           mkdir -p "${stage}"/bin
            cp -af "${stage}"/packages/lib/release/*.dll "${stage}"/bin/
            chmod +x-w "${stage}"/bin/*.dll   # correct package permissions

            # Run 'curl' as a sanity check. Capture just the first line, which
            # should have versions of stuff.
            curlout="$("${stage}"/bin/curl.exe --version | tr -d '\r' | head -n 1)"
            # With -e in effect, any nonzero rc blows up the script --
            # so plain 'expr str : pattern' asserts that str contains pattern.
            # curl version - should be start of line
            expr "$curlout" : "curl $(escape_dots "$version")" #> /dev/null
            # libcurl/version
            expr "$curlout" : ".* libcurl/$(escape_dots "$version")" > /dev/null
            # OpenSSL/version
            expr "$curlout" : ".* OpenSSL/$(escape_dots "$(get_installable_version openssl 3)")" > /dev/null
            # zlib/version
            expr "$curlout" : ".* zlib/$(escape_dots "$(get_installable_version zlib 3)")" > /dev/null

#            # Clean
#            pushd lib
#                nmake /f Makefile.VC6 clean
#            popd
#            pushd src
#                nmake /f Makefile.VC6 clean
#            popd
        ;;

        darwin*)
            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD}"

            mkdir -p "$stage/lib/release"
            rm -rf Resources/ ../Resources tests/Resources/

            # Force libz and openssl static linkage by moving .dylibs out of the way
            trap restore_dylibs EXIT
            for dylib in "$stage"/packages/lib/release/lib{z,crypto,ssl}*.dylib; do
                if [ -f "$dylib" ]; then
                    mv "$dylib" "$dylib".disable
                fi
            done

            #./buildconf

            # Release configure and build

            # Make .dylib's usable during configure as well as unit tests
            # (Used when building with dylib libz or OpenSSL.)
            # mkdir -p Resources/
            # ln -sf "${stage}"/packages/lib/release/*.dylib Resources/
            # mkdir -p ../Resources/
            # ln -sf "${stage}"/packages/lib/release/*.dylib ../Resources/
            # mkdir -p tests/Resources/
            # ln -sf "${stage}"/packages/lib/release/*.dylib tests/Resources/
            # LDFLAGS="-L../Resources/ -L\"$stage\"/packages/lib/release" \

            # Curl configure has trouble finding zlib 'framework' that
            # it doesn't have with openssl.  We help it with CPPFLAGS.

            # -g/-O options controled by --enable-debug/-optimize.  Unfortunately,
            # --enable-debug also defines DEBUGBUILD which changes behaviors.
#            CFLAGS="$opts" \
                CXXFLAGS="$opts" \
                LDFLAGS=-L"$stage"/packages/lib/release \
                CPPFLAGS="$opts -I$stage/packages/include/zlib" \
                ./configure  --disable-ldap --disable-ldaps --enable-shared=no \
                --disable-debug --disable-curldebug --enable-optimize \
                --prefix="$stage" --libdir="${stage}"/lib/release --enable-threaded-resolver \
                --with-ssl="${stage}/packages" --with-zlib="${stage}/packages" --without-libssh2
#            check_damage "$AUTOBUILD_PLATFORM"
#            make
#            make install

            # conditionally run unit tests
            # Disabled here and below by default on Mac because they
            # trigger the Mac firewall dialog and that may make
            # automated builds unreliable.  During development,
            # explicitly inhibit the disable and run the tests.  They
            # matter.
#            if [ "${DISABLE_UNIT_TESTS:-1}" = "0" ]; then
#                pushd tests
#                    # We hijack the 'quiet-test' target and redefine it as
#                    # a no-valgrind test.  Also exclude test 906.  It fails in the
#                    # 7.33 distribution with our configuration options.  530 fails
#                    # in TeamCity.  (Expect problems with the unit tests, they're
#                    # very sensitive to environment.)
#                    make quiet-test TEST_Q='-n !906 !530 !564 !584 !706 !1316'
#                popd
#            fi

			cmake ../${CURL_SOURCE_DIR} -GXcode -DCMAKE_C_FLAGS:STRING="$opts" -DCMAKE_CXX_FLAGS:STRING="$opts" -D'BUILD_SHARED_LIBS:bool=off' -D'BUILD_CODEC:bool=off' -DCMAKE_INSTALL_PREFIX=$stage

            check_damage "$AUTOBUILD_PLATFORM"

            xcodebuild -configuration Release -target libcurl -project CURL.xcodeproj
            xcodebuild -configuration Release -target install -project CURL.xcodeproj
            mkdir -p "$stage/lib/release"
            mv "$stage/lib/libcurl.a" "$stage/lib/release/libcurl.a"
			
#            make distclean
            # Again, for dylib dependencies
            # rm -rf Resources/ ../Resources tests/Resources/
        ;;

        linux*)
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

#            ./buildconf

##          # Prefer gcc-4.6 if available.
##          if [[ -x /usr/bin/gcc-4.6 && -x /usr/bin/g++-4.6 ]]; then
##              export CC=/usr/bin/gcc-4.6
##              export CXX=/usr/bin/g++-4.6
##          fi

            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Force static linkage to libz and openssl by moving .sos out of the way
            trap restore_sos EXIT
            for solib in "${stage}"/packages/lib/release/lib{z,ssl,crypto}.so*; do
                if [ -f "$solib" ]; then
                    mv -f "$solib" "$solib".disable
                fi
            done

            mkdir -p "$stage/lib/release"

            # Autoconf's configure will do some odd things to flags.  '-I' options
            # will get transferred to '-isystem' and there's a problem with quoting.
            # Linking and running also require LD_LIBRARY_PATH to locate the OpenSSL
            # .so's.  The '--with-ssl' option could do this if we had a more normal
            # package layout.
            #
            # configure-time compilation looks like:
            # ac_compile='$CC -c $CFLAGS $CPPFLAGS conftest.$ac_ext >&5'
            # ac_link='$CC -o conftest$ac_exeext $CFLAGS $CPPFLAGS $LDFLAGS conftest.$ac_ext $LIBS >&5'
            saved_path="${LD_LIBRARY_PATH:-}"

            # Release configure and build
            export LD_LIBRARY_PATH="${stage}"/packages/lib/release:"$saved_path"

            # -g/-O options controled by --enable-debug/-optimize.  Unfortunately,
            # --enable-debug also defines DEBUGBUILD which changes behaviors.
#            CFLAGS="$opts" \
#                CXXFLAGS="$opts"  \
#                CPPFLAGS="${CPPFLAGS:-} $opts -I$stage/packages/include/zlib" \
#                LIBS="-ldl" \
#                LDFLAGS="-L$stage/packages/lib/release" \
#                ./configure --disable-ldap --disable-ldaps --enable-shared=no --enable-threaded-resolver \
#                --disable-debug --disable-curldebug --enable-optimize \
#                --prefix="$stage" --libdir="$stage"/lib/release \
#                --with-ssl="$stage"/packages --with-zlib="$stage"/packages --without-libssh2
#            check_damage "$AUTOBUILD_PLATFORM"
#            make
#            make install

 #           # conditionally run unit tests
 #           if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
#                pushd tests
#                    # We hijack the 'quiet-test' target and redefine it as
#                    # a no-valgrind test.  Also exclude test 906.  It fails in the
#                    # 7.33 distribution with our configuration options.  530 fails
#                    # in TeamCity.  815 hangs in 7.36.0 fixed in 7.37.0.
#                    #
#                    # Expect problems with the unit tests, they're very sensitive
#                    # to environment.
#                    make quiet-test TEST_Q='-n !906 !530 !564 !584 !1026'
#                popd
#            fi

#            make distclean
#            mkdir -p "$stage/lib/release"
#            mkdir -p "$stage/lib/debug"

            cmake ../${CURL_SOURCE_DIR} -G"Unix Makefiles" -D'CMAKE_C_FLAGS:STRING=-m32' -D'CMAKE_CXX_FLAGS:STRING=-m32' -D'BUILD_SHARED_LIBS:bool=off' -DCMAKE_INSTALL_PREFIX=$stage
			
            check_damage "$AUTOBUILD_PLATFORM"

            make
            make install
            mkdir -p "$stage/lib/release"
            mv "$stage/lib/libcurl.a" "$stage/lib/release/libcurl.a"

            export LD_LIBRARY_PATH="$saved_path"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp ../"${CURL_SOURCE_DIR}"/COPYING "$stage/LICENSES/curl.txt"
popd
rm -rf "$CURL_BUILD_DIR"

mkdir -p "$stage"/docs/curl/
cp -a "$top"/README.Linden "$stage"/docs/curl/


pass
