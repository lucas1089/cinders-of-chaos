// Shared by server/tools/chaospathing_test.cpp and server/tools/path_bench.cpp (patch 0070, server/README.md "Cheaper
// monster pathfinding (O211)"): a grid world and a port of Map::getPathMatching that is generic over the node store, so the
// stock store (StockNodes, copied from the base engine's map.cpp / map.h) and ChaosPath::NodeStore run the same search.
// Everything the engine would do on a tile (canWalkTo, the creature cost, isSightClear) is a grid lookup here.
#ifndef PATH_SEARCH_REF_H
#define PATH_SEARCH_REF_H

#include <cstdint>
#include <cstdlib>
#include <limits>
#include <unordered_map>
#include <vector>
#include "chaospathing.h"

namespace PathRef {

constexpr int32_t MAX_NODES = 512;
constexpr int32_t MAP_NORMALWALKCOST = 10;
constexpr int32_t MAP_DIAGONALWALKCOST = 25;

enum Dir { N = 0, E = 1, S = 2, W = 3, SW = 4, SE = 5, NW = 6, NE = 7 };

struct Pos {
	uint16_t x = 0, y = 0;
	uint8_t z = 7;
};

struct Node {
	Node* parent;
	int_fast32_t f;
	uint16_t x, y;
};

struct Params { // FindPathParams
	bool fullPathSearch = true;
	bool clearSight = true;
	bool allowDiagonal = true;
	bool keepDistance = false;
	int32_t maxSearchDist = 0;
	int32_t minTargetDist = -1;
	int32_t maxTargetDist = -1;
};

// The stock AStarNodes (base src/map.h, src/map.cpp): value-initialised arrays, a node table on the heap, a linear scan
// of every node to find the best one.
class StockNodes
{
	public:
		StockNodes(uint32_t x, uint32_t y) : nodes(), openNodes()
		{
			curNode = 1;
			closedNodes = 0;
			openNodes[0] = true;
			Node& startNode = nodes[0];
			startNode.parent = nullptr;
			startNode.x = x;
			startNode.y = y;
			startNode.f = 0;
			nodeTable[(x << 16) | y] = nodes;
		}
		Node* createOpenNode(Node* parent, uint32_t x, uint32_t y, int_fast32_t f)
		{
			if (curNode >= MAX_NODES) {
				return nullptr;
			}
			size_t retNode = curNode++;
			openNodes[retNode] = true;
			Node* node = nodes + retNode;
			nodeTable[(x << 16) | y] = node;
			node->parent = parent;
			node->x = x;
			node->y = y;
			node->f = f;
			return node;
		}
		Node* getBestNode()
		{
			if (curNode == 0) {
				return nullptr;
			}
			int32_t best_node_f = std::numeric_limits<int32_t>::max();
			int32_t best_node = -1;
			for (size_t i = 0; i < curNode; i++) {
				if (openNodes[i] && nodes[i].f < best_node_f) {
					best_node_f = nodes[i].f;
					best_node = i;
				}
			}
			if (best_node >= 0) {
				return nodes + best_node;
			}
			return nullptr;
		}
		void closeNode(Node* node)
		{
			openNodes[node - nodes] = false;
			++closedNodes;
		}
		void openNode(Node* node)
		{
			size_t index = node - nodes;
			if (!openNodes[index]) {
				openNodes[index] = true;
				--closedNodes;
			}
		}
		int_fast32_t getClosedNodes() const { return closedNodes; }
		Node* getNodeByPosition(uint32_t x, uint32_t y)
		{
			auto it = nodeTable.find((x << 16) | y);
			if (it == nodeTable.end()) {
				return nullptr;
			}
			return it->second;
		}

	private:
		Node nodes[MAX_NODES];
		bool openNodes[MAX_NODES];
		std::unordered_map<uint32_t, Node*> nodeTable;
		size_t curNode;
		int_fast32_t closedNodes;
};

// The new store behind the same interface as StockNodes (the engine's AStarNodes forwards to it the same way).
class FastNodes
{
	public:
		FastNodes(uint32_t x, uint32_t y) { lease->reset(x, y); }
		Node* createOpenNode(Node* p, uint32_t x, uint32_t y, int_fast32_t f) { return lease->createOpenNode(p, x, y, f); }
		Node* getBestNode() { return lease->getBestNode(); }
		void closeNode(Node* n) { lease->closeNode(n); }
		void openNode(Node* n) { lease->openNode(n); }
		int_fast32_t getClosedNodes() const { return lease->getClosedNodes(); }
		Node* getNodeByPosition(uint32_t x, uint32_t y) { return lease->getNodeByPosition(x, y); }

	private:
		ChaosPath::Lease<ChaosPath::NodeStore<Node, MAX_NODES>> lease;
};

// A rectangle of tiles at (originX, originY), z 7: 0 no tile, 1 walkable, 2 blocking. creature[] marks tiles a creature
// stands on (the search lets a monster path through them at an extra cost, like Tile::getTopVisibleBlockingCreature).
struct Grid {
	int w = 0, h = 0;
	uint16_t originX = 1000, originY = 1000;
	std::vector<uint8_t> cell;
	std::vector<uint8_t> creature;

	void init(int width, int height) { w = width; h = height; cell.assign(size_t(w) * h, 0); creature.assign(size_t(w) * h, 0); }
	bool inside(int x, int y) const { return x >= 0 && y >= 0 && x < w && y < h; }
	uint8_t at(int x, int y) const { return inside(x, y) ? cell[size_t(y) * w + x] : 0; }
	uint8_t& at(int x, int y) { return cell[size_t(y) * w + x]; }
	bool walkable(int x, int y) const { return at(x, y) == 1; }
	bool crowded(int x, int y) const { return inside(x, y) && creature[size_t(y) * w + x] != 0; }
	Pos pos(int x, int y) const { Pos p; p.x = uint16_t(originX + x); p.y = uint16_t(originY + y); return p; }
	int gx(const Pos& p) const { return int(p.x) - originX; }
	int gy(const Pos& p) const { return int(p.y) - originY; }

	// isSightClear stand-in: every tile on the line except the ends must not block
	bool sightClear(const Pos& a, const Pos& b) const
	{
		int x0 = gx(a), y0 = gy(a), x1 = gx(b), y1 = gy(b);
		const int dx = std::abs(x1 - x0), dy = std::abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
		int err = dx - dy;
		while (x0 != x1 || y0 != y1) {
			if ((x0 != gx(a) || y0 != gy(a)) && at(x0, y0) == 2) {
				return false;
			}
			const int e2 = 2 * err;
			if (e2 > -dy) { err -= dy; x0 += sx; }
			if (e2 < dx) { err += dx; y0 += sy; }
		}
		return true;
	}
};

struct Stats {
	uint64_t searches = 0;
	uint64_t expanded = 0;  // nodes taken from the open list
	uint64_t created = 0;   // nodes put on the open list
	uint64_t tileTests = 0; // canWalkTo calls
	uint64_t failed = 0;
};

// FrozenPathingConditionCall (base src/creature.cpp), isSightClear on the grid
struct Condition {
	const Grid& grid;
	Pos target;

	bool isInRange(const Pos& startPos, const Pos& testPos, const Params& fpp) const
	{
		if (fpp.fullPathSearch) {
			if (testPos.x > target.x + fpp.maxTargetDist) { return false; }
			if (testPos.x < target.x - fpp.maxTargetDist) { return false; }
			if (testPos.y > target.y + fpp.maxTargetDist) { return false; }
			if (testPos.y < target.y - fpp.maxTargetDist) { return false; }
		} else {
			int_fast32_t dx = int(startPos.x) - int(target.x); // Position::getOffsetX(startPos, targetPos)
			int32_t dxMax = (dx >= 0 ? fpp.maxTargetDist : 0);
			if (testPos.x > target.x + dxMax) { return false; }
			int32_t dxMin = (dx <= 0 ? fpp.maxTargetDist : 0);
			if (testPos.x < target.x - dxMin) { return false; }
			int_fast32_t dy = int(startPos.y) - int(target.y);
			int32_t dyMax = (dy >= 0 ? fpp.maxTargetDist : 0);
			if (testPos.y > target.y + dyMax) { return false; }
			int32_t dyMin = (dy <= 0 ? fpp.maxTargetDist : 0);
			if (testPos.y < target.y - dyMin) { return false; }
		}
		return true;
	}

	bool operator()(const Pos& startPos, const Pos& testPos, const Params& fpp, int32_t& bestMatchDist) const
	{
		if (!isInRange(startPos, testPos, fpp)) {
			return false;
		}
		if (fpp.clearSight && !grid.sightClear(testPos, target)) {
			return false;
		}
		int32_t testDist = std::max<int32_t>(std::abs(int(target.x) - testPos.x), std::abs(int(target.y) - testPos.y));
		if (fpp.maxTargetDist == 1) {
			if (testDist < fpp.minTargetDist || testDist > fpp.maxTargetDist) {
				return false;
			}
			return true;
		} else if (testDist <= fpp.maxTargetDist) {
			if (testDist < fpp.minTargetDist) {
				return false;
			}
			if (testDist == fpp.maxTargetDist) {
				bestMatchDist = 0;
				return true;
			} else if (testDist > bestMatchDist) {
				bestMatchDist = testDist;
				return true;
			}
		}
		return false;
	}
};

// Map::getPathMatching (base src/map.cpp), line by line, with the tile tests on the grid.
template<typename Store>
bool getPathMatching(const Grid& grid, Pos start, const Condition& pathCondition, const Params& fpp,
                     std::vector<int>& dirList, Stats& stats, Pos* endOut = nullptr)
{
	++stats.searches;
	Pos pos = start;
	Pos endPos;

	Store nodes(pos.x, pos.y);
	int32_t bestMatch = 0;

	static int_fast32_t dirNeighbors[8][5][2] = {
		{{-1, 0}, {0, 1}, {1, 0}, {1, 1}, {-1, 1}},
		{{-1, 0}, {0, 1}, {0, -1}, {-1, -1}, {-1, 1}},
		{{-1, 0}, {1, 0}, {0, -1}, {-1, -1}, {1, -1}},
		{{0, 1}, {1, 0}, {0, -1}, {1, -1}, {1, 1}},
		{{1, 0}, {0, -1}, {-1, -1}, {1, -1}, {1, 1}},
		{{-1, 0}, {0, -1}, {-1, -1}, {1, -1}, {-1, 1}},
		{{0, 1}, {1, 0}, {1, -1}, {1, 1}, {-1, 1}},
		{{-1, 0}, {0, 1}, {-1, -1}, {1, 1}, {-1, 1}}
	};
	static int_fast32_t allNeighbors[8][2] = {{-1, 0}, {0, 1}, {1, 0}, {0, -1}, {-1, -1}, {1, -1}, {1, 1}, {-1, 1}};

	const Pos startPos = start;
	Node* found = nullptr;
	while (fpp.maxSearchDist != 0 || nodes.getClosedNodes() < 100) {
		Node* n = nodes.getBestNode();
		if (!n) {
			if (found) {
				break;
			}
			++stats.failed;
			return false;
		}
		++stats.expanded;

		const int_fast32_t x = n->x;
		const int_fast32_t y = n->y;
		pos.x = x;
		pos.y = y;
		if (pathCondition(startPos, pos, fpp, bestMatch)) {
			found = n;
			endPos = pos;
			if (bestMatch == 0) {
				break;
			}
		}

		uint_fast32_t dirCount;
		int_fast32_t* neighbors;
		if (n->parent) {
			const int_fast32_t offset_x = n->parent->x - x;
			const int_fast32_t offset_y = n->parent->y - y;
			if (offset_y == 0) {
				neighbors = offset_x == -1 ? *dirNeighbors[W] : *dirNeighbors[E];
			} else if (!fpp.allowDiagonal || offset_x == 0) {
				neighbors = offset_y == -1 ? *dirNeighbors[N] : *dirNeighbors[S];
			} else if (offset_y == -1) {
				neighbors = offset_x == -1 ? *dirNeighbors[NW] : *dirNeighbors[NE];
			} else if (offset_x == -1) {
				neighbors = *dirNeighbors[SW];
			} else {
				neighbors = *dirNeighbors[SE];
			}
			dirCount = fpp.allowDiagonal ? 5 : 3;
		} else {
			dirCount = 8;
			neighbors = *allNeighbors;
		}

		const int_fast32_t f = n->f;
		for (uint_fast32_t i = 0; i < dirCount; ++i) {
			pos.x = x + *neighbors++;
			pos.y = y + *neighbors++;

			if (fpp.maxSearchDist != 0 && (std::abs(int(startPos.x) - pos.x) > fpp.maxSearchDist || std::abs(int(startPos.y) - pos.y) > fpp.maxSearchDist)) {
				continue;
			}
			if (fpp.keepDistance && !pathCondition.isInRange(startPos, pos, fpp)) {
				continue;
			}

			bool tile;
			Node* neighborNode = nodes.getNodeByPosition(pos.x, pos.y);
			if (neighborNode) {
				tile = true;
			} else {
				++stats.tileTests;
				tile = grid.walkable(grid.gx(pos), grid.gy(pos));
				if (!tile) {
					continue;
				}
			}

			const int_fast32_t cost = (std::abs(int(n->x) - pos.x) == std::abs(int(n->y) - pos.y)) ? MAP_DIAGONALWALKCOST : MAP_NORMALWALKCOST;
			const int_fast32_t extraCost = grid.crowded(grid.gx(pos), grid.gy(pos)) ? MAP_NORMALWALKCOST * 3 : 0;
			const int_fast32_t newf = f + cost + extraCost;

			if (neighborNode) {
				if (neighborNode->f <= newf) {
					continue;
				}
				neighborNode->f = newf;
				neighborNode->parent = n;
				nodes.openNode(neighborNode);
			} else {
				neighborNode = nodes.createOpenNode(n, pos.x, pos.y, newf);
				++stats.created;
				if (!neighborNode) {
					if (found) {
						break;
					}
					++stats.failed;
					return false;
				}
			}
		}
		nodes.closeNode(n);
	}

	if (!found) {
		++stats.failed;
		return false;
	}

	int_fast32_t prevx = endPos.x;
	int_fast32_t prevy = endPos.y;
	found = found->parent;
	while (found) {
		pos.x = found->x;
		pos.y = found->y;
		int_fast32_t dx = int(pos.x) - prevx;
		int_fast32_t dy = int(pos.y) - prevy;
		prevx = pos.x;
		prevy = pos.y;
		if (dx == 1 && dy == 1) { dirList.push_back(NW); }
		else if (dx == -1 && dy == 1) { dirList.push_back(NE); }
		else if (dx == 1 && dy == -1) { dirList.push_back(SW); }
		else if (dx == -1 && dy == -1) { dirList.push_back(SE); }
		else if (dx == 1) { dirList.push_back(W); }
		else if (dx == -1) { dirList.push_back(E); }
		else if (dy == 1) { dirList.push_back(N); }
		else if (dy == -1) { dirList.push_back(S); }
		found = found->parent;
	}
	if (endOut) {
		*endOut = endPos;
	}
	return true;
}

} // namespace PathRef

#endif
