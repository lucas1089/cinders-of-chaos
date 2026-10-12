// Signature and hash test vectors of the signed updater's native part (src/framework/util/chaosupdate.h, added by
// client/base-patches/0031-signed-updater.patch). Build against an assembled client tree and OpenSSL:
//   g++ -std=c++17 -I <game-dir>/src client/tools/chaosupdate_test.cpp -lcrypto -o /tmp/chaosupdate_test && /tmp/chaosupdate_test
// The same manifest vector is checked in the running client by modules/client_chaos_updater/signature_vectors.lua.
#include <framework/util/chaosupdate.h>

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
    chaosupdate::hexToBytes(hex, out);
    return out;
}

int main()
{
    // RFC 8032 section 7.1, tests 1-3
    struct Vector { const char* pk; const char* msg; const char* sig; } rfc[] = {
        { "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
          "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b" },
        { "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
          "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00" },
        { "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
          "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a" },
    };
    for (const auto& v : rfc) {
        const std::string msg = bytes(v.msg);
        check(chaosupdate::ed25519Verify(v.pk, msg, v.sig), "RFC 8032 vector verifies");
        check(!chaosupdate::ed25519Verify(v.pk, msg + "x", v.sig), "changed message refused");
        std::string sig = v.sig;
        sig[10] = sig[10] == '0' ? '1' : '0';
        check(!chaosupdate::ed25519Verify(v.pk, msg, sig), "changed signature refused");
    }
    check(!chaosupdate::ed25519Verify(rfc[1].pk, bytes(rfc[0].msg), rfc[0].sig), "other key refused");

    // a manifest payload signed by client/tools/make_update_manifest.py with the RFC 8032 test 1 key
    const std::string payload =
        "{\"channel\":\"live\",\"created\":\"2026-10-10T00:00:00Z\",\"files\":[{\"path\":\"modules/game_a/a.lua\","
        "\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\",\"size\":3}],"
        "\"files_url\":\"files/\",\"format\":1,\"min_package\":0,\"min_version\":0,\"parallel\":4,"
        "\"product\":\"cinders-of-chaos\",\"version\":1}";
    const char* payloadSig =
        "d337bacbfcba1dbb7ba21f567099078f295b587f876d1cd1a82a401dfde31d465b0a7ad4ac277b6cda5026644ae061d88b8ecf882637a279c82d5c73eac88601";
    check(chaosupdate::ed25519Verify(rfc[0].pk, payload, payloadSig), "manifest vector verifies");
    std::string tampered = payload;
    tampered.replace(tampered.find("\"version\":1"), 11, "\"version\":2");
    check(!chaosupdate::ed25519Verify(rfc[0].pk, tampered, payloadSig), "tampered manifest refused");

    // malformed input is a failed check, not a crash
    check(!chaosupdate::ed25519Verify("", payload, payloadSig), "empty key");
    check(!chaosupdate::ed25519Verify(std::string(64, 'z'), payload, payloadSig), "non-hex key");
    check(!chaosupdate::ed25519Verify(rfc[0].pk, payload, ""), "empty signature");
    check(!chaosupdate::ed25519Verify(rfc[0].pk, payload, std::string(payloadSig).substr(0, 126)), "short signature");
    check(!chaosupdate::ed25519Verify(rfc[0].pk, payload, std::string(128, '0')), "zero signature");

    // SHA-256 (FIPS 180-2 examples)
    check(chaosupdate::sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc");
    check(chaosupdate::sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 empty");
    chaosupdate::Sha256Stream s;
    s.update("ab", 2);
    s.update("c", 1);
    check(s.finishHex() == chaosupdate::sha256Hex("abc"), "sha256 in parts");

    // write-dir paths of the updater
    check(chaosupdate::isSafeUpdatePath("chaos_update/files/data/fonts/Verdana Bold-11px.png"), "space allowed");
    check(chaosupdate::isSafeUpdatePath("chaos_update/files/data/minimap/63-(1-2-7)a.png"), "parentheses allowed");
    const char* bad[] = { "", "/chaos_update/x", "chaos_update/../x", "chaos_update//x", "chaos_update/./x",
                          "chaos_update/x/", "chaos_update\\x", "C:/x", "chaos_update/ x", "chaos_update/x.",
                          "chaos_update/x$" };
    for (const char* p : bad)
        check(!chaosupdate::isSafeUpdatePath(p), p);

    std::printf("chaosupdate_test: %d checks, %s\n", checks, fails ? "FAILED" : "OK");
    return fails ? 1 : 0;
}
