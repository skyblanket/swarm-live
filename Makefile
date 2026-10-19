# swarm-live — LiveView framework + swarmUI for swarmrt
# Requires sibling ../swarmrt with bin/swc + bin/libswarmrt.a built.

SWC := ../swarmrt/bin/swc

EXAMPLES := counter todo router chat feed showcase canvas arena flock
BINS := $(addprefix bin/,$(EXAMPLES))

LIB_SOURCES := src/liveview.sw src/ui.sw src/client.sw src/ArenaJs.sw src/FlockJs.sw

.PHONY: all clean
all: $(BINS)

bin/%: src/%.sw $(LIB_SOURCES)
	@mkdir -p bin
	$(SWC) build $< -o $@

clean:
	rm -rf bin
