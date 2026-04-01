#pragma once

#include <cstddef>
#include <mempeep/descriptors.hpp>

namespace mempeep {

/**
 * @brief Number of bytes a descriptor will advance the address when reading.
 *
 * Various descriptors consume address-sized words, so AddrSize must be
 * provided.
 *
 * @tparam Desc     The descriptor whose remote size is computed.
 * @tparam AddrSize Size in bytes of the remote address type.
 */
template <IsDescriptor Desc, std::size_t AddrSize>
constexpr std::size_t read_size;

template <typename T, std::size_t AddrSize>
constexpr std::size_t read_size<Primitive<T>, AddrSize> = sizeof(T);

template <IsAddress AddrT, std::size_t AddrSize>
constexpr std::size_t read_size<RawAddr<AddrT>, AddrSize> = AddrSize;

template <
  IsDescriptor Desc,
  native_type_t<Desc> Min,
  native_type_t<Desc> Max,
  std::size_t AddrSize>
constexpr std::size_t read_size<Bounded<Desc, Min, Max>, AddrSize>
  = read_size<Desc, AddrSize>;

template <IsDescriptor Desc, std::size_t N, std::size_t AddrSize>
constexpr std::size_t read_size<Array<Desc, N>, AddrSize>
  = N * read_size<Desc, AddrSize>;

template <IsDescriptor Desc, std::size_t AddrSize>
constexpr std::size_t read_size<Ref<Desc>, AddrSize> = AddrSize;

template <IsDescriptor Desc, std::size_t AddrSize>
constexpr std::size_t read_size<NullableRef<Desc>, AddrSize> = AddrSize;

template <IsDescriptor Desc, std::size_t MaxLen, std::size_t AddrSize>
constexpr std::size_t read_size<Vector<Desc, MaxLen>, AddrSize> = 2 * AddrSize;

template <
  IsDescriptor Desc,
  auto Next,
  std::size_t MaxLen,
  std::size_t AddrSize>
inline constexpr std::size_t
  read_size<CircularList<Desc, Next, MaxLen>, AddrSize>
  = AddrSize;

template <typename T, IsFieldsItem... Items, std::size_t AddrSize>
constexpr std::size_t read_size<Struct<T, Fields<Items...>>, AddrSize>
  = []<IsFieldsItem... Is>(std::type_identity<Fields<Is...>>) {
      std::size_t acc = 0;
      (
        [&acc] {
          if constexpr (requires { Is::seek; })
            acc = Is::seek;
          else if constexpr (requires { Is::skip; })
            acc += Is::skip;
          else if constexpr (requires { typename Is::desc_type; })
            acc += read_size<typename Is::desc_type, AddrSize>;
          else
            static_assert(false, "unhandled fields item in read_size");
        }(),
        ...
      );
      return acc;
    }(std::type_identity<Fields<Items...>>{});

}  // namespace mempeep