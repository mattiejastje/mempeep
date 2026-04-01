#pragma once

#include <cstdint>
#include <mempeep/descriptors.hpp>

namespace mempeep::test {

using TUInt8 = Primitive<uint8_t>;

struct Pos {
  uint8_t x, y;
};

// intentionally have padding bytes at end, for testing
using TPos
  = Struct<Pos, Fields<Field<TUInt8, &Pos::x>, Field<TUInt8, &Pos::y>, Pad<2>>>;

struct Cave {
  uint8_t id;
  uint8_t next;
};

using TCave = Primitive<Cave>;

struct Player {
  uint8_t health;
  Pos pos;
  uint8_t target_ptr;
  uint16_t shop_ptr;  // wider than needed, must also work
  uint8_t weapon_ptr;
  Pos prev_pos;
  std::optional<Pos> tagged_pos;
  std::optional<Pos> house_pos;
  uint8_t mana;
};

using TPlayer = Struct<
  Player,
  Fields<
    Pad<2>,
    Field<TUInt8, &Player::health>,
    Pad<1>,
    Field<TPos, &Player::pos>,
    Field<RawAddr<uint8_t>, &Player::target_ptr>,
    Field<RawAddr<uint16_t>, &Player::shop_ptr>,
    Field<RawAddr<uint8_t>, &Player::weapon_ptr>,
    Field<Ref<TPos>, &Player::prev_pos>,
    Field<NullableRef<TPos>, &Player::tagged_pos>,
    Field<NullableRef<TPos>, &Player::house_pos>,
    Field<TUInt8, &Player::mana>,
    Pad<1>>>;

struct Game {
  uint8_t level;
  Player player;
  std::array<Pos, 2> hands;
  std::vector<Pos> pets;
  std::vector<Cave> caves;
};

using TGame = Struct<
  Game,
  Fields<
    Seek<1>,
    Field<TUInt8, &Game::level>,
    Seek<4>,
    Field<TPlayer, &Game::player>,
    Field<Array<TPos, 2>, &Game::hands>,
    Field<Vector<TPos, 0x1000>, &Game::pets>,
    Field<CircularList<TCave, &Cave::next, 0x1000>, &Game::caves>>>;

static constexpr char game_data[]
  = "\x00\x00\x00\x00"  // 0:  unused
    "\x00\x11"          // 4:  pad(1), level = 17
    "\x00\x00\x00\x00"  // 6:  pad(4)
    "\x7b\x00"          // 10: health = 123, pad(1)
    "\x0b\x16\x00\x00"  // 12: pos = (11, 22, pad(2))
    "\x00"              // 16: target_ptr = 0
    "\x02"              // 17: shop_ptr = 2
    "\x06"              // 18: weapon_ptr = 6
    "\x24"              // 19: prev_pos ref = 36
    "\x28"              // 20: tagged_pos nullable ref -> 40
    "\x00"              // 21: house_pos nullable ref = 0 (null)
    "\x2f"              // 22: mana = 47
    "\x00"              // 23: pad(1)
    "\x01\x02\x00\x00"  // 24: hands[0] = (1, 2, pad(2))
    "\x03\x04\x00\x00"  // 28: hands[1] = (1, 2, pad(2))
    "\x2c\x38"          // 32: pets vec (44, 48)
    "\x3c\x00"          // 34: caves circular list = 60, unused(1)
    "\x58\x63\x00\x00"  // 36: prev_pos = (88, 99, pad(2))
    "\x37\x42\x00\x00"  // 40: tagged_pos = (55, 66, pad(2))
    "\x05\x06\x00\x00"  // 44: pets[0] = (5, 6, pad(2))
    "\x07\x08\x00\x00"  // 48: pets[1] = (7, 8, pad(2))
    "\x09\x0a\x00\x00"  // 52: pets[2] = (9, 10, pad(2))
    "\x00\x00\x00\x00"  // 56: unused
    "\x10\x3e"          // 60: caves[0] = (16, 62)
    "\x12\x40"          // 62: caves[1] = (18, 64)
    "\x14\x42"          // 64: caves[2] = (20, 66)
    "\x16\x3c"          // 66: caves[3] = (22, 60)
    "\x00\x00";         // 68: unused

}  // namespace mempeep::test