// Offline benchmark of the spectator queries (patch 0071, server/README.md "Cheaper spectator queries (O212)").
//   g++ -std=c++17 -O2 -I DIR server/tools/spectator_bench.cpp -o spectator_bench   (DIR holds chaosspectators.h, see chaosspectators_test.cpp)
//   spectator_bench [--seconds N] [--check]
// The world copies the engine's: Position, creatures in the creature_list / player_list of 8x8 QTree leaves
// (QTreeNode::getLeafStatic, the leafS / leafE links, FLOOR_SIZE 8), and Map::getSpectators / getSpectatorsInternal /
// moveCreature as in the fork's map.cpp (maxViewportX 16, maxViewportY 12, the same cache rules: a lookup for the default
// range of a multifloor query, cleared by every creature added to or removed from a tile, the players cache only for a
// player). It is one template, run twice: with the stock pieces (the unchanged SpectatorVec with its reserve(32), a
// std::map<Position, SpectatorVec> cache, a std::vector of stack positions) and with the new ones of chaosspectators.h
// (SpectatorList, Cache, SmallVec). The walk and the cache rules are the same code for both; only the pieces differ.
// What it times: queries per second of a hunting pack (40 monsters and 5 players in one screen: steps, a spell, effects)
// and of a city (100 players), the heap allocations (global operator new counted) and the answers (--check, the CI mode: both
// worlds run the same random operations and every query, step union and cache hit must return the same creatures in the
// same order; exit 1 on any difference).
// What it does not have: the engine's other costs around a query (the tile, the packets, the Lua events): the numbers are
// the share of the spectator code, not of a server tick. See the README for how that share was estimated.
#include "chaosspectators.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <new>
#include <random>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;

// ---------------------------------------------------------------------------------------------------- allocation count
static size_t g_allocs = 0;
void* operator new(size_t n) { ++g_allocs; void* p = std::malloc(n ? n : 1); if (!p) { throw std::bad_alloc(); } return p; }
void* operator new[](size_t n) { ++g_allocs; void* p = std::malloc(n ? n : 1); if (!p) { throw std::bad_alloc(); } return p; }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, size_t) noexcept { std::free(p); }
void operator delete[](void* p, size_t) noexcept { std::free(p); }

// ---------------------------------------------------------------------------------------------------- engine copies
struct Position {
	constexpr Position() = default;
	constexpr Position(uint16_t x, uint16_t y, uint8_t z) : x(x), y(y), z(z) {}
	static int_fast16_t getOffsetZ(const Position& p1, const Position& p2) { return p1.z - p2.z; }
	uint16_t x = 0;
	uint16_t y = 0;
	uint8_t z = 0;
	bool operator<(const Position& p) const {
		if (z != p.z) { return z < p.z; }
		if (y != p.y) { return y < p.y; }
		return x < p.x;
	}
};

struct Creature {
	Position pos;
	bool player = false;
	uint32_t id = 0;
	const Position& getPosition() const { return pos; }
	Creature* getPlayer() { return player ? this : nullptr; }
};

static constexpr int32_t FLOOR_BITS = 3;
static constexpr int32_t FLOOR_SIZE = (1 << FLOOR_BITS);
static constexpr int32_t MAP_MAX_LAYERS = 16;
static constexpr int32_t maxClientViewportX = 14;
static constexpr int32_t maxClientViewportY = 10;
static constexpr int32_t maxViewportX = maxClientViewportX + 2;
static constexpr int32_t maxViewportY = maxClientViewportY + 2;

using CreatureVector = std::vector<Creature*>;

class QTreeLeafNode;
class QTreeNode
{
	public:
		virtual ~QTreeNode() { for (auto* ptr : child) { delete ptr; } }
		bool isLeaf() const { return leaf; }
		QTreeLeafNode* getLeaf(uint32_t x, uint32_t y);
		template<typename Leaf, typename Node>
		static Leaf getLeafStatic(Node node, uint32_t x, uint32_t y) {
			do {
				node = node->child[((x & 0x8000) >> 15) | ((y & 0x8000) >> 14)];
				if (!node) { return nullptr; }
				x <<= 1;
				y <<= 1;
			} while (!node->leaf);
			return static_cast<Leaf>(node);
		}
		QTreeLeafNode* createLeaf(uint32_t x, uint32_t y, uint32_t level);
		bool leaf = false;
		QTreeNode* child[4] = {};
};

class QTreeLeafNode final : public QTreeNode
{
	public:
		QTreeLeafNode() { leaf = true; newLeaf = true; }
		void addCreature(Creature* c) {
			creature_list.push_back(c);
			if (c->getPlayer()) { player_list.push_back(c); }
		}
		void removeCreature(Creature* c) {
			auto iter = std::find(creature_list.begin(), creature_list.end(), c);
			*iter = creature_list.back();
			creature_list.pop_back();
			if (c->getPlayer()) {
				iter = std::find(player_list.begin(), player_list.end(), c);
				*iter = player_list.back();
				player_list.pop_back();
			}
		}
		static bool newLeaf;
		QTreeLeafNode* leafS = nullptr;
		QTreeLeafNode* leafE = nullptr;
		CreatureVector creature_list;
		CreatureVector player_list;
};
bool QTreeLeafNode::newLeaf = false;

QTreeLeafNode* QTreeNode::getLeaf(uint32_t x, uint32_t y)
{
	if (leaf) { return static_cast<QTreeLeafNode*>(this); }
	QTreeNode* node = child[((x & 0x8000) >> 15) | ((y & 0x8000) >> 14)];
	if (!node) { return nullptr; }
	return node->getLeaf(x << 1, y << 1);
}

QTreeLeafNode* QTreeNode::createLeaf(uint32_t x, uint32_t y, uint32_t level)
{
	if (!isLeaf()) {
		uint32_t index = ((x & 0x8000) >> 15) | ((y & 0x8000) >> 14);
		if (!child[index]) {
			if (level != FLOOR_BITS) { child[index] = new QTreeNode(); }
			else { child[index] = new QTreeLeafNode(); QTreeLeafNode::newLeaf = true; }
		}
		return child[index]->createLeaf(x * 2, y * 2, level - 1);
	}
	return static_cast<QTreeLeafNode*>(this);
}

// ---------------------------------------------------------------------------------------------------- stock pieces
namespace Stock {
// spectators.h of the fork, as it is (its reserve(32) included)
class SpectatorVec
{
	using Vec = std::vector<Creature*>;
	using Iterator = Vec::iterator;
	using ConstIterator = Vec::const_iterator;
public:
	SpectatorVec() { vec.reserve(32); }
	void addSpectators(const SpectatorVec& spectators) {
		for (Creature* spectator : spectators.vec) {
			auto it = std::find(vec.begin(), vec.end(), spectator);
			if (it != end()) { continue; }
			vec.emplace_back(spectator);
		}
	}
	void erase(Creature* spectator) {
		auto it = std::find(vec.begin(), vec.end(), spectator);
		if (it == end()) { return; }
		std::iter_swap(it, end() - 1);
		vec.pop_back();
	}
	size_t size() const { return vec.size(); }
	bool empty() const { return vec.empty(); }
	Iterator begin() { return vec.begin(); }
	ConstIterator begin() const { return vec.begin(); }
	Iterator end() { return vec.end(); }
	ConstIterator end() const { return vec.end(); }
	void emplace_back(Creature* c) { vec.emplace_back(c); }
private:
	Vec vec;
};

struct Cache {
	std::map<Position, SpectatorVec> m;
	const SpectatorVec* find(const Position& p) const { auto it = m.find(p); return it == m.end() ? nullptr : &it->second; }
	SpectatorVec& store(const Position& p) { return m[p]; }
	void clear() { m.clear(); }
};

using StackVec = std::vector<int32_t>;
}

namespace New {
using SpectatorVec = ChaosSpec::SpectatorList<Creature>;

struct Cache {
	ChaosSpec::Cache<SpectatorVec> c;
	const SpectatorVec* find(const Position& p) const { return c.find(ChaosSpec::posKey(p.x, p.y, p.z)); }
	SpectatorVec& store(const Position& p) { return c.store(ChaosSpec::posKey(p.x, p.y, p.z)); }
	void clear() { c.clear(); }
};

using StackVec = ChaosSpec::SmallVec<int32_t, 48>;
}

// ---------------------------------------------------------------------------------------------------- the map
// Map::getSpectators and friends of the fork's map.cpp, over the pieces of P
template<typename P>
class World
{
	public:
		using SpectatorVec = typename P::SpectatorVec;

		World() = default;
		World(const World&) = delete;

		void addLeaf(uint16_t x, uint16_t y) {
			QTreeLeafNode::newLeaf = false;
			QTreeLeafNode* leaf = root.createLeaf(x, y, 15);
			if (QTreeLeafNode::newLeaf) {
				QTreeLeafNode* northLeaf = root.getLeaf(x, y - FLOOR_SIZE);
				if (northLeaf) { northLeaf->leafS = leaf; }
				QTreeLeafNode* westLeaf = root.getLeaf(x - FLOOR_SIZE, y);
				if (westLeaf) { westLeaf->leafE = leaf; }
				QTreeLeafNode* southLeaf = root.getLeaf(x, y + FLOOR_SIZE);
				if (southLeaf) { leaf->leafS = southLeaf; }
				QTreeLeafNode* eastLeaf = root.getLeaf(x + FLOOR_SIZE, y);
				if (eastLeaf) { leaf->leafE = eastLeaf; }
			}
		}

		QTreeLeafNode* getQTNode(uint16_t x, uint16_t y) { return QTreeNode::getLeafStatic<QTreeLeafNode*, QTreeNode*>(&root, x, y); }

		void place(Creature* c) {
			clearCaches(c);
			getQTNode(c->pos.x, c->pos.y)->addCreature(c);
		}

		// Tile::addThing / removeThing: the caches are cleared, the players one only for a player
		void clearCaches(Creature* c) {
			spectatorCache.clear();
			if (c->getPlayer()) { playersSpectatorCache.clear(); }
		}

		// Map::moveCreature without the tile and the packets: the queries, the union, the stack positions, the cache clears
		uint64_t moveCreature(Creature& creature, const Position& newPos) {
			Position oldPos = creature.pos;
			SpectatorVec spectators, newPosSpectators;
			getSpectators(spectators, oldPos, true);
			getSpectators(newPosSpectators, newPos, true);
			spectators.addSpectators(newPosSpectators);

			typename P::StackVec oldStackPosVector;
			for (Creature* spectator : spectators) {
				if (Creature* tmpPlayer = spectator->getPlayer()) {
					oldStackPosVector.push_back(tmpPlayer->id != creature.id ? int32_t(tmpPlayer->id & 7) : -1);
				}
			}

			clearCaches(&creature); // oldTile.removeThing

			QTreeLeafNode* leaf = getQTNode(oldPos.x, oldPos.y);
			QTreeLeafNode* new_leaf = getQTNode(newPos.x, newPos.y);
			if (leaf != new_leaf) {
				leaf->removeCreature(&creature);
				new_leaf->addCreature(&creature);
			}
			creature.pos = newPos;
			clearCaches(&creature); // newTile.addThing

			uint64_t sum = 0;
			size_t i = 0;
			for (Creature* spectator : spectators) {
				if (Creature* tmpPlayer = spectator->getPlayer()) {
					sum += uint64_t(oldStackPosVector[i++]) + tmpPlayer->id;
				}
			}
			for (Creature* spectator : spectators) { sum += spectator->pos.x; }
			return sum;
		}

		void getSpectatorsInternal(SpectatorVec& spectators, const Position& centerPos, int32_t minRangeX, int32_t maxRangeX, int32_t minRangeY, int32_t maxRangeY, int32_t minRangeZ, int32_t maxRangeZ, bool onlyPlayers) const {
			auto min_y = centerPos.y + minRangeY;
			auto min_x = centerPos.x + minRangeX;
			auto max_y = centerPos.y + maxRangeY;
			auto max_x = centerPos.x + maxRangeX;

			int32_t minoffset = centerPos.z - maxRangeZ;
			uint16_t x1 = std::min<uint32_t>(0xFFFF, std::max<int32_t>(0, (min_x + minoffset)));
			uint16_t y1 = std::min<uint32_t>(0xFFFF, std::max<int32_t>(0, (min_y + minoffset)));

			int32_t maxoffset = centerPos.z - minRangeZ;
			uint16_t x2 = std::min<uint32_t>(0xFFFF, std::max<int32_t>(0, (max_x + maxoffset)));
			uint16_t y2 = std::min<uint32_t>(0xFFFF, std::max<int32_t>(0, (max_y + maxoffset)));

			int32_t startx1 = x1 - (x1 % FLOOR_SIZE);
			int32_t starty1 = y1 - (y1 % FLOOR_SIZE);
			int32_t endx2 = x2 - (x2 % FLOOR_SIZE);
			int32_t endy2 = y2 - (y2 % FLOOR_SIZE);

			const QTreeLeafNode* startLeaf = QTreeNode::getLeafStatic<const QTreeLeafNode*, const QTreeNode*>(&root, startx1, starty1);
			const QTreeLeafNode* leafS = startLeaf;
			const QTreeLeafNode* leafE;

			for (int_fast32_t ny = starty1; ny <= endy2; ny += FLOOR_SIZE) {
				leafE = leafS;
				for (int_fast32_t nx = startx1; nx <= endx2; nx += FLOOR_SIZE) {
					if (leafE) {
						const CreatureVector& node_list = (onlyPlayers ? leafE->player_list : leafE->creature_list);
						for (Creature* creature : node_list) {
							const Position& cpos = creature->getPosition();
							if (minRangeZ > cpos.z || maxRangeZ < cpos.z) { continue; }
							int_fast16_t offsetZ = Position::getOffsetZ(centerPos, cpos);
							if ((min_y + offsetZ) > cpos.y || (max_y + offsetZ) < cpos.y || (min_x + offsetZ) > cpos.x || (max_x + offsetZ) < cpos.x) { continue; }
							spectators.emplace_back(creature);
						}
						leafE = leafE->leafE;
					} else {
						leafE = QTreeNode::getLeafStatic<const QTreeLeafNode*, const QTreeNode*>(&root, nx + FLOOR_SIZE, ny);
					}
				}
				if (leafS) { leafS = leafS->leafS; }
				else { leafS = QTreeNode::getLeafStatic<const QTreeLeafNode*, const QTreeNode*>(&root, startx1, ny + FLOOR_SIZE); }
			}
		}

		void getSpectators(SpectatorVec& spectators, const Position& centerPos, bool multifloor = false, bool onlyPlayers = false,
		                   int32_t minRangeX = 0, int32_t maxRangeX = 0, int32_t minRangeY = 0, int32_t maxRangeY = 0) {
			++queries;
			if (centerPos.z >= MAP_MAX_LAYERS) { return; }

			bool foundCache = false;
			bool cacheResult = false;

			minRangeX = (minRangeX == 0 ? -maxViewportX : -minRangeX);
			maxRangeX = (maxRangeX == 0 ? maxViewportX : maxRangeX);
			minRangeY = (minRangeY == 0 ? -maxViewportY : -minRangeY);
			maxRangeY = (maxRangeY == 0 ? maxViewportY : maxRangeY);

			if (minRangeX == -maxViewportX && maxRangeX == maxViewportX && minRangeY == -maxViewportY && maxRangeY == maxViewportY && multifloor) {
				if (onlyPlayers) {
					const SpectatorVec* cached = playersSpectatorCache.find(centerPos);
					if (cached) {
						if (!spectators.empty()) { spectators.addSpectators(*cached); }
						else { spectators = *cached; }
						foundCache = true;
					}
				}

				if (!foundCache) {
					const SpectatorVec* cached = spectatorCache.find(centerPos);
					if (cached) {
						if (!onlyPlayers) {
							if (!spectators.empty()) { spectators.addSpectators(*cached); }
							else { spectators = *cached; }
						} else {
							const SpectatorVec& cachedSpectators = *cached;
							for (Creature* spectator : cachedSpectators) {
								if (spectator->getPlayer()) { spectators.emplace_back(spectator); }
							}
						}
						foundCache = true;
					} else {
						cacheResult = true;
					}
				}
			}

			if (!foundCache) {
				int32_t minRangeZ;
				int32_t maxRangeZ;
				if (multifloor) {
					if (centerPos.z > 7) {
						minRangeZ = std::max<int32_t>(centerPos.z - 2, 0);
						maxRangeZ = std::min<int32_t>(centerPos.z + 2, MAP_MAX_LAYERS - 1);
					} else if (centerPos.z == 6) {
						minRangeZ = 0;
						maxRangeZ = 8;
					} else if (centerPos.z == 7) {
						minRangeZ = 0;
						maxRangeZ = 9;
					} else {
						minRangeZ = 0;
						maxRangeZ = 7;
					}
				} else {
					minRangeZ = centerPos.z;
					maxRangeZ = centerPos.z;
				}

				getSpectatorsInternal(spectators, centerPos, minRangeX, maxRangeX, minRangeY, maxRangeY, minRangeZ, maxRangeZ, onlyPlayers);

				if (cacheResult) {
					if (onlyPlayers) { playersSpectatorCache.store(centerPos) = spectators; }
					else { spectatorCache.store(centerPos) = spectators; }
				}
			}
		}

		// Game::addMagicEffect(pos, effect)
		uint64_t addMagicEffect(const Position& pos) {
			SpectatorVec spectators;
			getSpectators(spectators, pos, true, true);
			uint64_t sum = 0;
			for (Creature* s : spectators) { if (s->getPlayer()) { sum += s->id; } }
			return sum;
		}

		// Game::addDistanceEffect(fromPos, toPos, effect)
		uint64_t addDistanceEffect(const Position& from, const Position& to) {
			SpectatorVec spectators, toPosSpectators;
			getSpectators(spectators, from, true, true);
			getSpectators(toPosSpectators, to, true, true);
			spectators.addSpectators(toPosSpectators);
			uint64_t sum = 0;
			for (Creature* s : spectators) { if (s->getPlayer()) { sum += s->id; } }
			return sum;
		}

		// Combat::doAreaCombat: one query for the area with its own range, then per target the health bar, the effect, the number
		uint64_t areaCombat(const Position& center, const std::vector<Creature*>& targets) {
			SpectatorVec spectators;
			getSpectators(spectators, center, true, true, 8, 8, 6, 6);
			uint64_t sum = spectators.size();
			for (Creature* t : targets) {
				sum += addMagicEffect(t->pos);   // the hit effect
				sum += addMagicEffect(t->pos);   // Game::addCreatureHealth
				sum += addMagicEffect(t->pos);   // the damage number
			}
			return sum;
		}

		uint64_t queries = 0;

	private:
		QTreeNode root;
		typename P::Cache spectatorCache;
		typename P::Cache playersSpectatorCache;
};

struct StockP { using SpectatorVec = Stock::SpectatorVec; using Cache = Stock::Cache; using StackVec = Stock::StackVec; };
struct NewP { using SpectatorVec = New::SpectatorVec; using Cache = New::Cache; using StackVec = New::StackVec; };

// ---------------------------------------------------------------------------------------------------- scenarios
struct Scenario {
	std::string name;
	int x0, y0, w, h;      // leaf area (tiles)
	int monsters, players;
	int monsterBox;        // monsters start in a box of this size around the players
	int playerBox;
	bool multiFloor;       // a few creatures on the floors above and below
};

struct Setup {
	std::vector<Creature> creatures;
	std::vector<Creature*> players, monsters;
};

static void buildSetup(const Scenario& sc, uint32_t seed, Setup& s)
{
	std::mt19937 rng(seed);
	s.creatures.assign(size_t(sc.monsters + sc.players), Creature());
	int cx = sc.x0 + sc.w / 2, cy = sc.y0 + sc.h / 2;
	for (int i = 0; i < sc.players + sc.monsters; ++i) {
		Creature& c = s.creatures[size_t(i)];
		c.id = uint32_t(i + 1);
		c.player = i < sc.players;
		int box = c.player ? sc.playerBox : sc.monsterBox;
		int px = c.player && sc.playerBox >= sc.w - 8 ? sc.x0 + 4 + int(rng() % unsigned(sc.w - 8)) : cx - box / 2 + int(rng() % unsigned(box));
		int py = c.player && sc.playerBox >= sc.h - 8 ? sc.y0 + 4 + int(rng() % unsigned(sc.h - 8)) : cy - box / 2 + int(rng() % unsigned(box));
		int pz = 7;
		if (sc.multiFloor && rng() % 6 == 0) { pz = 5 + int(rng() % 5); }
		c.pos = Position(uint16_t(px), uint16_t(py), uint8_t(pz));
		(c.player ? s.players : s.monsters).push_back(&c);
	}
}

template<typename W>
static void buildWorld(W& w, const Scenario& sc, Setup& s, uint32_t seed)
{
	std::mt19937 rng(seed);
	for (int y = sc.y0 - 40; y < sc.y0 + sc.h + 40; y += FLOOR_SIZE) {
		for (int x = sc.x0 - 40; x < sc.x0 + sc.w + 40; x += FLOOR_SIZE) {
			bool inside = x >= sc.x0 - 8 && x < sc.x0 + sc.w + 8 && y >= sc.y0 - 8 && y < sc.y0 + sc.h + 8;
			if (!inside && rng() % 6 == 0) { continue; } // some sectors around the area do not exist, as on the real map
			w.addLeaf(uint16_t(x), uint16_t(y));
		}
	}
	for (Creature& c : s.creatures) {
		// a creature stands in a leaf that exists
		while (!w.getQTNode(c.pos.x, c.pos.y)) { w.addLeaf(uint16_t(c.pos.x & ~7), uint16_t(c.pos.y & ~7)); }
		w.place(&c);
	}
}

static Position stepToward(const Position& p, int tx, int ty, std::mt19937& rng, const Scenario& sc)
{
	int dx = 0, dy = 0;
	if (rng() % 3 != 0) {
		dx = tx > p.x ? 1 : (tx < p.x ? -1 : 0);
		dy = ty > p.y ? 1 : (ty < p.y ? -1 : 0);
		if (rng() % 2) { dx = 0; } else if (rng() % 2) { dy = 0; }
	} else {
		dx = int(rng() % 3) - 1;
		dy = int(rng() % 3) - 1;
	}
	int nx = std::min(std::max(int(p.x) + dx, sc.x0 + 2), sc.x0 + sc.w - 3);
	int ny = std::min(std::max(int(p.y) + dy, sc.y0 + 2), sc.y0 + sc.h - 3);
	return Position(uint16_t(nx), uint16_t(ny), p.z);
}

// One operation sequence, driven by the rng only (never by results), so both worlds see the same one.
enum Phase { PH_MOVES, PH_SPELL, PH_EFFECTS, PH_MIXED, PH_COUNT };
static const char* phaseName(int p) { static const char* n[] = {"steps", "spell", "effects", "mixed tick"}; return n[p]; }

template<typename W>
static uint64_t runPhase(W& w, Setup& s, const Scenario& sc, Phase ph, int ticks, std::mt19937& rng)
{
	uint64_t sum = 0;
	int tx = sc.x0 + sc.w / 2, ty = sc.y0 + sc.h / 2;
	for (int t = 0; t < ticks; ++t) {
		bool doMoves = ph == PH_MOVES || ph == PH_MIXED;
		bool doSpell = ph == PH_SPELL || ph == PH_MIXED;
		bool doEffects = ph == PH_EFFECTS || ph == PH_MIXED;
		if (doMoves) {
			for (Creature* p : s.players) { sum += w.moveCreature(*p, stepToward(p->pos, p->pos.x + int(rng() % 9) - 4, p->pos.y + int(rng() % 9) - 4, rng, sc)); }
			for (Creature* m : s.monsters) {
				Creature* target = s.players.empty() ? nullptr : s.players[rng() % s.players.size()];
				int gx = target ? target->pos.x : tx, gy = target ? target->pos.y : ty;
				sum += w.moveCreature(*m, stepToward(m->pos, gx, gy, rng, sc));
			}
		}
		if (doSpell && !s.players.empty()) {
			Creature* caster = s.players[rng() % s.players.size()];
			std::vector<Creature*> targets;
			for (Creature* m : s.monsters) {
				if (std::abs(int(m->pos.x) - caster->pos.x) <= 6 && std::abs(int(m->pos.y) - caster->pos.y) <= 5) { targets.push_back(m); }
			}
			if (targets.empty() && !s.monsters.empty()) { targets.push_back(s.monsters[0]); }
			sum += w.areaCombat(caster->pos, targets);
			// 25 area tile effects (Combat::combatTileEffects: one shared query, plus the plain effect for the cast)
			for (int i = 0; i < 25; ++i) {
				sum += w.addMagicEffect(Position(uint16_t(caster->pos.x - 2 + i % 5), uint16_t(caster->pos.y - 2 + i / 5), caster->pos.z));
			}
		}
		if (doEffects) {
			size_t n = s.players.size();
			for (size_t i = 0; i < std::min<size_t>(n, 20); ++i) {
				Creature* p = s.players[rng() % n];
				sum += w.addMagicEffect(p->pos);
				sum += w.addDistanceEffect(p->pos, Position(uint16_t(p->pos.x + int(rng() % 7) - 3), uint16_t(p->pos.y + int(rng() % 7) - 3), p->pos.z));
			}
		}
	}
	return sum;
}

struct Result { double seconds = 0; uint64_t queries = 0; size_t allocs = 0; uint64_t sum = 0; uint64_t checkSum = 0; uint64_t checkQueries = 0; int ticks = 0; };

template<typename P>
static Result timePhase(const Scenario& sc, Phase ph, double budget, int reps, int fixedTicks = 0)
{
	Result best;
	best.seconds = 1e30;
	for (int rep = 0; rep < reps; ++rep) {
		World<P> w;
		Setup s;
		buildSetup(sc, 4242, s);
		buildWorld(w, sc, s, 99);
		std::mt19937 rng(777);
		uint64_t checkSum = runPhase(w, s, sc, ph, 30, rng); // the same 30 ticks in both worlds: the sums must agree
		uint64_t checkQueries = w.queries;
		int ticks = fixedTicks ? fixedTicks : 10;
		for (; !fixedTicks;) { // a tick count that takes about the budget (the stock run decides, the new one plays the same)
			auto a = Clock::now();
			runPhase(w, s, sc, ph, ticks, rng);
			double d = std::chrono::duration<double>(Clock::now() - a).count();
			if (d >= budget / 4) { break; }
			ticks *= 2;
		}
		for (int t = 10; fixedTicks && t <= fixedTicks; t *= 2) { runPhase(w, s, sc, ph, t, rng); } // the same warm up as the stock run's
		std::mt19937 r2(31337);
		uint64_t q0 = w.queries;
		size_t a0 = g_allocs;
		auto t0 = Clock::now();
		uint64_t sum = runPhase(w, s, sc, ph, ticks, r2);
		double sec = std::chrono::duration<double>(Clock::now() - t0).count();
		Result r;
		r.seconds = sec;
		r.queries = w.queries - q0;
		r.allocs = g_allocs - a0;
		r.sum = sum;
		r.checkSum = checkSum;
		r.checkQueries = checkQueries;
		r.seconds = sec / double(ticks); // per tick
		r.queries /= uint64_t(ticks);
		r.allocs /= size_t(ticks);
		r.ticks = ticks;
		if (r.seconds < best.seconds) { best = r; }
	}
	return best;
}

// ---------------------------------------------------------------------------------------------------- the check
static bool g_bad = false;
static void fail(const char* what, uint64_t a, uint64_t b)
{
	std::printf("MISMATCH %s: stock %llu new %llu\n", what, (unsigned long long)a, (unsigned long long)b);
	g_bad = true;
}

template<typename SV>
static std::vector<uint32_t> ids(const SV& v)
{
	std::vector<uint32_t> out;
	for (const Creature* c : v) { out.push_back(c->id); }
	return out;
}

// both worlds, the same creatures and the same operations; every answer compared in full (the elements and their order)
static void checkScenario(const Scenario& sc, uint32_t seed, int steps)
{
	World<StockP> ws;
	World<NewP> wn;
	Setup ss, sn;
	buildSetup(sc, seed, ss);
	buildSetup(sc, seed, sn);
	buildWorld(ws, sc, ss, seed + 1);
	buildWorld(wn, sc, sn, seed + 1);
	std::mt19937 rng(seed * 7 + 1);
	uint64_t compared = 0;
	for (int step = 0; step < steps; ++step) {
		unsigned op = rng() % 10;
		size_t n = ss.creatures.size();
		Creature& cs = ss.creatures[rng() % n];
		Creature& cn = sn.creatures[cs.id - 1];
		if (op < 4) {
			Position np = stepToward(cs.pos, sc.x0 + int(rng() % unsigned(sc.w)), sc.y0 + int(rng() % unsigned(sc.h)), rng, sc);
			if (rng() % 15 == 0) { np.x = uint16_t(sc.x0 + 2 + rng() % unsigned(sc.w - 4)); np.y = uint16_t(sc.y0 + 2 + rng() % unsigned(sc.h - 4)); } // teleport
			uint64_t a = ws.moveCreature(cs, np);
			uint64_t b = wn.moveCreature(cn, np);
			if (a != b) { fail("moveCreature sum", a, b); }
			++compared;
		} else {
			// a random query, the engine's shapes: default range multifloor, players only, own ranges, a non empty target
			Position c = (rng() % 3 == 0) ? Position(uint16_t(sc.x0 + int(rng() % unsigned(sc.w))), uint16_t(sc.y0 + int(rng() % unsigned(sc.h))), uint8_t(rng() % 3 == 0 ? 5 + rng() % 6 : 7)) : cs.pos;
			bool multi = rng() % 4 != 0;
			bool onlyPlayers = rng() % 2;
			int ranges[] = {0, 0, 0, 1, 3, 8, 14, 18};
			int rx = ranges[rng() % 8], ry = rng() % 2 ? rx : ranges[rng() % 8];
			Stock::SpectatorVec a;
			New::SpectatorVec b;
			if (rng() % 8 == 0) { // the caller passes a non empty vector (the cache must append, not replace)
				Creature* pre = &ss.creatures[rng() % n];
				a.emplace_back(pre);
				b.emplace_back(&sn.creatures[pre->id - 1]);
			}
			ws.getSpectators(a, c, multi, onlyPlayers, rx, rx, ry, ry);
			wn.getSpectators(b, c, multi, onlyPlayers, rx, rx, ry, ry);
			// ids: both worlds have their own Creature objects
			if (ids(a) != ids(b)) { fail("getSpectators", ids(a).size(), ids(b).size()); }
			if (op == 9 && !a.empty()) { // erase the way Monster::onThink / Player::... do (swap with the last)
				Creature* ea = *a.begin();
				a.erase(ea);
				b.erase(&sn.creatures[ea->id - 1]);
				if (ids(a) != ids(b)) { fail("erase", ids(a).size(), ids(b).size()); }
			}
			++compared;
			if (op == 8) { // the union of two positions
				Stock::SpectatorVec a2;
				New::SpectatorVec b2;
				Position c2(uint16_t(c.x + 1), c.y, c.z);
				ws.getSpectators(a, c2, true);
				wn.getSpectators(b, c2, true);
				ws.getSpectators(a2, c2, true, true);
				wn.getSpectators(b2, c2, true, true);
				a.addSpectators(a2);
				b.addSpectators(b2);
				if (ids(a) != ids(b)) { fail("union", ids(a).size(), ids(b).size()); }
				++compared;
			}
		}
	}
	// the final positions too
	for (size_t i = 0; i < ss.creatures.size(); ++i) {
		if (ss.creatures[i].pos.x != sn.creatures[i].pos.x || ss.creatures[i].pos.y != sn.creatures[i].pos.y) { fail("position", i, i); }
	}
	std::printf("  %-22s %d operations, %llu answers compared, %llu queries\n", sc.name.c_str(), steps, (unsigned long long)compared, (unsigned long long)ws.queries);
}


// ---------------------------------------------------------------------------------------------------- the parts of a query
struct Parts { double walk, miss, hit, hitPlayers, uni; size_t missAllocs, hitAllocs; };

// ns per call of: the sector walk alone, a query that misses the cache (walk + store), one that hits it, the same for
// players only, and the union of two lists of the size the hunt gives (45 creatures, 40 of them shared)
template<typename P>
static Parts partsOf(const Scenario& sc, double budget)
{
	World<P> w;
	Setup s;
	buildSetup(sc, 4242, s);
	buildWorld(w, sc, s, 99);
	using SV = typename P::SpectatorVec;
	Position c = s.players[0]->pos;
	Parts r{};
	auto run = [&](auto&& fn, size_t* allocs) {
		long n = 200;
		for (;;) {
			auto a = Clock::now();
			size_t a0 = g_allocs;
			for (long i = 0; i < n; ++i) { fn(); }
			double d = std::chrono::duration<double>(Clock::now() - a).count();
			if (d >= budget / 6) { if (allocs) { *allocs = (g_allocs - a0) / size_t(n); } return d / double(n) * 1e9; }
			n *= 2;
		}
	};
	volatile size_t sink = 0;
	r.walk = run([&] { SV v; w.getSpectatorsInternal(v, c, -maxViewportX, maxViewportX, -maxViewportY, maxViewportY, 0, 9, false); sink += v.size(); }, nullptr);
	r.miss = run([&] { w.clearCaches(s.players[0]); SV v; w.getSpectators(v, c, true); sink += v.size(); }, &r.missAllocs);
	{ SV v0; w.getSpectators(v0, c, true); }
	r.hit = run([&] { SV v; w.getSpectators(v, c, true); sink += v.size(); }, &r.hitAllocs);
	{ SV v0; w.getSpectators(v0, c, true, true); }
	r.hitPlayers = run([&] { SV v; w.getSpectators(v, c, true, true); sink += v.size(); }, nullptr);
	SV a, b;
	for (size_t i = 0; i < s.creatures.size(); ++i) { a.emplace_back(&s.creatures[i]); if (i >= 5) { b.emplace_back(&s.creatures[i]); } }
	r.uni = run([&] { SV x = a; x.addSpectators(b); sink += x.size(); }, nullptr);
	return r;
}

// ---------------------------------------------------------------------------------------------------- main
static const Scenario kHunt = {"hunt: 40 + 5", 32200, 32100, 120, 90, 40, 5, 20, 9, true};
static const Scenario kCity = {"city: 100 players", 32300, 32200, 160, 110, 0, 100, 0, 150, false};
static const Scenario kCrowd = {"crowd: 200 + 60", 32400, 32300, 60, 50, 200, 60, 30, 30, true};

int main(int argc, char** argv)
{
	double budget = 0.6;
	bool check = false;
	for (int i = 1; i < argc; ++i) {
		if (!std::strcmp(argv[i], "--check")) { check = true; }
		else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) { budget = std::atof(argv[++i]); }
		else { std::printf("usage: spectator_bench [--seconds N] [--check]\n"); return 2; }
	}

	std::printf("check: the same operations on a stock world and a new world, every answer compared in order\n");
	for (uint32_t seed = 1; seed <= (check ? 6u : 3u); ++seed) {
		checkScenario(kHunt, seed, check ? 6000 : 3000);
		checkScenario(kCity, seed, check ? 4000 : 2000);
		checkScenario(kCrowd, seed, check ? 4000 : 2000);
	}
	if (check) {
		std::printf("%s\n", g_bad ? "some checks failed" : "ok");
		return g_bad ? 1 : 0;
	}
	if (g_bad) { std::printf("answers differ, no timing\n"); return 1; }

	std::printf("\nper tick of the scenario (one tick: every creature steps once / one spell / 20 effects), best of 3\n");
	std::printf("%-20s %-13s | %9s %8s %8s | %9s %8s %8s | %6s %6s\n", "scenario", "phase", "stock us", "queries", "allocs", "new us", "queries", "allocs", "faster", "allocs");
	const Scenario* scs[] = {&kHunt, &kCity, &kCrowd};
	for (const Scenario* sc : scs) {
		for (int ph = 0; ph < PH_COUNT; ++ph) {
			if (sc->monsters == 0 && ph == PH_SPELL) { continue; }
			Result a = timePhase<StockP>(*sc, Phase(ph), budget, 3);
			Result b = timePhase<NewP>(*sc, Phase(ph), budget, 3, a.ticks);
			if (a.checkSum != b.checkSum || a.checkQueries != b.checkQueries) { std::printf("answers differ in %s / %s\n", sc->name.c_str(), phaseName(ph)); return 1; }
			std::printf("%-20s %-13s | %9.1f %8llu %8zu | %9.1f %8llu %8zu | %5.2fx %5.1f%%\n", sc->name.c_str(), phaseName(ph),
			            a.seconds * 1e6, (unsigned long long)a.queries, a.allocs, b.seconds * 1e6, (unsigned long long)b.queries, b.allocs,
			            a.seconds / b.seconds, a.allocs ? 100.0 * double(b.allocs) / double(a.allocs) : 0.0);
		}
	}
	std::printf("\nthe parts of one query in the hunt (ns per call, best of 3)\n");
	std::printf("%-34s %10s %10s\n", "", "stock", "new");
	Parts ps{}, pn{};
	for (int rep = 0; rep < 3; ++rep) {
		Parts a = partsOf<StockP>(kHunt, budget), b = partsOf<NewP>(kHunt, budget);
		if (rep == 0 || a.walk < ps.walk) { ps = a; }
		if (rep == 0 || b.walk < pn.walk) { pn = b; }
	}
	std::printf("%-34s %10.0f %10.0f\n", "sector walk alone (45 creatures)", ps.walk, pn.walk);
	std::printf("%-34s %10.0f %10.0f   allocs per call %zu -> %zu\n", "query, cache miss (walk + store)", ps.miss, pn.miss, ps.missAllocs, pn.missAllocs);
	std::printf("%-34s %10.0f %10.0f   allocs per call %zu -> %zu\n", "query, cache hit", ps.hit, pn.hit, ps.hitAllocs, pn.hitAllocs);
	std::printf("%-34s %10.0f %10.0f\n", "query, players only, cache hit", ps.hitPlayers, pn.hitPlayers);
	std::printf("%-34s %10.0f %10.0f\n", "union of 45 and 40 (copy + merge)", ps.uni, pn.uni);
	std::printf("faster = stock time / new time (the same queries, so also the ratio of queries per second); allocs = new allocations as a share of the stock ones\n");
	return 0;
}
