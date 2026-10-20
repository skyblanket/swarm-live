#!/bin/sh
# Run a built demo with the workarounds for open swarmrt issues:
#   - ignore SIGPIPE: needed before swarmrt#20 was fixed (main >= ae943e8 handles it); harmless after
#   - 4 scheduler threads: each idle scheduler costs ~2% of a core (swarmrt#4) and a hot
#     shared ETS table scales backwards across schedulers (swarmrt#58); 4 gave the best
#     frame rate at the lowest CPU for the Flock demo (override: SW_SCHEDULERS=n)
#
#   scripts/run.sh flock        # after: make bin/flock
cd "$(dirname "$0")/.." || exit 1
trap '' PIPE
SW_SCHEDULERS="${SW_SCHEDULERS:-4}" exec "./bin/$1"
