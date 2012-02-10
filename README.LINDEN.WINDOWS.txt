=== curl-7.X.Y/include/curl/curlbuild.h ===

The curlbuild.h file distributed in the source tarball is specially constructed 
for platforms that cannot run configure and probe the environment. If you update 
the vendor branch and then merge back with the default, be certain that 
curlbuild.h is copied verbatim from the source distribution and is not modified 
in subsequent commits. Running configure on linux or mac will edit the file, 
removing the windows specific parts. 

=== curl-7.X.Y/lib/Makefile.vc10 ===

This file has been edited by lindenlab to pick up the LINDEN_LIBPATH variable 
and find our autobuild-packaged library files. If you upgrade curl, be sure to 
carry those modifications forward, or find another way to link in the autobuild 
libraries.
