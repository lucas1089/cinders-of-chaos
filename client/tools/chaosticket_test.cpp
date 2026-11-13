// Test vectors of the start ticket (src/client/chaosticket.h, added by client/base-patches/0198-launcher-start-only.patch).
// The CI step cuts the header out of the patch and builds this against OpenSSL:
//   awk ... client/base-patches/0198-launcher-start-only.patch > $d/chaosticket.h   (as the other chaos*_test.cpp steps of ci.yml)
//   g++ -std=c++17 -Wall -Wextra -I $d client/tools/chaosticket_test.cpp -lcrypto -o $d/chaosticket_test && $d/chaosticket_test
// The vector is the one launcher/src/ticket.rs and client/tools/ticket_vector_test.py also read (launcher/tests/data/
// ticket_vector.json); the Python test fails when the constants below differ from it. The key is a TEST key: the real client
// key never enters the repository, a log or a test.
#include "chaosticket.h"

#include <cctype>
#include <cstdio>
#include <string>

static const char* VECTOR_CLIENT_KEY_HEX = "1111111111111111111111111111111111111111111111111111111111111111";
static const char* VECTOR_SUB_KEY_HEX = "855b74dfece7c8900ac9aa88d3667063ff856c4ab37214179d5287cb8710b4c0";
static const char* VECTOR_NONCE = "00112233445566778899aabbccddeeff";
static const char* VECTOR_TICKET =
    "t1.47.200.1800000000.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52";
static const unsigned long long VECTOR_BUILD = 47;
static const unsigned long long VECTOR_LAUNCHER = 200;
static const unsigned long long VECTOR_EXPIRY = 1800000000;

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
    for (size_t i = 0; i + 1 < hex.size(); i += 2)
        out.push_back(static_cast<char>(std::stoi(hex.substr(i, 2), nullptr, 16)));
    return out;
}

int main()
{
    // RFC 4231 test case 2 under the HMAC, RFC 5869 test case 3 under the HKDF (no salt)
    check(chaosticket::toHex(chaosticket::hmac("Jefe", "what do ya want for nothing?")) ==
              "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
          "HMAC-SHA256 RFC 4231 case 2");
    check(chaosticket::toHex(chaosticket::subKey(std::string(22, '\x0b'))) !=
              "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d",
          "the sub key uses our label, not the RFC's empty info");
    {
        // the RFC 5869 case 3 itself, with the header's own two steps and an empty info
        const std::string prk = chaosticket::hmac(std::string(32, '\0'), std::string(22, '\x0b'));
        check(chaosticket::toHex(chaosticket::hmac(prk, std::string(1, '\x01'))) ==
                  "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d",
              "HKDF-SHA256 RFC 5869 case 3");
    }

    const std::string key = bytes(VECTOR_CLIENT_KEY_HEX);
    check(key.size() == 32, "the test key is 32 bytes");
    check(chaosticket::toHex(chaosticket::subKey(key)) == VECTOR_SUB_KEY_HEX, "sub key of the vector");
    check(chaosticket::mint(key, VECTOR_BUILD, VECTOR_LAUNCHER, VECTOR_EXPIRY, VECTOR_NONCE) == VECTOR_TICKET,
          "ticket of the vector");

    chaosticket::Ticket t;
    check(chaosticket::verify(key, VECTOR_TICKET, VECTOR_EXPIRY - 10, VECTOR_BUILD, &t) == chaosticket::Verdict::Ok,
          "the vector verifies");
    check(t.build == VECTOR_BUILD && t.launcher == VECTOR_LAUNCHER && t.expiry == VECTOR_EXPIRY &&
              t.nonce == VECTOR_NONCE,
          "the fields come back");
    check(chaosticket::verify(key, VECTOR_TICKET, VECTOR_EXPIRY, VECTOR_BUILD) == chaosticket::Verdict::Ok,
          "the last second counts");
    check(chaosticket::verify(key, VECTOR_TICKET, VECTOR_EXPIRY + 1, VECTOR_BUILD) == chaosticket::Verdict::Expired,
          "one second later it is old");
    check(chaosticket::verify(key, VECTOR_TICKET, VECTOR_EXPIRY - 10, VECTOR_BUILD + 1) == chaosticket::Verdict::WrongBuild,
          "another client build");
    check(chaosticket::verify(std::string(32, '\x22'), VECTOR_TICKET, VECTOR_EXPIRY - 10, VECTOR_BUILD) ==
              chaosticket::Verdict::BadMac,
          "another key");

    // any changed field breaks the mac
    const std::string good = VECTOR_TICKET;
    const char* changed[] = {
        "t1.48.200.1800000000.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        "t1.47.201.1800000000.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        "t1.47.200.1800000001.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        "t1.47.200.1800000000.00112233445566778899aabbccddeef0.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        "t1.47.200.1800000000.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb53",
    };
    for (const char* c : changed)
        check(chaosticket::verify(key, c, VECTOR_EXPIRY - 10, 47) == chaosticket::Verdict::BadMac, c);

    // odd text is malformed, never a crash
    std::string upper = good;
    for (char& c : upper)
        c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    const std::string malformed[] = {
        "", "t1", "t1.47.200.1800000000.x.y", upper, good + ".extra", "t2" + good.substr(2), good.substr(0, good.size() - 1),
        "t1.-47.200.1800000000.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        "t1. 47.200.1800000000.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        "t1.4294967296000000.200.1800000000.00112233445566778899aabbccddeeff.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        "t1.47.200.1800000000.0011.09115e8900323d8561376d956ffba6a796a21be83d62c3f9de309d66e86dbb52",
        std::string(10000, '.'), std::string(10000, '1'),
    };
    for (const std::string& m : malformed)
        check(chaosticket::verify(key, m, 1, 47) == chaosticket::Verdict::Malformed, m.substr(0, 40).c_str());

    // a restart ticket: minted by the game itself with the same rules
    const std::string nonce = chaosticket::randomNonce();
    check(nonce.size() == 32 && chaosticket::isLowerHex(nonce, 32), "a random nonce is 32 hex digits");
    check(nonce != chaosticket::randomNonce(), "two nonces differ");
    const std::string r = chaosticket::mint(key, 47, 200, 5000 + chaosticket::RESTART_LIFETIME, nonce);
    check(chaosticket::verify(key, r, 5000, 47) == chaosticket::Verdict::Ok, "a restart ticket verifies");
    check(chaosticket::verify(key, r, 5000 + chaosticket::RESTART_LIFETIME + 1, 47) == chaosticket::Verdict::Expired,
          "and ends after its minute");

    std::printf("chaosticket_test: %d checks, %d failures\n", checks, fails);
    return fails ? 1 : 0;
}
