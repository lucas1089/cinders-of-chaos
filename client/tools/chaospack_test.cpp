// Native vectors for the encrypted client pack (src/framework/util/chaospack.h, base patch 0102). Proves the engine's
// AES-256-GCM + HKDF-SHA256 format is byte-identical to client/tools/pack_client.py: the fixed cross-language vector,
// a round trip, wrong-key failure and tamper detection. Built standalone in CI (.github/workflows/ci.yml):
//   g++ -std=c++17 -I "$d/src" client/tools/chaospack_test.cpp -lcrypto -o chaospack_test
#include <framework/util/chaospack.h>

#include <cstdio>
#include <string>

static int failures = 0;

static void check(bool cond, const char* msg)
{
    if (!cond) {
        std::printf("FAIL: %s\n", msg);
        ++failures;
    }
}

static std::string fromHex(const std::string& hex)
{
    std::string out;
    for (size_t i = 0; i + 1 < hex.size(); i += 2)
        out.push_back(static_cast<char>(std::stoi(hex.substr(i, 2), nullptr, 16)));
    return out;
}

static std::string toHex(const std::string& bytes)
{
    static const char d[] = "0123456789abcdef";
    std::string out;
    for (unsigned char c : bytes) {
        out.push_back(d[c >> 4]);
        out.push_back(d[c & 0xF]);
    }
    return out;
}

int main()
{
    // key = 00 01 .. 1f
    std::string key(32, '\0');
    for (int i = 0; i < 32; ++i)
        key[i] = static_cast<char>(i);

    // The fixed vector pack_client_test.py prints and asserts.
    const std::string plaintext = "cinders-of-chaos";
    const std::string expectEncKey = "8664f864be53d89bd9681ba75531422d12fb7458f0e1daca98980079154470ab";
    const std::string expectNonce = "53123440ea4dfe8c06531097";
    const std::string expectPack =
        "4348504b0100000053123440ea4dfe8c065310971000000000000000"
        "839c5a388737b75f311c824d116d13705cae09ce4749596ebfbdba7c9ceadf31";

    std::string encKey, nonceKey;
    check(chaospack::deriveKeys(key, encKey, nonceKey), "deriveKeys");
    check(toHex(encKey) == expectEncKey, "enc key matches Python");

    std::string pack;
    check(chaospack::encrypt(key, plaintext, false, pack), "encrypt");
    check(toHex(pack.substr(8, 12)) == expectNonce, "nonce matches Python");
    check(toHex(pack) == expectPack, "pack bytes match Python (determinism + format)");

    std::string out;
    check(chaospack::decrypt(key, fromHex(expectPack), out), "decrypt the Python vector");
    check(out == plaintext, "decrypt gives the plaintext");

    // round trip over a larger blob
    std::string big;
    for (int i = 0; i < 10000; ++i)
        big.push_back(static_cast<char>((i * 7) & 0xFF));
    std::string bigPack, bigOut;
    check(chaospack::encrypt(key, big, false, bigPack), "encrypt big");
    check(chaospack::decrypt(key, bigPack, bigOut), "decrypt big");
    check(bigOut == big, "big round trip");

    // wrong key fails
    std::string otherKey(32, '\0');
    for (int i = 0; i < 32; ++i)
        otherKey[i] = static_cast<char>(i + 1);
    std::string bad;
    check(!chaospack::decrypt(otherKey, pack, bad), "wrong key fails");

    // tampered ciphertext fails
    std::string tampered = pack;
    tampered[chaospack::HEADER_LEN + 2] ^= 0x01;
    check(!chaospack::decrypt(key, tampered, bad), "tampered ciphertext fails");

    // tampered header (flags byte, part of the AAD) fails
    std::string tampered2 = pack;
    tampered2[5] ^= 0x01;
    check(!chaospack::decrypt(key, tampered2, bad), "tampered header fails");

    if (failures) {
        std::printf("%d check(s) failed\n", failures);
        return 1;
    }
    std::printf("chaospack_test: all checks passed\n");
    return 0;
}
