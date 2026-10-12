// Test vectors of the client guard's native part (src/client/chaosguard.h, added by
// client/base-patches/0035-client-guard.patch). Build against an assembled client tree and OpenSSL:
//   g++ -std=c++17 -I <game-dir>/src/client client/tools/chaosguard_test.cpp -lcrypto -o /tmp/chaosguard_test && /tmp/chaosguard_test
// The handshake vector is the same one server/tools/loadtest.py computes with Python's hmac (guard_answer), so the
// client, the server (src-patch 0021, Crypto++) and the load test agree on the message layout.
#include "chaosguard.h"

#include <cstdio>
#include <string>

static int fails = 0, checks = 0;
static void check(bool ok, const char* what)
{
    ++checks;
    if (!ok) {
        std::printf("FAIL %s\n", what);
        ++fails;
    }
}

static std::string bytes(const std::string& hex)
{
    std::string out;
    chaosguard::fromHex(hex, out);
    return out;
}

int main()
{
    // RFC 4231 test case 2: the HMAC-SHA256 underneath (key "Jefe")
    {
        unsigned char out[32];
        unsigned int len = 0;
        const std::string msg = "what do ya want for nothing?";
        HMAC(EVP_sha256(), "Jefe", 4, reinterpret_cast<const unsigned char*>(msg.data()), msg.size(), out, &len);
        check(chaosguard::toHex(std::string(reinterpret_cast<char*>(out), len)) ==
                  "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", "RFC 4231 case 2");
    }

    // the handshake: development key, nonce 00..0f, account "acc", character "Name", build 7
    const std::string devKey = bytes("4445562d4b45592d63696e646572732d6f662d6368616f732d554e5341464521");
    check(devKey == "DEV-KEY-cinders-of-chaos-UNSAFE!", "development key bytes");
    std::string nonce;
    check(chaosguard::parseChallenge("cg1:000102030405060708090a0b0c0d0e0f", nonce), "challenge parsed");
    check(nonce == bytes("000102030405060708090a0b0c0d0e0f"), "nonce bytes");
    check(chaosguard::answer(devKey, nonce, "acc", "Name", 7) ==
              "cg1:7:9b0910caa733c832d1d824fbbcb98548d2844a0a8e6afdbda4637d2a8897fb87", "handshake vector");
    check(chaosguard::answer(devKey, nonce, "acc", "Name", 8) != chaosguard::answer(devKey, nonce, "acc", "Name", 7),
          "build is part of the MAC");
    check(chaosguard::answer(devKey, nonce, "ac", "cName", 7) != chaosguard::answer(devKey, nonce, "acc", "Name", 7),
          "names are length-prefixed");

    // malformed challenges
    const char* bad[] = { "", "cg1:", "cg2:000102030405060708090a0b0c0d0e0f", "cg1:000102030405060708090a0b0c0d0e",
                          "cg1:000102030405060708090a0b0c0d0e0f00", "cg1:zz0102030405060708090a0b0c0d0e0f" };
    for (const char* b : bad)
        check(!chaosguard::parseChallenge(b, nonce), b);

    // the identifier of the login packets
    check((chaosguard::clientId() >> 16) == 0x4343, "identifier tag");
    check((chaosguard::clientId() & 0xFFFF) == chaosguard::build(), "identifier build");

    std::string secret = "secret";
    chaosguard::wipe(secret);
    check(secret.empty(), "wipe");

    std::printf("chaosguard_test: %d checks, %s\n", checks, fails ? "FAILED" : "OK");
    return fails ? 1 : 0;
}
