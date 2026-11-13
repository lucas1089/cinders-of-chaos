// The platform half of the start ticket (src/client/chaoslauncher.h, client base patch 0198), on a system that is not Windows:
// requireOrExit() with a good, a missing, an old and a wrong ticket, the variable removed afterwards, prepareRestart() giving the
// next process a ticket the same rules accept. The Windows branch (message box, starting the launcher) is not compiled here.
// Build: cut chaosguard.h, chaosguard_builtin.h (base patch 0035), chaosticket.h and chaoslauncher.h (0198) out of the patches
// (the ci.yml step does), then
//   g++ -std=c++17 -Wall -Wextra -DCHAOS_CLIENT_BUILD=47 -I $d -I client/tools/chaoslauncher_test_key
//       client/tools/chaoslauncher_test.cpp -lcrypto
#include "chaoslauncher.h"

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

int main()
{
    std::string key = chaosguard::builtInKey();
    check(key == std::string(32, '\x11'), "the stub key is the test key");
    const uint64_t now = static_cast<uint64_t>(std::time(nullptr));
    const std::string nonce = "00112233445566778899aabbccddeeff";

    chaoslauncher::setEnv(chaosticket::ENV_NAME, chaosticket::mint(key, 47, 200, now + 30, nonce));
    check(chaoslauncher::requireOrExit(), "a good ticket lets the game start");
    check(chaoslauncher::launcherBuild() == 200, "the launcher number is kept");
    check(chaoslauncher::getEnv(chaosticket::ENV_NAME).empty(), "the variable is removed, children do not inherit it");

    check(!chaoslauncher::requireOrExit(), "no ticket: the game does not start");

    chaoslauncher::setEnv(chaosticket::ENV_NAME, chaosticket::mint(key, 47, 200, now - 5, nonce));
    check(!chaoslauncher::requireOrExit(), "an old ticket is refused");
    check(chaoslauncher::getEnv(chaosticket::ENV_NAME).empty(), "and removed");

    chaoslauncher::setEnv(chaosticket::ENV_NAME, chaosticket::mint(key, 48, 200, now + 30, nonce));
    check(!chaoslauncher::requireOrExit(), "a ticket for another build is refused");

    chaoslauncher::setEnv(chaosticket::ENV_NAME, chaosticket::mint(std::string(32, '\x22'), 47, 200, now + 30, nonce));
    check(!chaoslauncher::requireOrExit(), "a ticket of another key is refused");

    chaoslauncher::setEnv(chaosticket::ENV_NAME, "garbage");
    check(!chaoslauncher::requireOrExit(), "garbage is refused");

    // the restart: the new process gets a ticket of its own with the same launcher number
    chaoslauncher::setEnv(chaosticket::ENV_NAME, chaosticket::mint(key, 47, 200, now + 30, nonce));
    check(chaoslauncher::requireOrExit(), "the first run starts");
    chaoslauncher::prepareRestart();
    const std::string next = chaoslauncher::getEnv(chaosticket::ENV_NAME);
    chaosticket::Ticket t;
    check(chaosticket::verify(key, next, now, 47, &t) == chaosticket::Verdict::Ok, "the restart ticket verifies");
    check(t.launcher == 200, "with the launcher number of this run");
    check(t.expiry >= now + chaosticket::RESTART_LIFETIME - 2 && t.expiry <= now + chaosticket::RESTART_LIFETIME + 5,
          "for a minute");
    check(chaoslauncher::requireOrExit(), "and the restarted game starts from it");

    chaosguard::wipe(key);
    std::printf("chaoslauncher_test: %d checks, %d failures\n", checks, fails);
    return fails ? 1 : 0;
}
