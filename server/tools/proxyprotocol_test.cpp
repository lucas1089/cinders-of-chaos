// Unit test of the PROXY protocol parser and the trusted-address rules of engine patch 0025
// (server/src-patches/0025-proxy-protocol.patch, src/proxyprotocol.cpp). CI takes proxyprotocol.cpp / .h out of the
// patch and builds them with the stand-in headers in server/tools/proxyprotocol_stubs/:
//   g++ -std=c++17 -I server/tools/proxyprotocol_stubs -I DIR/src DIR/src/proxyprotocol.cpp
//       server/tools/proxyprotocol_test.cpp -o proxyprotocol_test   (then run it; exit status 0 = every check passed)
#include "configmanager.h"
#include "tools.h"
#include "proxyprotocol.h"
#include <cstring>
#include <iostream>
#include <vector>
ConfigManager g_config;
using namespace ProxyProtocol;
static int fails = 0;
#define CHECK(c) do { if (!(c)) { std::cout << "FAIL line " << __LINE__ << ": " #c << std::endl; ++fails; } } while (0)
// feed like the connection does: read `need` bytes at a time from the stream
static Parse feed(const std::vector<uint8_t>& s, Header& h, size_t& consumed) {
  size_t have = FIRST_READ; Parse p;
  for (int i = 0; i < 200; ++i) {
    if (have > s.size()) { consumed = 0; return Parse::NeedMore; }
    p = parse(s.data(), have, h);
    if (p != Parse::NeedMore) { consumed = have; return p; }
    if (h.need <= have || h.need > MAX_HEADER) return Parse::Invalid;
    have = h.need;
  }
  return Parse::Invalid;
}
static std::vector<uint8_t> str(const std::string& x) { return std::vector<uint8_t>(x.begin(), x.end()); }
static uint32_t ip(int a,int b,int c,int d){ uint8_t x[4]={uint8_t(a),uint8_t(b),uint8_t(c),uint8_t(d)}; uint32_t r; memcpy(&r,x,4); return r; }
static std::vector<uint8_t> v2(uint8_t cmd, uint8_t fam, std::vector<uint8_t> payload) {
  std::vector<uint8_t> v = {0x0D,0x0A,0x0D,0x0A,0x00,0x0D,0x0A,0x51,0x55,0x49,0x54,0x0A, uint8_t(0x20|cmd), fam, uint8_t(payload.size()>>8), uint8_t(payload.size()&0xFF)};
  v.insert(v.end(), payload.begin(), payload.end()); return v;
}
int main() {
  Header h; size_t used;
  // v1 TCP4, followed by game bytes that must not be consumed
  auto s = str("PROXY TCP4 203.0.113.7 10.0.0.5 51234 7172\r\n"); size_t hl = s.size(); s.push_back(0x99); s.push_back(0x00);
  CHECK(feed(s, h, used) == Parse::Ok); CHECK(used == hl); CHECK(h.ip == ip(203,0,113,7)); CHECK(h.port == 51234); CHECK(!h.local);
  // v1 UNKNOWN (15 bytes) not over-read
  s = str("PROXY UNKNOWN\r\nX"); CHECK(feed(s, h, used) == Parse::Ok); CHECK(used == 15); CHECK(h.local);
  // v1 TCP6 mapped and plain v6
  s = str("PROXY TCP6 ::ffff:198.51.100.9 ::ffff:10.0.0.5 4000 7171\r\n"); CHECK(feed(s, h, used) == Parse::Ok); CHECK(h.ip == ip(198,51,100,9));
  s = str("PROXY TCP6 2001:db8::1 2001:db8::2 4000 7171\r\n"); CHECK(feed(s, h, used) == Parse::Invalid);
  // v1 malformed
  for (const char* bad : {"PROXY TCP4 1.2.3 1.2.3.4 1 2\r\n", "PROXY TCP4 1.2.3.400 1.2.3.4 1 2\r\n", "PROXY TCP4 1.2.3.4 1.2.3.4 99999 2\r\n",
                          "PROXY TCP4 1.2.3.4/8 1.2.3.4 1 2\r\n", "PROXY TCP4 1.2.3.4\r\n", "PROXY TCP4 1.2.3.4 1.2.3.4 1 2\rX", "PROXY TCP4 0.0.0.0 1.2.3.4 1 2\r\n"}) {
    s = str(bad); CHECK(feed(s, h, used) == Parse::Invalid);
  }
  s = str("PROXY " + std::string(150, 'A')); CHECK(feed(s, h, used) == Parse::Invalid);
  // v2 PROXY TCP4 + trailing data
  s = v2(1, 0x11, {192,0,2,44, 10,0,0,5, 0x1F,0x90, 0x1C,0x04}); hl = s.size(); s.push_back(0x55);
  CHECK(feed(s, h, used) == Parse::Ok); CHECK(used == hl); CHECK(h.ip == ip(192,0,2,44)); CHECK(h.port == 8080);
  // v2 with TLVs after the addresses
  { std::vector<uint8_t> p = {192,0,2,45, 10,0,0,5, 0,1, 0,2, 0x04, 0x00, 0x03, 'a','b','c'}; s = v2(1, 0x11, p); CHECK(feed(s, h, used) == Parse::Ok); CHECK(used == s.size()); CHECK(h.ip == ip(192,0,2,45)); }
  // v2 LOCAL (health check)
  s = v2(0, 0x00, {}); CHECK(feed(s, h, used) == Parse::Ok); CHECK(h.local); CHECK(used == 16);
  // v2 TCP6 mapped / not mapped
  { std::vector<uint8_t> p(36, 0); p[10]=p[11]=0xFF; p[12]=198; p[13]=51; p[14]=100; p[15]=1; p[32]=0x12; p[33]=0x34;
    s = v2(1, 0x21, p); CHECK(feed(s, h, used) == Parse::Ok); CHECK(h.ip == ip(198,51,100,1)); CHECK(h.port == 0x1234);
    p[10] = 0; s = v2(1, 0x21, p); CHECK(feed(s, h, used) == Parse::Invalid); }
  // v2 bad version / command / family / short / too long
  s = v2(1, 0x11, {1,2,3,4,5,6,7,8,9,10,11,12}); s[12] = 0x11; CHECK(feed(s, h, used) == Parse::Invalid);
  s = v2(2, 0x11, {1,2,3,4,5,6,7,8,9,10,11,12}); CHECK(feed(s, h, used) == Parse::Invalid);
  s = v2(1, 0x31, std::vector<uint8_t>(216, 1)); CHECK(feed(s, h, used) == Parse::Invalid);
  s = v2(1, 0x11, {1,2,3,4}); CHECK(feed(s, h, used) == Parse::Invalid);
  s = v2(1, 0x11, std::vector<uint8_t>(600, 1)); CHECK(feed(s, h, used) == Parse::Invalid);
  s = v2(1, 0x11, {1,2,3,4,5,6,7,8,9,10,11,12}); s[11] = 0; CHECK(feed(s, h, used) == Parse::Invalid);
  // not a header: a Tibia login packet
  s = {0x95,0x00, 1,2,3,4, 0x01, 0x0A, 0x00, 0x4A}; CHECK(feed(s, h, used) == Parse::Invalid);
  // looksLikeHeader
  uint8_t a[2] = {0x0D,0x0A}, b[2] = {'P','R'}, c[2] = {0x95,0x00}; CHECK(looksLikeHeader(a)); CHECK(looksLikeHeader(b)); CHECK(!looksLikeHeader(c));
  // trusted list, CIDR, bad entries, loopback, required
  g_config.trusted = "203.0.113.10, 198.51.100.0/24 bogus 10.1.2.3/40";
  CHECK(classify(ip(203,0,113,10)) == Peer::Gateway); CHECK(classify(ip(198,51,100,77)) == Peer::Gateway);
  CHECK(classify(ip(203,0,113,11)) == Peer::Direct); CHECK(classify(ip(10,1,2,3)) == Peer::Direct);
  g_config.required = true;
  CHECK(classify(ip(203,0,113,11)) == Peer::Refused); CHECK(classify(ip(127,0,0,1)) == Peer::Direct); CHECK(classify(ip(198,51,100,1)) == Peer::Gateway);
  startupReport();
  g_config.trusted = ""; CHECK(classify(ip(203,0,113,10)) == Peer::Refused); startupReport();
  g_config.required = false; CHECK(classify(ip(203,0,113,10)) == Peer::Direct); startupReport();
  g_config.trusted = "0.0.0.0/0"; CHECK(classify(ip(8,8,8,8)) == Peer::Gateway);
  logRefused("test", ip(1,2,3,4)); logRefused("test", ip(1,2,3,4)); logRefused("other", ip(5,6,7,8), "why");
  std::cout << (fails ? "FAILED " : "ok ") << fails << std::endl;
  return fails != 0;
}
