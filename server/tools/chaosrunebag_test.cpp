// Tests of src/chaosrunebag.h (engine src-patch 0092, the Rune Bag in the purse, O509; server/README.md "Using a rune from
// the bag"). CI cuts the header out of the patch and builds this file against it:
//   g++ -std=c++17 -Wall -Wextra -I <dir with chaosrunebag.h> server/tools/chaosrunebag_test.cpp
// Checks: off (type 0, or a null inbox) visits nothing; the items directly inside a Rune Bag that lies directly in the
// store inbox are visited, in order; nothing else of the purse is (a loose item, a Loot Bag or another pouch, a bag
// inside the Rune Bag, a Rune Bag inside a bag in the purse, an item of the bag type that is no container); the walk
// stops when the callback says so; a count and a removal list built from the one walk agree; the type can be changed
// and switched off.
#include "chaosrunebag.h"

#include <cstdio>
#include <deque>
#include <vector>

static int failures = 0;
static int checks = 0;

static void eq(long got, long want, const char* what)
{
	++checks;
	if (got != want) {
		++failures;
		std::printf("FAIL %s: got %ld, want %ld\n", what, got, want);
	}
}

struct Box;

// the engine's member names: Item::getID, Item::getContainer; Container::getItemList
struct Item {
	uint16_t id;
	uint32_t count;
	Box* box;
	uint16_t getID() const { return id; }
	Box* getContainer() const { return box; }
};

struct Box {
	std::deque<Item*> items;
	const std::deque<Item*>& getItemList() const { return items; }
};

static const uint16_t RUNE_BAG = 32096, LOOT_BAG = 32081, BACKPACK = 1988, DISPEL = 2261, MENDING = 2265;

int main()
{
	std::vector<Item*> owned;
	auto item = [&](uint16_t id, uint32_t count, Box* box = nullptr) {
		owned.push_back(new Item{id, count, box});
		return owned.back();
	};
	auto bag = [&](uint16_t id, std::initializer_list<Item*> content) {
		Box* b = new Box();
		for (Item* i : content) {
			b->items.push_back(i);
		}
		return item(id, 1, b);
	};
	auto ids = [](const Box& inbox) {
		std::vector<uint16_t> out;
		ChaosRuneBag::forEachItem(&inbox, [&](Item* i) {
			out.push_back(i->getID());
			return false;
		});
		return out;
	};

	Box purse;
	Item* runesA = item(DISPEL, 12);
	Item* runesB = item(MENDING, 3);
	purse.items.push_back(bag(RUNE_BAG, {runesA, runesB}));

	// nothing set (Game.setRuneBagContainer never called): the engine behaves as before
	eq(ChaosRuneBag::bagType(), 0, "unset: type 0");
	eq(ids(purse).size(), 0, "unset: nothing visited");

	ChaosRuneBag::setBagType(RUNE_BAG);
	eq(ids(purse).size(), 2, "set: the two stacks of the Rune Bag in the purse");
	eq(ids(purse)[0], DISPEL, "set: first stack, bag order");
	eq(ids(purse)[1], MENDING, "set: second stack");
	eq(ChaosRuneBag::forEachItem(static_cast<const Box*>(nullptr), [](Item*) { return false; }), 0, "a null inbox visits nothing");

	// the narrow rule: only the contents of a Rune Bag lying directly in the purse
	Box other;
	Item* loose = item(DISPEL, 99);                            // a plain item lying in the purse
	Item* lootStack = item(DISPEL, 50);                        // inside the Loot Bag in the purse
	Item* deep = item(DISPEL, 40);                             // inside a bag inside the Rune Bag
	Item* hidden = item(DISPEL, 30);                           // a Rune Bag inside a bag in the purse
	Item* notContainer = item(RUNE_BAG, 1);                    // an item of the bag type that is no container
	other.items.push_back(loose);
	other.items.push_back(bag(LOOT_BAG, {lootStack}));
	other.items.push_back(bag(BACKPACK, {bag(RUNE_BAG, {hidden})}));
	other.items.push_back(notContainer);
	other.items.push_back(bag(RUNE_BAG, {bag(BACKPACK, {deep}), item(MENDING, 7)}));
	std::vector<uint16_t> seen = ids(other);
	eq(seen.size(), 2, "the narrow rule: a bag and a stack of the Rune Bag only");
	eq(seen[0], BACKPACK, "the bag inside the Rune Bag is one entry, its contents are not walked");
	eq(seen[1], MENDING, "the stack beside it");
	long total = 0;
	ChaosRuneBag::forEachItem(&other, [&](Item* i) {
		total += i->count;
		return false;
	});
	eq(total, 1 + 7, "no loose item, no Loot Bag content, nothing nested counted");

	// the walk stops when the callback says so, and says so
	int calls = 0;
	bool stopped = ChaosRuneBag::forEachItem(&purse, [&](Item* i) {
		++calls;
		return i->getID() == DISPEL;
	});
	eq(stopped, 1, "stopped: true");
	eq(calls, 1, "stopped: no further call");
	eq(ChaosRuneBag::forEachItem(&purse, [](Item*) { return false; }), 0, "not stopped: false");

	// a count and a removal list from the same walk agree (Player::getItemTypeCount / countRemovableItemsOfType)
	Box two;
	two.items.push_back(bag(RUNE_BAG, {item(DISPEL, 5), item(MENDING, 2)}));
	two.items.push_back(bag(RUNE_BAG, {item(DISPEL, 4)}));
	uint32_t count = 0;
	std::vector<Item*> list;
	ChaosRuneBag::forEachItem(&two, [&](Item* i) {
		if (i->getID() == DISPEL) {
			count += i->count;
			list.push_back(i);
		}
		return false;
	});
	uint32_t listed = 0;
	for (Item* i : list) {
		listed += i->count;
	}
	eq(count, 9, "two Rune Bags: counted");
	eq(listed, count, "the removal list holds what was counted");
	uint32_t limit = 6, got = 0;
	std::vector<Item*> limited;
	ChaosRuneBag::forEachItem(&two, [&](Item* i) {
		if (i->getID() == DISPEL) {
			limited.push_back(i);
			got += i->count;
			if (got >= limit) {
				return true;
			}
		}
		return false;
	});
	eq(limited.size(), 2, "a limit stops at the stack that reaches it");

	// the type can change and be switched off
	ChaosRuneBag::setBagType(LOOT_BAG);
	eq(ids(two).size(), 0, "another type: the Rune Bags are no longer visited");
	ChaosRuneBag::setBagType(0);
	eq(ids(purse).size(), 0, "off again: nothing visited");

	for (Item* i : owned) {
		delete i->box;
		delete i;
	}
	std::printf("rune bag header test: %d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
