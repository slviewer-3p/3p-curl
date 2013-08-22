
0.  Pre-Checkin Checklist

    Performed from top of repo, default branch, head:

    [ ]  Is tag 'current' at or near head of 'vendor'?

         hg heads
         hg tags

    [ ]  Is curlbuild.h identical to distribution?

         hg diff -rcurrent curl/include/curl/curlbuild.h

    [ ]  Is Makefile identical to distribution?  Not strictly
         required but a good idea.

         hg diff -rcurrent curl/Makefile


1.  Introduction

    Straight-up import of libcurl built for three platforms
    and made available for static linkage.  As of 22-Aug-13
    or so, follows the guidelines laid out in:

    https://wiki.lindenlab.com/wiki/Mercurial_Vendor_Branches

    Sources from curl.haxx.se are placed in a branch named
    'vendor' into a directory named 'curl' and not the 
    default versioned subdirectory name (e.g.  curl-7.21.1).
    New releases should be integrated into the vendor branch
    as detailed in the wiki.

    Linden changes and additions go into the 'default' 
    branch.

    Tags are inconsistent but I've started doing the following:
    * 'current' points to head or near head of 'vendor'
    * 'vendor_<version>' points to a particular code drop
      in 'vendor'.
    * 'linden_<version>' points to a working build of an
      integrated code drop built from 'default'.

2.  Modifications

    Essential modifications to curl distributions.

  2.1  Do Not Use C-Ares for DNS Lookups

    Use the threaded resolver system which is built on the
    platform's resolver library and made asynchronous and
    thread safe.  The c-ares library appears to be at the
    heart of many of the DNS lookup failures customers see.

    Changes:
    * curl/lib/config-win32.h modified to enable threaded
      resolver.
    * curl/src/config-win32.h modified identically.
    * configure script invoked with correct arguments to
      use the threaded resolver on linux and darwin.

    There is some scripting in the build-cmd.sh file to
    try to catch failures in this area but don't rely
    on it.  

  2.2  Do Not Modify include/curl/curlbuild.h

    The curlbuild.h file distributed in the source tarball
	is specially constructed for platforms that cannot run
    configure and probe the environment (i.e. Windows). If
    you update the vendor branch and then merge back with
    the default, be certain that curlbuild.h is copied verbatim
    from the source distribution and is not modified in
    subsequent commits. Running configure on linux or mac
    will edit the file, removing the windows specific parts. 

  2.3  Makefile.vc10 Modified to Use LINDEN_LIBPATH

    This file has been edited by lindenlab to pick up the
    LINDEN_LIBPATH variable and find our autobuild-packaged
    library files. If you upgrade curl, be sure to carry
    those modifications forward, or find another way to link
    in the autobuild libraries.
