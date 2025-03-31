#include "types.hh"

namespace nix {

#if HAVE_LIBCPUID

extern "C" const char ** nix_libutil_cpuid();

StringSet computeLevels()
{
    StringSet levels;
    struct cpu_id_t data;

    const char ** value = nix_libutil_cpuid();
    if (value != nullptr) {
        for (size_t i = 0; value[i] != nullptr; i++) {
            levels.insert(value[i]);
        }
    }

    return levels;
}

#else

StringSet computeLevels()
{
    return StringSet{};
}

#endif // HAVE_LIBCPUID

}
