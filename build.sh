#!/bin/sh

# turn on verbose debugging output for parabuild logs.
set -x

if [ -z "$AUTOBUILD" ] ; then 
    AUTOBUILD="$(which autobuild)"
fi

autobuild_installed ()
{
    if [ -z "$AUTOBUILD" ] || [ ! -x "$AUTOBUILD" ] ; then
		if [ -z "$helper" ] ; then
			helper=.
		fi
		for AUTOBUILD in `which autobuild` "$helper/../autobuild/bin/autobuild" ; do
			if [ -x "$AUTOBUILD" ] ; then
				break
			fi
		done
    fi

    echo "located autobuild tool: '$AUTOBUILD'"
}

# at this point we should know where everything is, so make errors fatal
set -e

# this fail function will either be provided by the parabuild buildscripts or
# not exist.  either way it's a fatal error
autobuild_installed || fail

# *HACK - bash doesn't know how to pass real pathnames to native windows python
if [ "$OSTYPE" == 'cygwin' ] ; then
	AUTOBUILD="$(cygpath -u $AUTOBUILD.cmd)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

"$AUTOBUILD" build

"$AUTOBUILD" package

FOO_INSTALLABLE_PACKAGE_FILENAME="$(ls -1 foo-$FOO_VERSION-$AUTOBUILD_PLATFORM-$(date +%Y%m%d)*.tar.bz2)"
upload_item installer "$FOO_INSTALLABLE_PACKAGE_FILENAME" application/octet-stream

FOO_INSTALLABLE_PACKAGE_MD5="$(calc_md5 "$FOO_INSTALLABLE_PACKAGE_FILENAME")"
echo "{'md5':'$FOO_INSTALLABLE_PACKAGE_MD5', 'url':'http://s3.amazonaws.com/viewer-source-downloads/install_pkgs/$FOO_INSTALLABLE_PACKAGE_FILENAME'}" > "output.json"

upload_item docs "output.json" text/plain

pass

