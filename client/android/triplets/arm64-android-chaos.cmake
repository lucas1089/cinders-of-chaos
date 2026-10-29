# vcpkg triplet for the Android client (O313): arm64 only, static libraries, release only, API 26.
# Used with the NDK that ANDROID_NDK_HOME names (r27d, see docs/ANDROID_CLIENT.md).
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_CMAKE_SYSTEM_VERSION 26)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
# the NDK toolchain falls back to armeabi-v7a without it (luajit then assembles arm64 code for armv7)
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=arm64-v8a)
set(VCPKG_BUILD_TYPE release)
# position independent code: every static library ends up in one shared library
set(VCPKG_C_FLAGS "-fPIC")
set(VCPKG_CXX_FLAGS "-fPIC")
# 16 KB page size: Android 15 devices and Google Play ask for aligned libraries
set(VCPKG_LINKER_FLAGS "-Wl,-z,max-page-size=16384")
