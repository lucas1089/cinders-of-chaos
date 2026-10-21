// Native vectors for the encrypted client pack (src/framework/util/chaospack.h, base patch 0102, format version 2:
// zlib level 9 then AES-256-GCM). Proves the engine's format is byte-identical to client/tools/pack_client.py: the
// fixed cross-language vector, round trips through the streaming decryptStream() (the engine's path, also with a
// reader that returns odd-sized pieces of a multi-chunk pack), wrong key, tamper, truncation and the inflate length
// checks. Built standalone in CI (.github/workflows/ci.yml):
//   g++ -std=c++17 -I "$d/src" client/tools/chaospack_test.cpp -lcrypto -lz -o chaospack_test
// With a pack file as argument it instead times the streamed decrypt + inflate of that file with the development key:
//   chaospack_test some.pack
#include <framework/util/chaospack.h>

#include <chrono>
#include <cstdio>
#include <fstream>
#include <random>
#include <string>
#include <vector>

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

static bool decryptVec(const std::string& key, const std::string& pack, std::vector<uint8_t>& out)
{
    size_t at = 0;
    auto read = [&](unsigned char* dst, size_t n) {
        if (n > pack.size() - at)
            return false;
        std::memcpy(dst, pack.data() + at, n);
        at += n;
        return true;
    };
    return chaospack::decryptStream(key, pack.size(), read, out);
}

// an authentic pack around any body, so only the zlib and length checks can refuse it
static std::string seal(const std::string& key, uint64_t declared, const std::string& body, uint8_t version)
{
    std::string encKey, nonceKey;
    chaospack::deriveKeys(key, encKey, nonceKey);
    const std::string nonce = chaospack::hmacSha256(nonceKey, body).substr(0, chaospack::NONCE_LEN);
    std::string header("CHPK", 4);
    header.push_back(static_cast<char>(version));
    header.append(3, '\0');
    header += nonce;
    chaospack::writeU64LE(header, declared);
    std::string ct, tag;
    chaospack::aesGcmEncrypt(encKey, nonce, header, body, ct, tag);
    return header + ct + tag;
}

static std::string zlibOf(const std::string& data)
{
    uLongf n = compressBound(static_cast<uLong>(data.size()));
    std::string out(n, '\0');
    compress2(reinterpret_cast<Bytef*>(&out[0]), &n, reinterpret_cast<const Bytef*>(data.data()),
              static_cast<uLong>(data.size()), 9);
    out.resize(n);
    return out;
}

// time the engine's path on a real pack file (development key), the way mountEncryptedPack() reads it
static int timeFile(const char* path)
{
    const std::string devKey = "DEV-KEY-cinders-of-chaos-UNSAFE!";
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) {
        std::printf("cannot open %s\n", path);
        return 1;
    }
    const uint64_t size = static_cast<uint64_t>(stream.tellg());
    stream.seekg(0);
    auto read = [&stream](unsigned char* dst, size_t n) {
        return static_cast<bool>(stream.read(reinterpret_cast<char*>(dst), static_cast<std::streamsize>(n)));
    };
    std::vector<uint8_t> out;
    const auto t0 = std::chrono::steady_clock::now();
    const bool ok = chaospack::decryptStream(devKey, size, read, out);
    const auto ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    std::printf("%s: %s, pack %llu bytes -> ZIP %llu bytes in %lld ms\n", path, ok ? "ok" : "FAILED",
                static_cast<unsigned long long>(size), static_cast<unsigned long long>(out.size()),
                static_cast<long long>(ms));
    return ok ? 0 : 1;
}

int main(int argc, char** argv)
{
    if (argc > 1)
        return timeFile(argv[1]);

    // key = 00 01 .. 1f
    std::string key(32, '\0');
    for (int i = 0; i < 32; ++i)
        key[i] = static_cast<char>(i);

    // The fixed vector pack_client_test.py asserts (VECTOR_*): "cinders-of-chaos " * 8, zlib level 9.
    std::string plaintext;
    for (int i = 0; i < 8; ++i)
        plaintext += "cinders-of-chaos ";
    const std::string expectEncKey = "8664f864be53d89bd9681ba75531422d12fb7458f0e1daca98980079154470ab";
    const std::string expectNonce = "a4f05f4f646c80674642f216";
    const std::string expectPack =
        "4348504b02000000a4f05f4f646c80674642f2168800000000000000"
        "2adfd565c2ccbec47d45ae8bed629eb494db35d0f392e139d1ea224a73a1abe379728e73d0750f8aa8a6c21e";

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

    // streamed (the engine's path): the Python vector, wrong key, tampering, truncation
    auto str = [](const std::vector<uint8_t>& v) { return std::string(v.begin(), v.end()); };
    std::vector<uint8_t> buf;
    check(decryptVec(key, fromHex(expectPack), buf) && str(buf) == plaintext, "stream: the Python vector");
    check(decryptVec(key, bigPack, buf) && str(buf) == big, "stream: big round trip");
    check(!decryptVec(otherKey, pack, buf) && buf.empty(), "stream: wrong key fails and clears");
    check(!decryptVec(key, tampered, buf) && buf.empty(), "stream: tampered ciphertext fails");
    check(!decryptVec(key, tampered2, buf), "stream: tampered header fails");
    for (size_t at : { size_t(4), size_t(6), size_t(20), size_t(27), pack.size() - 1 }) {
        std::string t = pack;
        t[at] ^= 0x01;
        check(!decryptVec(key, t, buf) && buf.empty(), "stream: flipped header / tag byte fails");
    }
    for (size_t cut : { size_t(1), size_t(16), size_t(17) })
        check(!decryptVec(key, pack.substr(0, pack.size() - cut), buf), "stream: truncated pack fails");
    check(!decryptVec(key, pack + std::string(1, '\0'), buf), "stream: a trailing byte fails");

    {
        // ~12 MB, half compressible text and half random: several 4 MB chunks, the reader hands out 1 MB + 3 pieces
        std::mt19937 rng(7);
        std::string tree;
        while (tree.size() < 6u * 1024 * 1024)
            tree += "modules/game_x/x.lua print('cinders of chaos') ";
        while (tree.size() < 12u * 1024 * 1024 + 12345)
            tree.push_back(static_cast<char>(rng() & 0xFF));
        std::string treePack;
        check(chaospack::encrypt(key, tree, true, treePack), "encrypt 12 MB");
        check(treePack.size() < tree.size() * 3 / 4, "12 MB: compressed");
        check(treePack[5] == chaospack::FLAG_DEV, "dev flag in the header");
        size_t at = 0;
        auto oddRead = [&](unsigned char* dst, size_t n) {
            while (n > 0) { // a reader that fills in pieces still has to fill exactly n
                const size_t step = std::min<size_t>(n, 1024 * 1024 + 3);
                if (step > treePack.size() - at)
                    return false;
                std::memcpy(dst, treePack.data() + at, step);
                at += step;
                dst += step;
                n -= step;
            }
            return true;
        };
        check(chaospack::decryptStream(key, treePack.size(), oddRead, buf) && buf.size() == tree.size() &&
                  str(buf) == tree,
              "stream: 12 MB multi-chunk round trip");
        std::string late = treePack;
        late[late.size() - chaospack::TAG_LEN - 2] ^= 0x01; // inside the Adler-32 or last deflate bytes
        check(!decryptVec(key, late, buf) && buf.empty(), "stream: change in the last chunk fails and clears");
        std::string early = treePack;
        early[chaospack::HEADER_LEN + 100] ^= 0x01;
        check(!decryptVec(key, early, buf) && buf.empty(), "stream: change in the first chunk fails and clears");
    }

    // the inflate checks behind an authentic tag
    const std::string data(8000, 'c');
    const std::string z = zlibOf(data);
    check(decryptVec(key, seal(key, data.size(), z, 2), buf) && str(buf) == data, "sealed round trip");
    check(!decryptVec(key, seal(key, data.size() - 1, z, 2), buf), "longer than declared fails");
    check(!decryptVec(key, seal(key, data.size() + 1, z, 2), buf), "shorter than declared fails");
    check(!decryptVec(key, seal(key, data.size(), z + "x", 2), buf), "bytes after the stream fail");
    check(!decryptVec(key, seal(key, data.size(), z.substr(0, z.size() - 1), 2), buf), "cut stream fails");
    check(!decryptVec(key, seal(key, data.size(), data, 2), buf), "not a zlib stream fails");
    check(!decryptVec(key, seal(key, data.size(), z, 1), buf), "version 1 is refused");
    check(!decryptVec(key, seal(key, 1ull << 40, z, 2), buf) && buf.empty(), "a huge declared length is refused");

    if (failures) {
        std::printf("%d check(s) failed\n", failures);
        return 1;
    }
    std::printf("chaospack_test: all checks passed\n");
    return 0;
}
