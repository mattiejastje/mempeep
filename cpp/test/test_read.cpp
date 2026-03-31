#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <array>
#include <mempeep/read.hpp>
#include <mempeep/test/memory.hpp>
#include <mempeep/tracers/ok_tracer.hpp>
#include <mempeep/tracers/log_tracer.hpp>
#include <optional>
#include <string_view>

#include "support/mock_game.hpp"

using namespace mempeep;

// truly empty data
// (can't use "" as it includes null terminator)
static constexpr std::array<uint8_t, 0> empty_data{};

using TUInt8 = Primitive<uint8_t>;

TEST_CASE("successful read") {
  static constexpr uint8_t base{4};
  auto reader = test::MockMemoryReader<uint8_t>{test::game_data};
  test::Game game{};
  auto tracer = LogTracer{on_entry_print(std::cout), LogLevel::VALUES};
  CHECK(read<test::TGame>(base, reader, tracer, game));
  SUBCASE("level") { CHECK_EQ(game.level, 17); }
  SUBCASE("message") {
    CHECK_EQ(game.message.size(), 11);
    CHECK_EQ(game.message, std::string("hello world"));
  }
  SUBCASE("player") {
    CHECK_EQ(game.player.health, 123);
    CHECK_EQ(game.player.pos.x, 11);
    CHECK_EQ(game.player.pos.y, 22);
    CHECK_EQ(game.player.target_ptr, 0);
    CHECK_EQ(game.player.shop_ptr, 2);
    CHECK_EQ(game.player.weapon_ptr, 6);
    CHECK_EQ(game.player.prev_pos.x, 88);
    CHECK_EQ(game.player.prev_pos.y, 99);
    CHECK_EQ(game.player.mana, 47);
    SUBCASE("tagged_pos") {
      REQUIRE(game.player.tagged_pos.has_value());
      CHECK_EQ(game.player.tagged_pos->x, 55);
      CHECK_EQ(game.player.tagged_pos->y, 66);
    }
    CHECK(!game.player.house_pos.has_value());
  }
  SUBCASE("hands") {
    CHECK_EQ(game.hands[0].x, 1);
    CHECK_EQ(game.hands[0].y, 2);
    CHECK_EQ(game.hands[1].x, 3);
    CHECK_EQ(game.hands[1].y, 4);
  }
  SUBCASE("pets") {
    REQUIRE_EQ(game.pets.size(), 3);
    CHECK_EQ(game.pets[0].x, 5);
    CHECK_EQ(game.pets[0].y, 6);
    CHECK_EQ(game.pets[1].x, 7);
    CHECK_EQ(game.pets[1].y, 8);
    CHECK_EQ(game.pets[2].x, 9);
    CHECK_EQ(game.pets[2].y, 10);
  }
  SUBCASE("caves") {
    REQUIRE_EQ(game.caves.size(), 4);
    CHECK_EQ(game.caves[0].id, 16);
    CHECK_EQ(game.caves[1].id, 18);
    CHECK_EQ(game.caves[2].id, 20);
    CHECK_EQ(game.caves[3].id, 22);
  }
}

TEST_CASE("failed read: complete failure") {
  auto reader = test::MockMemoryReader<uint8_t>{empty_data};
  test::Game game{};
  OkTracer tracer{};
  CHECK(!read<test::TGame>(0, reader, tracer, game));
}

TEST_CASE("failed read: invalid addresses") {
  static constexpr uint8_t base{4};
  static constexpr std::string_view data{test::game_data, 23};
  auto reader = test::MockMemoryReader<uint8_t>{data};
  test::Game game{};
  OkTracer tracer{};
  CHECK(!read<test::TGame>(base, reader, tracer, game));
  SUBCASE("level") { CHECK_EQ(game.level, 17); }
  SUBCASE("player") {
    CHECK_EQ(game.player.health, 123);
    CHECK_EQ(game.player.pos.x, 11);
    CHECK_EQ(game.player.pos.y, 22);
    CHECK_EQ(game.player.target_ptr, 0);
    CHECK_EQ(game.player.shop_ptr, 2);
    CHECK_EQ(game.player.weapon_ptr, 6);
    CHECK_EQ(game.player.prev_pos.x, 0);  // failed
    CHECK_EQ(game.player.prev_pos.y, 0);  // failed
    CHECK_EQ(game.player.mana, 47);
    SUBCASE("tagged_pos") {
      REQUIRE(game.player.tagged_pos.has_value());  // pointer was not null
      CHECK(game.player.tagged_pos->x == 0);        // failed
      CHECK(game.player.tagged_pos->y == 0);        // failed
    }
    CHECK(!game.player.house_pos.has_value());
  }
}

TEST_CASE("failed read: pad overflow") {
  struct Overflow {};

  using TOverflow = Struct<Overflow, Fields<Pad<0xff>, Pad<0xff>>>;
  auto reader = test::MockMemoryReader<uint8_t>{empty_data};
  Overflow overflow{};
  OkTracer tracer{};
  CHECK(!read<TOverflow>(0, reader, tracer, overflow));
}

TEST_CASE("failed read: null ref") {
  struct Obj {
    uint8_t item;
  };

  using TObj = Struct<Obj, Fields<Field<Ref<TUInt8>, &Obj::item>>>;
  auto reader = test::MockMemoryReader<uint8_t>{"\x00"};
  Obj obj{};
  OkTracer tracer{};
  CHECK(!read<TObj>(0, reader, tracer, obj));
}

TEST_CASE("failed read: missing ref") {
  struct Obj {
    uint8_t item;
  };

  using TObj = Struct<Obj, Fields<Field<Ref<TUInt8>, &Obj::item>>>;
  auto reader = test::MockMemoryReader<uint8_t>{empty_data};
  Obj obj{};
  OkTracer tracer{};
  CHECK(!read<TObj>(0, reader, tracer, obj));
}

TEST_CASE("failed read: missing nullable ref") {
  struct Obj {
    std::optional<uint8_t> item;
  };

  using TObj = Struct<Obj, Fields<Field<NullableRef<TUInt8>, &Obj::item>>>;
  auto reader = test::MockMemoryReader<uint8_t>{empty_data};
  Obj obj{};
  OkTracer tracer{};
  CHECK(!read<TObj>(0, reader, tracer, obj));
}