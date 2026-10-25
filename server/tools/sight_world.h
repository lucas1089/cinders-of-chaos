// Synthetic world shared by chaossight_test.cpp and sight_bench.cpp (patch 0074, server/README.md "Cheaper line of sight
// (O218)"). It copies what the sight line touches in the engine: the quad tree (QTreeNode::getLeafStatic and createLeaf:
// two bits per level, 13 levels from the root down to an 8x8 leaf, FLOOR_SIZE 8; mapdesc_world.h has 12 levels, which makes
// a leaf cover 16x16 tiles that share one 8x8 Floor, wrong for a test that sets neighbouring blocks), a leaf with one
// Floor per z (MAP_MAX_LAYERS 16), the stock Map::getTile, a Tile::hasProperty(CONST_PROP_BLOCKPROJECTILE) stand-in (the
// ground and each item are looked up in a flag table, as Item::items[id] is) and copies of the stock Map::isTileClear,
// checkSteepLine, checkSlightLine and Map::checkSightLine (the reference).
#ifndef SIGHT_WORLD_H
#define SIGHT_WORLD_H

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <random>
#include <vector>

namespace world {

constexpr int FLOOR_SIZE = 8;
constexpr int MAP_MAX_LAYERS = 16;
constexpr int TREE_LEVELS = 13; // 15 down to FLOOR_BITS 3, both ends included

struct Tile {
	uint16_t ground = 0;
	uint8_t n = 0;       // items on top
	uint8_t itemBase = 0;
};

struct Floor {
	Tile* tiles[FLOOR_SIZE][FLOOR_SIZE] = {};
};

struct Node {
	Node* child[4] = {};
	bool leaf = false;
	virtual ~Node() = default;

	template<typename Leaf, typename N>
	static Leaf getLeafStatic(N node, uint32_t x, uint32_t y) {
		do {
			node = node->child[((x & 0x8000) >> 15) | ((y & 0x8000) >> 14)];
			if (!node) { return nullptr; }
			x <<= 1;
			y <<= 1;
		} while (!node->leaf);
		return static_cast<Leaf>(node);
	}
};

struct Leaf final : Node {
	Floor* array[MAP_MAX_LAYERS] = {};
	Leaf() { leaf = true; }
	Floor* getFloor(uint8_t z) const { return array[z]; }
};

class Map
{
	public:
		Map() = default;
		Map(const Map&) = delete;
		~Map() { for (Tile* t : tiles) { delete t; } for (Floor* f : floors) { delete f; } for (Node* n : nodes) { delete n; } }

		Tile* getTile(uint16_t x, uint16_t y, uint8_t z) const {
			if (z >= MAP_MAX_LAYERS) { return nullptr; }
			const Leaf* leaf = Node::getLeafStatic<const Leaf*, const Node*>(&root, x, y);
			if (!leaf) { return nullptr; }
			const Floor* floor = leaf->getFloor(z);
			if (!floor) { return nullptr; }
			return floor->tiles[x & 7][y & 7];
		}

		// Map::getFloorAt of patch 0072
		const Floor* getFloorAt(uint16_t x, uint16_t y, uint8_t z) const {
			if (z >= MAP_MAX_LAYERS) { return nullptr; }
			const Leaf* leaf = Node::getLeafStatic<const Leaf*, const Node*>(&root, x, y);
			return leaf ? leaf->getFloor(z) : nullptr;
		}

		void setTile(uint16_t x, uint16_t y, uint8_t z, Tile* t) {
			Node* node = &root;
			uint32_t px = x, py = y;
			for (int level = 0; level < TREE_LEVELS; ++level) {
				int idx = ((px & 0x8000) >> 15) | ((py & 0x8000) >> 14);
				if (!node->child[idx]) {
					Node* c;
					if (level == TREE_LEVELS - 1) { c = new Leaf(); } else { c = new Node(); }
					nodes.push_back(c);
					node->child[idx] = c;
				}
				node = node->child[idx];
				px <<= 1;
				py <<= 1;
			}
			Leaf* leaf = static_cast<Leaf*>(node);
			if (!leaf->array[z]) { leaf->array[z] = new Floor(); floors.push_back(leaf->array[z]); }
			Tile*& slot = leaf->array[z]->tiles[x & 7][y & 7];
			if (slot) { tiles.erase(std::find(tiles.begin(), tiles.end(), slot)); delete slot; }
			slot = t;
			tiles.push_back(t);
		}

	private:
		Node root;
		std::vector<Node*> nodes;
		std::vector<Floor*> floors;
		std::vector<Tile*> tiles;
};

// 1 in 40 item ids stops a projectile
inline const bool* blockTable() {
	static std::vector<char> t = [] {
		std::vector<char> v(4096);
		for (size_t i = 0; i < v.size(); ++i) { v[i] = (i * 2654435761u >> 7) % 40 == 0; }
		return v;
	}();
	return reinterpret_cast<const bool*>(t.data());
}

// Tile::hasProperty(CONST_PROP_BLOCKPROJECTILE): the ground, then the items
inline bool hasBlock(const Tile* tile) {
	const bool* b = blockTable();
	if (tile->ground && b[tile->ground & 4095]) { return true; }
	for (int i = 0; i < tile->n; ++i) {
		if (b[(tile->itemBase + i * 37) & 4095]) { return true; }
	}
	return false;
}

// stock Map::isTileClear with blockFloor false
inline bool stockTileClear(const Map& map, uint16_t x, uint16_t y, uint8_t z) {
	const Tile* tile = map.getTile(x, y, z);
	if (!tile) { return true; }
	return !hasBlock(tile);
}

inline bool stockSteep(const Map& map, uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint8_t z) {
	float dx = x1 - x0;
	float slope = (dx == 0) ? 1 : (y1 - y0) / dx;
	float yi = y0 + slope;
	for (uint16_t x = x0 + 1; x < x1; ++x) {
		if (!stockTileClear(map, std::floor(yi + 0.1), x, z)) { return false; }
		yi += slope;
	}
	return true;
}

inline bool stockSlight(const Map& map, uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint8_t z) {
	float dx = x1 - x0;
	float slope = (dx == 0) ? 1 : (y1 - y0) / dx;
	float yi = y0 + slope;
	for (uint16_t x = x0 + 1; x < x1; ++x) {
		if (!stockTileClear(map, x, std::floor(yi + 0.1), z)) { return false; }
		yi += slope;
	}
	return true;
}

// stock Map::checkSightLine (the reference)
inline bool stockCheckSightLine(const Map& map, uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint8_t z) {
	if (x0 == x1 && y0 == y1) { return true; }
	if (std::abs(y1 - y0) > std::abs(x1 - x0)) {
		if (y1 > y0) { return stockSteep(map, y0, x0, y1, x1, z); }
		return stockSteep(map, y1, x1, y0, x0, z);
	}
	if (x0 > x1) { return stockSlight(map, x1, y1, x0, y0, z); }
	return stockSlight(map, x0, y0, x1, y1, z);
}

} // namespace world

#endif
