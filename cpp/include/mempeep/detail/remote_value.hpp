#pragma once

#include <mempeep/detail/concepts/address.hpp>
#include <mempeep/detail/concepts/descriptor.hpp>

namespace mempeep {

/**
 * @brief A remote address paired with the descriptor of the value it locates.
 *
 * Serves as the entry point for @ref read(), so that the descriptor does not
 * need to be specified separately at the call site.
 *
 * Can be constructed directly from a known address:
 * @code
 * read(RemoteValue<TData, uint32_t>{base_address}, reader, tracer, foo);
 * @endcode
 *
 * Can also obtained as the result of reading an @ref Addr descriptor inside a
 * larger structure, for deferred reading:
 * @code
 * RemoteValue<TData, uint32_t> addr = ...; // obtained from a prior read
 * Data data{};
 * read(addr, reader, tracer, data);
 * @endcode
 *
 * When present as a field in a native struct via @ref Addr, @p TypedAddr
 * intentionally appears as the field type. This reflects that deferred
 * reading is a hybrid concept: the native value is a remote address paired
 * with knowledge of what lives there, and a plain integer would hide that
 * intent.
 *
 * The underlying address is accessible via the @p address member if needed,
 * for example to perform bounds checks or to pass to external APIs. Direct
 * arithmetic on the address is intentionally not supported to prevent
 * accidental misuse; use @ref read_at() for indexed access into arrays.
 *
 * @tparam Desc  Descriptor of the value that lives at the stored address.
 *               Determines how the value is read when passed to @ref read().
 * @tparam AddrT The address type. Must satisfy @ref IsAddress and must match
 *               the address type of the memory reader passed to @ref read().
 */
template <IsDescriptor Desc, IsAddress AddrT>
struct RemoteValue {
  AddrT address;
};

}  // namespace mempeep
