// PhysFS mounts the update overlay the way base patch 0103 does (ResourceManager::mountUpdateOverlay): blobs are
// decrypted in place into one StoreZip buffer, mounted from memory at "/" in FRONT of a folder that stands for the pack,
// and the overlay's files win; the pack's other files stay visible; after unmounting the pack's own file is back.
// Built in CI (.github/workflows/ci.yml) with chaospack.h (0102) and chaosblob.h (0103):
//   g++ -std=c++17 -I "$d/src" client/tools/chaosblob_mount_test.cpp -lcrypto -lphysfs -o t && t PACK_DIR
// PACK_DIR must hold modules/game_x/x.lua ("print(\"pack\")\n") and modules/game_x/other.lua.
#include <framework/util/chaosblob.h>

#include <physfs.h>

#include <cstdio>
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

static std::string readAll(const char* path)
{
    PHYSFS_File* f = PHYSFS_openRead(path);
    if (!f)
        return "<missing>";
    std::string s(static_cast<size_t>(PHYSFS_fileLength(f)), '\0');
    if (!s.empty())
        PHYSFS_readBytes(f, &s[0], s.size());
    PHYSFS_close(f);
    return s;
}

int main(int argc, char** argv)
{
    if (argc < 2 || !PHYSFS_init(argv[0]))
        return 2;
    const std::string key(32, '\x42');
    const std::string encKey = chaosblob::deriveEncKey(key);
    const std::vector<std::pair<std::string, std::string>> files = {
        { "data/images/new.png", std::string(5000, '\x89') }, { "modules/game_x/x.lua", "print(\"update\")\n" }
    };
    std::vector<std::string> blobs;
    std::vector<std::pair<std::string, uint64_t>> sizes;
    for (const auto& f : files) {
        std::string b;
        check(chaosblob::encrypt(key, f.second, false, b), "encrypt");
        blobs.push_back(b);
        sizes.emplace_back(f.first, f.second.size());
    }
    // the engine's loop: header, body read into its slot, decrypted in place, tag, CRC
    std::vector<uint8_t> data;
    data.reserve(static_cast<size_t>(chaosblob::StoreZip::sizeFor(sizes)));
    chaosblob::StoreZip zip;
    for (size_t i = 0; i < files.size(); ++i) {
        const auto* b = reinterpret_cast<const unsigned char*>(blobs[i].data());
        chaosblob::Header h;
        chaosblob::Decryptor d;
        check(d.begin(encKey, b, h), "begin");
        const size_t at = zip.beginEntry(data, files[i].first, h.plainLen);
        unsigned char* p = data.data() + at;
        std::copy(b + chaosblob::HEADER_LEN, b + chaosblob::HEADER_LEN + h.plainLen, p);
        check(d.update(p, p, h.plainLen) && d.finish(b + blobs[i].size() - chaosblob::TAG_LEN), "decrypt in place");
        zip.endEntry(data, chaosblob::crc32Update(p, h.plainLen));
    }
    zip.finish(data);

    check(PHYSFS_mount(argv[1], "/", 1) != 0, "the pack folder mounts");
    check(readAll("/modules/game_x/x.lua") == "print(\"pack\")\n", "before: the pack's file");
    check(PHYSFS_mountMemory(data.data(), data.size(), nullptr, "chaos_update_overlay.zip", "/", 0) != 0,
          "the overlay mounts from memory");
    check(readAll("/modules/game_x/x.lua") == "print(\"update\")\n", "the update's file wins");
    check(readAll("/data/images/new.png") == files[0].second, "a new file of the update");
    check(readAll("/modules/game_x/other.lua") != "<missing>", "the pack's other files stay visible");
    check(std::string(PHYSFS_getRealDir("/modules/game_x/x.lua")) == "chaos_update_overlay.zip", "real dir");
    check(PHYSFS_unmount("chaos_update_overlay.zip") != 0, "unmount");
    check(readAll("/modules/game_x/x.lua") == "print(\"pack\")\n", "after: the pack's file again");
    PHYSFS_deinit();
    if (failures == 0)
        std::printf("chaosblob_mount_test: ok\n");
    return failures == 0 ? 0 : 1;
}
