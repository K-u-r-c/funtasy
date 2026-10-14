#!/usr/bin/env bash
# Headless automated tests (see autoload/dev_auto.gd).
# Usage: tools/run_tests.sh [all|quick|lan|steam]   (env GODOT=/path/to/godot to override)
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=${TEST_LOG_DIR:-${TMPDIR:-/tmp}/funtasy_tests}
mkdir -p "$OUT"
WHAT=${1:-all}
status=0

run() { # name, args...
	local name=$1; shift
	timeout 200 "$GODOT" --headless --path . -- --nosteam "$@" > "$OUT/$name.log" 2>&1
	report "$name"
}

report() {
	local name=$1 log="$OUT/$1.log"
	local errors
	errors=$(grep -E "SCRIPT ERROR|^ERROR:|Parse Error|\[test\] FAIL" "$log" | grep -v "resources still in use\|MCP Bridge" | head -20)
	local summary
	summary=$(grep "\[test\] SUMMARY" "$log" | tail -1)
	if [ -n "$errors" ] || [ -z "$summary" ]; then
		echo "FAIL  $name  ${summary:-no summary}"
		echo "$errors" | sed 's/^/      /'
		status=1
	else
		echo "ok    $name  $summary"
	fi
}

pair() { # name, host-args, client-args
	local name=$1 hargs=$2 cargs=$3
	timeout 200 "$GODOT" --headless --path . -- --nosteam --auto=host --players=2 $hargs > "$OUT/$name-host.log" 2>&1 &
	local hp=$!
	sleep 2
	timeout 200 "$GODOT" --headless --path . -- --nosteam --auto=join $cargs > "$OUT/$name-client.log" 2>&1 &
	local cp=$!
	wait $hp; wait $cp
	report "$name-host"
	report "$name-client"
}

echo "== script check"
if ! timeout 120 "$GODOT" --headless --path . -s tools/check_scripts.gd > "$OUT/check.log" 2>&1; then
	echo "FAIL  check_scripts"; grep -E "BROKEN|SCRIPT ERROR" "$OUT/check.log" | head; status=1
else
	echo "ok    $(grep checked "$OUT/check.log")"
fi

if [ "$WHAT" = all ] || [ "$WHAT" = quick ]; then
	echo "== solo"
	for c in warrior ranger mage priest; do
		run "classes-$c" --auto=solo --class=$c --name=Solo$c --scenario=classes --quit=60
	done
	run gamepad --auto=solo --class=warrior --name=PadTester --scenario=gamepad --quit=60
	run rebind --scenario=rebind --quit=20
	run rebind-check --scenario=rebind_check --quit=20
fi
if [ "$WHAT" = all ] || [ "$WHAT" = lan ]; then
	echo "== LAN (2 instances)"
	pair full-wm "--class=warrior --name=HostW --scenario=full --quit=220" "--class=mage --name=ClientM --quit=220"
	pair full-pr "--class=priest --name=HostP --scenario=full --quit=220" "--class=ranger --name=ClientR --quit=220"
	pair wipe "--class=ranger --name=HostWipe --scenario=wipe --quit=60" "--class=priest --name=ClientWipe --quit=60"
fi
if [ "$WHAT" = steam ]; then
	echo "== Steam"
	timeout 60 "$GODOT" --headless --path . -- --auto=steamhost --quit=40 > "$OUT/steam.log" 2>&1
	report steam
fi
echo "logs: $OUT"
exit $status
