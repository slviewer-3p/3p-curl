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
eval "$("$AUTOBUILD" source_environment)"

"$AUTOBUILD" install

"$AUTOBUILD" build --use-cwd

"$AUTOBUILD" package

PACKAGE_FILENAME="$(ls -1 ${PACKAGE_NAME}-*-$AUTOBUILD_PLATFORM-$(date +%Y%m%d)*.tar.bz2)"

if "$build_legacy_package" ; then
    # repackage_legacy is defined in the branch independent BuildParams defaults
    "$repackage_legacy" "$PACKAGE_FILENAME"
fi

upload_item installer "$PACKAGE_FILENAME" binary/octet-stream

PACKAGE_MD5="$(calc_md5 "$PACKAGE_FILENAME")"
PACKAGE_DST="$S3PUT_URL""$S3PREFIX""repo/$repo/rev/$revision/arch/$arch/installer/$(basename "$PACKAGE_FILENAME")"
echo "{'md5':'$PACKAGE_MD5', 'url':'$PACKAGE_DST'}" > "output.js"

upload_item installer "output.json" text/plain

pass

