#pragma once

#include <cstdio>
#include <string>

#include <unistd.h>

// Write a small state file whole or not at all. `fopen(path, "w")` truncates
// first, so a reader -- the shell watches these files -- can see an empty file
// between the open and the write, and "off" or "no preview" for a frame reads as
// a bug in the pack. The temp file is a sibling, so the rename stays on one
// filesystem; the Lua side does the same (layout.write_atomic).
//
// The temp name is unique per attempt -- the writing process and a counter -- and
// not `path + ".tmp"`: two writes of the same file would otherwise open and
// truncate one shared temp, and the second rename would put the first writer's
// half-written body on the target. Each attempt therefore either lands whole or
// removes its own temp, and never touches the target or another writer's temp.
// `closeFile` is the flush. A failure there means the temp is not the whole
// text, so it must not be renamed over the target. Production passes fclose;
// a unit test passes a closer that reports failure.
inline bool writeStateFile(const std::string& path, const std::string& text, int (*closeFile)(FILE*) = std::fclose) {
    static size_t seq = 0;
    const auto    tmp = path + "." + std::to_string((long)getpid()) + "-" + std::to_string(++seq) + ".tmp";
    FILE*         f   = std::fopen(tmp.c_str(), "w");
    if (!f)
        return false;
    const bool wrote  = std::fputs(text.c_str(), f) >= 0;
    const bool closed = closeFile(f) == 0;
    if (!wrote || !closed || std::rename(tmp.c_str(), path.c_str()) != 0) {
        std::remove(tmp.c_str());
        return false;
    }
    return true;
}
