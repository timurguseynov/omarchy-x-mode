// writeStateFile without Hyprland. A close that reports failure must not publish
// the new body: fclose is the flush, and a failed flush is not a finished write.
#include "hyprbars/stateFile.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

namespace fs = std::filesystem;

static int failures = 0;

static void check(const char* name, bool ok) {
    if (!ok) {
        std::cerr << "FAIL " << name << "\n";
        failures++;
    }
}

static int failClose(FILE* file) {
    std::fclose(file);
    return EOF;
}

static std::string readAll(const fs::path& path) {
    std::ifstream in(path);
    return std::string(std::istreambuf_iterator<char>(in), {});
}

int main() {
    const fs::path dir = fs::temp_directory_path() / ("xmode-state-" + std::to_string(getpid()));
    fs::create_directories(dir);
    const fs::path target = dir / "state";

    check("setup", writeStateFile(target.string(), "old\n"));
    check("close-fails", !writeStateFile(target.string(), "new\n", failClose));
    check("close-keeps-old", readAll(target) == "old\n");
    check("close-ok", writeStateFile(target.string(), "next\n") && readAll(target) == "next\n");

    fs::remove_all(dir);
    if (failures > 0)
        return 1;
    std::cout << "write_state ok\n";
    return 0;
}
