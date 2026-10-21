# swarm-live — LiveView framework + swarmUI for swarmrt
# Requires sibling ../swarmrt with bin/swc + bin/libswarmrt.a built.

SWC ?= ../swarmrt/bin/swc

EXAMPLES := counter todo router chat feed showcase canvas arena flock observer_demo life
BINS := $(addprefix bin/,$(EXAMPLES))

LIB_SOURCES := src/LiveView.sw src/UI.sw src/Client.sw src/ArenaJs.sw src/FlockJs.sw src/ObserverJs.sw src/Observer.sw src/LifeJs.sw

.PHONY: all clean run-%

# make run-flock  (builds, then runs with the swarmrt-issue workarounds; see scripts/run.sh)
run-%: bin/%
	./scripts/run.sh $*
all: $(BINS)

bin/%: src/%.sw $(LIB_SOURCES)
	@mkdir -p bin
	$(SWC) build $< -o $@

clean:
	rm -rf bin
