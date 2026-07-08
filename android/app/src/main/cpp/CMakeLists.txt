cmake_minimum_required(VERSION 3.22.1)
project(rekindle_rar C)

# ---------------------------------------------------------------------------
# libarchive — provides RAR4 + RAR5 extraction.
#
# Its RAR5 reader is a clean-room, BSD-2-licensed implementation (NOT the
# license-encumbered unRAR source), so it is safe for F-Droid distribution.
#
# Pulled at configure time via FetchContent, so the FIRST native build needs
# network access. Set FETCHCONTENT_BASE_DIR (or vendor the source and switch to
# add_subdirectory) if you need offline / reproducible builds.
#
# All optional formats, filters and crypto backends are disabled: we only need
# RAR reading, which has no external dependencies.
# ---------------------------------------------------------------------------
include(FetchContent)

set(ENABLE_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_TAR OFF CACHE BOOL "" FORCE)
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)
set(ENABLE_UNZIP OFF CACHE BOOL "" FORCE)
set(ENABLE_ZLIB OFF CACHE BOOL "" FORCE)
set(ENABLE_BZip2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZMA OFF CACHE BOOL "" FORCE)
set(ENABLE_LZO OFF CACHE BOOL "" FORCE)
set(ENABLE_LZ4 OFF CACHE BOOL "" FORCE)
set(ENABLE_ZSTD OFF CACHE BOOL "" FORCE)
set(ENABLE_OPENSSL OFF CACHE BOOL "" FORCE)
set(ENABLE_MBEDTLS OFF CACHE BOOL "" FORCE)
set(ENABLE_NETTLE OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBB2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(ENABLE_EXPAT OFF CACHE BOOL "" FORCE)
set(ENABLE_PCREPOSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_PCRE2POSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_ICONV OFF CACHE BOOL "" FORCE)
set(ENABLE_ACL OFF CACHE BOOL "" FORCE)
set(ENABLE_XATTR OFF CACHE BOOL "" FORCE)
set(ENABLE_WERROR OFF CACHE BOOL "" FORCE)

# TODO(build): pin URL_HASH for reproducibility / supply-chain safety. Get the
# real SHA256 from https://github.com/libarchive/libarchive/releases (v3.7.7, or
# bump to the current 3.8.x) and add:  URL_HASH SHA256=<hash>
FetchContent_Declare(
        libarchive
        URL https://github.com/libarchive/libarchive/releases/download/v3.7.7/libarchive-3.7.7.tar.gz
)
FetchContent_MakeAvailable(libarchive)

add_library(rekindle_rar SHARED rar_extract.c)

target_include_directories(rekindle_rar PRIVATE
        ${libarchive_SOURCE_DIR}/libarchive)

# archive_static links libarchive directly into our .so, so the separate
# libarchive.so that libarchive's build also emits is excluded from packaging
# (see app/build.gradle.kts).
target_link_libraries(rekindle_rar PRIVATE archive_static log)
