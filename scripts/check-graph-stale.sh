#!/bin/bash
HASH_FILE=/home/pi/idea/logs/last-graphify-hash
CURRENT=$(git -C /home/pi/idea rev-parse HEAD 2>/dev/null)
LAST=$(cat "$HASH_FILE" 2>/dev/null)
if [ "$CURRENT" != "$LAST" ]; then
  echo "$CURRENT" > "$HASH_FILE"
  nohup bash /home/pi/idea/scripts/rebuild-graph.sh \
    >> /home/pi/idea/logs/graphify-rebuild.log 2>&1 &
fi
