// Native vectors for the encrypted update blobs (src/framework/util/chaosblob.h, base patch 0103). Proves the engine's
// format is byte-identical to client/tools/update_crypt.py (the publisher): the fixed cross-language vector (the same
// bytes as make_update_manifest_test.py VECTOR_BLOB), round trip, wrong key, the pack key never opening a blob, tamper
// of every region, the streaming in-place Decryptor, CRC-32 and the store-only ZIP the engine mounts. Built standalone in
// CI (.github/workflows/ci.yml) with chaospack.h of base patch 0102 beside it:
//   g++ -std=c++17 -I "$d/src" client/tools/chaosblob_test.cpp -lcrypto -o chaosblob_test && chaosblob_test OUT.zip
// OUT.zip (optional) receives a small archive written by StoreZip; CI checks it with Python's zipfile (CRCs included).
#include <framework/util/chaosblob.h>

#include <cstdio>
#include <fstream>
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

int main(int argc, char** argv)
{
    std::string key;
    for (int i = 0; i < 32; ++i)
        key.push_back(static_cast<char>(i));
    const std::string encKey = chaosblob::deriveEncKey(key);
    check(encKey.size() == 32, "derived key");
    check(toHex(encKey) == "5d2c72977c987d801f2ba0061993cb45266f0cca28c917ae6e8e191c277a9368",
          "update key = HKDF with the update labels (same as update_crypt.py)");

    // the fixed vector of make_update_manifest_test.py (update_crypt.encrypt)
    const std::string plain = "Cinders of Chaos update blob";
    const std::string vector = fromHex(
        "434855420100000056081a63ae5ba02bfc8785411c00000000000000228f968fdbd0179714570604cf59bf2902453d372f5e93"
        "b3d523a2ffb9be36b66b2d2b9c1412c280daa56a5d");
    std::string out;
    check(chaosblob::decrypt(encKey, vector, out) && out == plain, "the Python vector decrypts");
    std::string mine;
    check(chaosblob::encrypt(key, plain, false, mine) && mine == vector, "encrypt is byte-identical to the Python tool");

    // round trip, determinism, sizes
    for (size_t n : { size_t(0), size_t(1), size_t(1000), size_t(70000) }) {
        std::string p(n, '\0');
        for (size_t i = 0; i < n; ++i)
            p[i] = static_cast<char>((i * 131 + 7) & 0xFF);
        std::string a, b, back;
        check(chaosblob::encrypt(key, p, false, a) && chaosblob::encrypt(key, p, false, b) && a == b, "deterministic");
        check(a.size() == n + chaosblob::OVERHEAD, "size = plaintext + 44");
        check(chaosblob::decrypt(encKey, a, back) && back == p, "round trip");
    }

    // wrong key; the pack's key never opens a blob (own HKDF labels)
    std::string other(32, '\x5a');
    check(!chaosblob::decrypt(chaosblob::deriveEncKey(other), vector, out) && out.empty(), "wrong key fails");
    std::string packEnc, packNonce;
    chaospack::deriveKeys(key, packEnc, packNonce);
    check(packEnc != encKey && !chaosblob::decrypt(packEnc, vector, out), "the pack key does not open a blob");
    std::string asPack;
    check(chaospack::encrypt(key, plain, false, asPack) && !chaosblob::decrypt(encKey, asPack, out), "a pack is not a blob");

    // tamper: flags, nonce, length, body, tag; a short blob
    std::string blob;
    chaosblob::encrypt(key, std::string(500, 'x'), false, blob);
    for (size_t at : { size_t(5), size_t(9), size_t(21), size_t(28), size_t(300), blob.size() - 1 }) {
        std::string bad = blob;
        bad[at] = static_cast<char>(bad[at] ^ 1);
        check(!chaosblob::decrypt(encKey, bad, out), "tampered byte fails");
    }
    check(!chaosblob::decrypt(encKey, blob.substr(0, blob.size() - 1), out), "truncated fails");

    // streaming, in place, in odd pieces (what updateBlobSha256 and mountUpdateOverlay do)
    {
        std::vector<unsigned char> buf(blob.begin(), blob.end());
        chaosblob::Header h;
        chaosblob::Decryptor d;
        check(d.begin(encKey, buf.data(), h) && h.plainLen == 500 && h.flags == 0, "header");
        unsigned char* body = buf.data() + chaosblob::HEADER_LEN;
        check(d.update(body, body, 7) && d.update(body + 7, body + 7, 493), "update in pieces");
        check(d.finish(buf.data() + buf.size() - chaosblob::TAG_LEN), "tag ok");
        check(std::string(reinterpret_cast<char*>(body), 500) == std::string(500, 'x'), "decrypted in place");
        chaosblob::Decryptor e;
        std::vector<unsigned char> buf2(blob.begin(), blob.end());
        buf2[100] ^= 0x10;
        e.begin(encKey, buf2.data(), h);
        unsigned char* b2 = buf2.data() + chaosblob::HEADER_LEN;
        check(e.update(b2, b2, 500) && !e.finish(buf2.data() + buf2.size() - chaosblob::TAG_LEN), "streamed tamper fails");
        chaosblob::Decryptor f;
        f.begin(encKey, buf.data(), h);
        check(!f.finish(buf.data() + buf.size() - chaosblob::TAG_LEN), "finish before the whole body fails");
    }
    std::string dev;
    chaosblob::encrypt(key, plain, true, dev);
    chaosblob::Header dh;
    check(chaosblob::parseHeader(reinterpret_cast<const unsigned char*>(dev.data()), dev.size(), dh) &&
              (dh.flags & chaosblob::FLAG_DEV),
          "dev flag");

    // CRC-32 check value and the ZIP writer
    const std::string nine = "123456789";
    check(chaosblob::crc32Update(reinterpret_cast<const unsigned char*>(nine.data()), nine.size()) == 0xCBF43926u,
          "crc32 check value");
    std::vector<std::pair<std::string, std::string>> files = {
        { "data/images/a b.png", std::string(3000, '\x89') }, { "modules/game_x/x.lua", "print(1)\n" },
        { "modules/game_x/empty.txt", "" }
    };
    std::vector<std::pair<std::string, uint64_t>> sizes;
    for (const auto& f : files)
        sizes.emplace_back(f.first, f.second.size());
    const uint64_t total = chaosblob::StoreZip::sizeFor(sizes);
    std::vector<uint8_t> zipBuf;
    zipBuf.reserve(static_cast<size_t>(total));
    const uint8_t* start = zipBuf.data();
    chaosblob::StoreZip zip;
    for (const auto& f : files) {
        const size_t at = zip.beginEntry(zipBuf, f.first, f.second.size());
        std::copy(f.second.begin(), f.second.end(), zipBuf.begin() + static_cast<std::ptrdiff_t>(at));
        zip.endEntry(zipBuf, chaosblob::crc32Update(zipBuf.data() + at, f.second.size()));
    }
    zip.finish(zipBuf);
    check(zipBuf.size() == total, "sizeFor is exact");
    check(zipBuf.data() == start, "the buffer never moved (one allocation)");
    check(chaosblob::StoreZip::fits(total, files.size()) && !chaosblob::StoreZip::fits(1ull << 32, 1), "fits");
    if (argc > 1) {
        std::ofstream o(argv[1], std::ios::binary);
        o.write(reinterpret_cast<const char*>(zipBuf.data()), static_cast<std::streamsize>(zipBuf.size()));
    }

    if (failures == 0)
        std::printf("chaosblob_test: ok\n");
    return failures == 0 ? 0 : 1;
}
