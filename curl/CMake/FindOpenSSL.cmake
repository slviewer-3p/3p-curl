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
#   OPENSSL_FOUND - system has the OpenSSL library
#   OPENSSL_INCLUDE_DIR - the OpenSSL include directory
#   OPENSSL_LIBRARIES - The libraries needed to use OpenSSL

#Set the directory where the packages should be installed
get_filename_component( PACKAGE_DIR "${CMAKE_SOURCE_DIR}/../stage/packages" ABSOLUTE )

if (IS_DIRECTORY ${PACKAGE_DIR})
    # only use the OpenSSL package installed by autobuild in the packages directory

    get_filename_component( RELEASE_PATH "${PACKAGE_DIR}/lib/release" ABSOLUTE )
    get_filename_component( DEBUG_PATH "${PACKAGE_DIR}/lib/debug" ABSOLUTE )

    if (WIN32)
        find_library(LIBSSL_RELEASE
            NAMES
                libssl
            PATHS
                ${RELEASE_PATH}
            NO_DEFAULT_PATH
        )

        find_library(LIBCRYPTO_RELEASE
            NAMES
                libcrypto
            PATHS
                ${RELEASE_PATH}
            NO_DEFAULT_PATH
        )

        if ((${LIBSSL_RELEASE} STREQUAL "LIBSSL_RELEASE-NOTFOUND") OR (${LIBCRYPTO_RELEASE} STREQUAL "LIBCRYPTO_RELEASE-NOTFOUND"))
            message(FATAL_ERROR "OpenSSL release libraries not found!")
        endif()

        list(APPEND LIBS_FINAL
            ${LIBSSL_RELEASE}
            ${LIBCRYPTO_RELEASE}
        )
    else ()
        find_library(OPENSSL_SSL_LIB_RELEASE
            NAMES
                ssl
                ssleasy32
                ssleasy32MD
                libssl
            PATHS
                ${RELEASE_PATH}
            NO_DEFAULT_PATH
        )
        find_library(OPENSSL_CRYPTO_LIB_RELEASE
            NAMES
                crypto
                libcrypto
            PATHS
                ${RELEASE_PATH}
            NO_DEFAULT_PATH
        )

        if (${OPENSSL_SSL_LIB_RELEASE} STREQUAL "OPENSSL_SSL_LIB_RELEASE-NOTFOUND") 
            message(FATAL_ERROR "OpenSSL SSL libraries not found!")
        elseif (${OPENSSL_CRYPTO_LIB_RELEASE} STREQUAL "OPENSSL_CRYPTO_LIB_RELEASE-NOTFOUND")
            message(FATAL_ERROR "OpenSSL crypto libraries not found!")
        endif()

        list(APPEND LIBS_FINAL
            ${OPENSSL_SSL_LIB_RELEASE}
            ${OPENSSL_CRYPTO_LIB_RELEASE}
        )

    endif()

    find_path(OPENSSL_INCLUDE_DIR
            NAMES
                openssl/ssl.h
        PATHS
                "${PACKAGE_DIR}/include"
            NO_DEFAULT_PATH
    )

    if (${OPENSSL_INCLUDE_DIR} STREQUAL "OPENSSL_INCLUDE_DIR-NOTFOUND")
        message(FATAL_ERROR "OpenSSL include files not found!")
    endif()

    set(OPENSSL_LIBRARIES ${LIBS_FINAL} CACHE FILEPATH "The libraries needed to use OpenSSL" )
    set(OPENSSL_FOUND 1 CACHE BOOL "System has the OpenSSL library")
else()
    message(FATAL_ERROR "Package directory not found.  Execute autobuild install!")
endif(IS_DIRECTORY ${PACKAGE_DIR})
