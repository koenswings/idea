#!/bin/sh
# STUB: idea-usage-export (idea#416 / idea#412 pool-Pi proof only).
# This is NOT Axle's helper v7 command. Do not install it on kits,
# idea, golden idea01, or any host that is not a claimed proof Pi.
# It never reads or writes /var/lib/idea/usage/ and never prints secrets.
#
# Accepts only (via SSH_ORIGINAL_COMMAND or argv):
#   since YYYY-MM-DD
#   archive-and-clear --before YYYY-MM-DD
# Anything else, including an empty command or a shell, is refused.
set -eu

cmd=${SSH_ORIGINAL_COMMAND-}
if [ -z "$cmd" ] && [ "$#" -gt 0 ]; then
    cmd="$*"
fi

case "$cmd" in
    'since '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        day=${cmd#since }
        printf '%s\n' "{\"schema\":\"idea-usage-export-stub/1\",\"stub\":true,\"verb\":\"since\",\"since\":\"${day}\",\"summaries\":[],\"samples\":[]}"
        exit 0
        ;;
    'archive-and-clear --before '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        day=${cmd#archive-and-clear --before }
        printf '%s\n' "{\"schema\":\"idea-usage-export-stub/1\",\"stub\":true,\"verb\":\"archive-and-clear\",\"before\":\"${day}\",\"cleared\":false,\"reason\":\"stub-does-not-modify-files\"}"
        exit 0
        ;;
    *)
        echo "idea-usage-export: refused" >&2
        exit 1
        ;;
esac
