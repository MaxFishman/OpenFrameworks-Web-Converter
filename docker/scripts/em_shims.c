/*
 * em_shims.c — Emscripten build shims
 *
 * openFrameworks' prebuilt emscripten libraries reference reallocarray(),
 * a BSD/glibc extension that emscripten's musl libc does not export to the
 * linker. Since oF links with -sERROR_ON_UNDEFINED_SYMBOLS=1, the link fails
 * with "undefined symbol: reallocarray". We provide the standard definition
 * (realloc with a multiplication-overflow guard) so the symbol resolves.
 *
 * The build worker drops a copy of this file into every project's src/ before
 * compiling. The __EMSCRIPTEN__ guard makes it a no-op on other platforms.
 */
#ifdef __EMSCRIPTEN__
#include <stdlib.h>
#include <errno.h>

void *reallocarray(void *ptr, size_t nmemb, size_t size) {
    if (size != 0 && nmemb > ((size_t)-1) / size) {
        errno = ENOMEM;
        return NULL;
    }
    return realloc(ptr, nmemb * size);
}
#endif
