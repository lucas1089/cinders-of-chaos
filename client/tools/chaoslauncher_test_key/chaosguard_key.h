// A TEST key header for client/tools/chaoslauncher_test.cpp, standing in for the chaosguard_key.h that src/client/CMakeLists.txt
// writes into the build folder (base patch 0035). The key is 32 bytes of 0x11: the same TEST key as the ticket vector
// (launcher/tests/data/ticket_vector.json). Never a real key: the real client key never enters the repository, a log or a test.
#pragma once
#define CHAOS_GUARD_KEY_IS_DEV 1
namespace chaosguard_key {
static const volatile unsigned char x[32] = {17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17,17};
static const volatile unsigned char m[32] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
static const volatile unsigned char p[32] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31};
}
