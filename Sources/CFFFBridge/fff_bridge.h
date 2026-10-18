#ifndef FFF_BRIDGE_H
#define FFF_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

/* C API of native/fff-bridge, the slice of fff (https://github.com/dmtrKovalenko/fff)
   that roto uses. Keep in sync with native/fff-bridge/src/lib.rs. */

typedef struct Bridge FffBridge;

/* Called once per result, best first. `name` is only valid during the call. */
typedef void (*FffBridgeMatch)(const char *name, int32_t score, void *context);

/* Indexes `base_dir` and opens the frecency database at `frecency_db` (NULL to
   skip frecency). NULL on failure. Scanning runs in the background. */
FffBridge *fff_bridge_open(const char *base_dir, const char *frecency_db);

void fff_bridge_close(FffBridge *bridge);

/* Waits up to `timeout_ms` for the scan; with `full`, starts a new one first.
   Returns whether the scan finished. */
bool fff_bridge_rescan(FffBridge *bridge, uint64_t timeout_ms, bool full);

/* Reports up to `limit` matches for `query`; an empty query lists everything
   by frecency. Returns how many names matched in total. */
uint32_t fff_bridge_search(FffBridge *bridge, const char *query, uint32_t limit,
                           FffBridgeMatch callback, void *context);

/* Records that `name` was opened, so it ranks higher next time. */
bool fff_bridge_track(FffBridge *bridge, const char *name);

#endif
