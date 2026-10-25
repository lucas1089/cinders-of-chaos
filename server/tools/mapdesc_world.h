// Synthetic world shared by chaosmapdesc_test.cpp and mapdesc_bench.cpp (patch 0072, server/README.md "Cheaper map
// description (O213)"). It copies what the map description touches in the engine: the quad tree (QTreeNode::getLeafStatic:
// two bits per level, 12 levels down to a 8x8 leaf, FLOOR_SIZE 8), a leaf with one Floor per z (MAP_MAX_LAYERS 16), the
// stock Map::getTile, the stock ProtocolGame::GetFloorDescription / GetMapDescription loops (the reference) and the
// GetMapDescription floor order. Not the engine: the tile writer is a stand-in (ground and up to a few items, a table
// lookup for each as Item::items[id] is), creatures and the known creature list are not part of what the patch changes.
#ifndef MAPDESC_WORLD_H
#define MAPDESC_WORLD_H

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <random>
#include <vector>

namespace world {

constexpr int FLOOR_SIZE = 8;
constexpr int MAP_MAX_LAYERS = 16;

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

		const Floor* getFloorAt(uint16_t x, uint16_t y, uint8_t z) const {
			if (z >= MAP_MAX_LAYERS) { return nullptr; }
			const Leaf* leaf = Node::getLeafStatic<const Leaf*, const Node*>(&root, x, y);
			return leaf ? leaf->getFloor(z) : nullptr;
		}

		void setTile(uint16_t x, uint16_t y, uint8_t z, Tile* t) {
			Node* node = &root;
			uint32_t px = x, py = y;
			for (int level = 0; level < 12; ++level) {
				int idx = ((px & 0x8000) >> 15) | ((py & 0x8000) >> 14);
				if (!node->child[idx]) {
					Node* c;
					if (level == 11) { c = new Leaf(); } else { c = new Node(); }
					nodes.push_back(c);
					node->child[idx] = c;
				}
				node = node->child[idx];
				px <<= 1;
				py <<= 1;
			}
			Leaf* leaf = static_cast<Leaf*>(node);
			if (!leaf->array[z]) { leaf->array[z] = new Floor(); floors.push_back(leaf->array[z]); }
			tiles.push_back(t);
			leaf->array[z]->tiles[x & 7][y & 7] = t;
		}

	private:
		Node root;
		std::vector<Node*> nodes;
		std::vector<Floor*> floors;
		std::vector<Tile*> tiles;
};

// outgoing message: the bytes only (the engine's buffer is a fixed array too)
struct Msg {
	std::vector<uint8_t> buf;
	Msg() { buf.reserve(1 << 17); }
	void addByte(uint8_t b) { buf.push_back(b); }
	template<typename T> void add(T v) { uint8_t b[sizeof(T)]; std::memcpy(b, &v, sizeof(T)); buf.insert(buf.end(), b, b + sizeof(T)); }
	void clear() { buf.clear(); }
};

// stand-in for ProtocolGame::GetTileDescription: environmental effects, ground, up to 9 more items, each looked up in a
// table (clientId, stackable) as Item::items[id] is
struct ItemType { uint16_t clientId; bool stackable; };
inline const ItemType* itemTable() {
	static std::vector<ItemType> t = [] {
		std::vector<ItemType> v(4096);
		std::mt19937 r(7);
		for (auto& e : v) { e.clientId = uint16_t(100 + r() % 20000); e.stackable = (r() % 7) == 0; }
		return v;
	}();
	return t.data();
}

inline void emitTile(const Tile* tile, Msg& msg) {
	const ItemType* it = itemTable();
	msg.add<uint16_t>(0x00);
	if (tile->ground) {
		const ItemType& g = it[tile->ground & 4095];
		msg.add<uint16_t>(g.clientId);
		msg.addByte(0xFF);
	}
	for (int i = 0; i < tile->n; ++i) {
		const ItemType& g = it[(tile->itemBase + i * 37) & 4095];
		msg.add<uint16_t>(g.clientId);
		msg.addByte(0xFF);
		if (g.stackable) { msg.addByte(uint8_t(i + 1)); }
	}
}

// the stock GetFloorDescription (the reference)
inline void stockFloor(const Map& map, Msg& msg, int32_t x, int32_t y, int32_t z, int32_t width, int32_t height, int32_t offset, int32_t& skip) {
	for (int32_t nx = 0; nx < width; nx++) {
		for (int32_t ny = 0; ny < height; ny++) {
			Tile* tile = map.getTile(x + nx + offset, y + ny + offset, z);
			if (tile) {
				if (skip >= 0) { msg.addByte(skip); msg.addByte(0xFF); }
				skip = 0;
				emitTile(tile, msg);
			} else if (skip == 0xFE) {
				msg.addByte(0xFF); msg.addByte(0xFF);
				skip = -1;
			} else {
				++skip;
			}
		}
	}
}

template<typename FloorFn>
inline void mapDescription(Msg& msg, int32_t x, int32_t y, int32_t z, int32_t width, int32_t height, FloorFn&& floorFn) {
	int32_t skip = -1;
	int32_t startz, endz, zstep;
	if (z > 7) {
		startz = z - 2;
		endz = std::min<int32_t>(MAP_MAX_LAYERS - 1, z + 2);
		zstep = 1;
	} else {
		startz = 7;
		endz = 0;
		zstep = -1;
	}
	for (int32_t nz = startz; nz != endz + zstep; nz += zstep) {
		floorFn(msg, x, y, nz, width, height, z - nz, skip);
	}
	if (skip >= 0) { msg.addByte(skip); msg.addByte(0xFF); }
}

} // namespace world

#endif
