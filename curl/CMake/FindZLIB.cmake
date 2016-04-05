################################################################
# @file FindOpenSSL.cmake
# @brief Locate Linden Lab OpenSSL package for CURL build
#
# $LicenseInfo:firstyear=2011&license=viewerlgpl$
#Second Life Viewer Source Code
#Copyright (C) 2016, Linden Research, Inc.
#
#This library is free software; you can redistribute it and/or
#modify it under the terms of the GNU Lesser General Public
#License as published by the Free Software Foundation;
#version 2.1 of the License only.
#
#This library is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#Lesser General Public License for more details.
#
#You should have received a copy of the GNU Lesser General Public
#License along with this library; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
#Linden Research, Inc., 945 Battery Street, San Francisco, CA  94111  USA
#$/LicenseInfo$
################################################################
# Variables set:
# ::
#
#   ZLIB_INCLUDE_DIRS   - where to find zlib.h, etc.
#   ZLIB_LIBRARIES      - List of libraries when using zlib.
#   ZLIB_FOUND          - True if zlib found.
#
# ::

#Set the directory where the packages should be installed
get_filename_component( PACKAGE_DIR "${CMAKE_SOURCE_DIR}/../stage/packages" ABSOLUTE )

if (IS_DIRECTORY ${PACKAGE_DIR})
    # only use the Zlib package installed by autobuild in the packages directory

    get_filename_component( RELEASE_PATH "${PACKAGE_DIR}/lib/release" ABSOLUTE )

    find_library(LIB_MINI_RELEASE
        NAMES
            minizip
        PATHS
            ${RELEASE_PATH}
        NO_DEFAULT_PATH
    )

    find_library(LIB_ZLIB_RELEASE
        NAMES
            zlib
            z
        PATHS
            ${RELEASE_PATH}
        NO_DEFAULT_PATH
    )

    if (${LIB_MINI_RELEASE} STREQUAL "LIB_MINI_RELEASE-NOTFOUND")
        message(FATAL_ERROR "Zlib Mini not found!")
    elseif (${LIB_ZLIB_RELEASE} STREQUAL "LIB_ZLIB_RELEASE-NOTFOUND")
        message(FATAL_ERROR "ZLib Libraries not found!")
    endif()

    find_path(ZLIB_INCLUDE_DIRS
        NAMES
            zlib.h
        PATHS
            "${PACKAGE_DIR}/include"
        PATH_SUFFIXES
            "zlib"
    )

    if (${ZLIB_INCLUDE_DIRS} STREQUAL "ZLIB_INCLUDE_DIRS-NOTFOUND")
        message(FATAL_ERROR "OpenSSL include files not found!")
    endif()

    list(APPEND LIBS_FINAL
        ${LIB_ZLIB_RELEASE}
        ${LIB_MINI_RELEASE}
    )

    set(ZLIB_LIBRARIES ${LIBS_FINAL} CACHE FILEPATH "List of libraries when using zlib." )
    set(ZLIB_FOUND 1 CACHE BOOL "True if zlib found.")

else()
    message(FATAL_ERROR "Package directory not found.  Execute autobuild install!")
endif(IS_DIRECTORY ${PACKAGE_DIR})
