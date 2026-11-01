# Else exist specifically for clang
ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wno-c++11-narrowing
INCLUDES = `pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon`
LIBS =

SRC = main.cpp barDeco.cpp BarPassElement.cpp snap.cpp dragSession.cpp
OBJ = $(SRC:.cpp=.o)
DEP = $(OBJ:.o=.d)
TARGET = hyprbars.so

# One object per source, so `make -j` has five things to do instead of one. The
# single rule this used to have handed all five files to one g++ invocation,
# which compiles them one after another: 47 seconds of wall clock for 45 seconds
# of CPU on six cores, and `make -j` changed nothing because there was only ever
# one job.
all: $(TARGET)

$(TARGET): $(OBJ)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $^ -o $@ $(LIBS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(EXTRA_FLAGS) $(INCLUDES) -MMD -MP -c $< -o $@

-include $(DEP)

clean:
	rm -f ./$(TARGET) $(OBJ) $(DEP)

meson-build:
	mkdir -p build
	cd build && meson .. && ninja

.PHONY: all meson-build clean
