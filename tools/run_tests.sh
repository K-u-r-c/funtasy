#!/usr/bin/env bash
# Headless automated tests (see autoload/dev_auto.gd).
# Usage: tools/run_tests.sh [all|quick|lan|steam]   (env GODOT=/path/to/godot to override)
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
# Line-buffered output: a test instance killed by `timeout` would otherwise lose its last lines.
LB=""
command -v stdbuf > /dev/null && LB="stdbuf -oL -eL"
OUT=${TEST_LOG_DIR:-${TMPDIR:-/tmp}/funtasy_tests}
mkdir -p "$OUT"
WHAT=${1:-all}
status=0

# Every test instance uses its own throw-away profile (user://profiles/test_*), so real
# characters and settings are never touched.
USERDIR=$("$GODOT" --headless --path . -s tools/print_user_dir.gd 2>/dev/null | grep '^USERDIR=' | cut -d= -f2)
if [ -n "$USERDIR" ] && [ -d "$USERDIR/profiles" ]; then
	rm -rf "$USERDIR"/profiles/test_*
fi

# Translations (#32): the CSV lists every key with a valid Polish entry, and Godot builds the
# .translation file from it (generated, not in git).
if ! python3 tools/i18n_extract.py --check > "$OUT/i18n_check.log" 2>&1; then
	echo "FAIL  i18n-check"; sed 's/^/      /' "$OUT/i18n_check.log" | head -20
	status=1
else
	echo "ok    i18n-check"
fi
"$GODOT" --headless --path . --import > "$OUT/import.log" 2>&1

# TEST_ONLY=<regex>: run only the tests whose name matches (e.g. TEST_ONLY='^teleport').
skip() { [ -n "${TEST_ONLY:-}" ] && ! [[ $1 =~ $TEST_ONLY ]]; }

run() { # name, args...
	local name=$1; shift
	skip "$name" && return
	timeout 400 $LB "$GODOT" --headless --path . -- --nosteam --profile=test_$name "$@" > "$OUT/$name.log" 2>&1
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
	skip "$name" && return
	timeout 320 $LB "$GODOT" --headless --path . -- --nosteam --profile=test_$name-host --auto=host --players=2 $hargs > "$OUT/$name-host.log" 2>&1 &
	local hp=$!
	sleep 2
	timeout 320 $LB "$GODOT" --headless --path . -- --nosteam --profile=test_$name-client --auto=join $cargs > "$OUT/$name-client.log" 2>&1 &
	local cp=$!
	wait $hp; wait $cp
	report "$name-host"
	report "$name-client"
}

group() { # name, clients, host-args, client-args (a host and 2-3 clients)
	local name=$1 n=$2 hargs=$3 cargs=$4
	skip "$name" && return
	timeout 320 $LB "$GODOT" --headless --path . -- --nosteam --profile=test_$name-host --auto=host --players=$((n + 1)) $hargs > "$OUT/$name-host.log" 2>&1 &
	local pids=($!)
	sleep 2
	for i in $(seq 1 "$n"); do
		timeout 320 $LB "$GODOT" --headless --path . -- --nosteam --profile=test_$name-client$i --auto=join --name=${name//-/}C$i $cargs > "$OUT/$name-client$i.log" 2>&1 &
		pids+=($!)
		sleep 1
	done
	for pid in "${pids[@]}"; do wait "$pid"; done
	report "$name-host"
	for i in $(seq 1 "$n"); do report "$name-client$i"; done
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
	for c in warrior ranger mage priest; do
		run "skills-$c" --auto=solo --class=$c --name=Skill$c --scenario=skills --quit=200
	done
	run economy --auto=solo --class=warrior --name=Eco --scenario=economy --quit=200
	for c in warrior ranger mage priest; do
		run "talents-$c" --auto=solo --class=$c --name=Tal$c --scenario=talents --quit=120
	done
	run lore --auto=solo --class=priest --name=Lore --scenario=lore --quit=120
	run monsters --auto=solo --class=warrior --name=Mon --scenario=monsters --quit=300
	run bosses --auto=solo --class=mage --name=Bos --scenario=bosses --quit=300
	for c in warrior ranger mage priest; do
		run legendaries-$c --auto=solo --class=$c --name=Leg --scenario=legendaries --quit=360
	done
	run biomes --auto=solo --class=warrior --name=Bio --scenario=biomes --quit=200
	run biomes-sewers --auto=solo --class=ranger --name=Bio --scenario=biomes --biome=sewers --quit=120
	run biomes-foundry --auto=solo --class=priest --name=Bio --scenario=biomes --biome=foundry --quit=120
	run biomes-archives --auto=solo --class=mage --name=Bio --scenario=biomes --biome=archives --quit=120
	run biomes-kurgan --auto=solo --class=warrior --name=Bio --scenario=biomes --biome=kurgan --quit=120
	run primitives --auto=solo --class=mage --name=Prim --scenario=primitives --quit=200
	for c in warrior ranger mage priest; do
		run balance-$c --auto=solo --class=$c --name=Bal --scenario=balance --quit=360
	done
	run ui-layout --auto=solo --class=priest --name=Layout --scenario=ui_layout --quit=90
	run ui-layout-pl --auto=solo --class=priest --name=Layout --scenario=ui_layout --lang=pl --quit=90
	run spouts-sewers --auto=solo --class=ranger --name=Pipes --scenario=spouts --biome=sewers --quit=60
	run spouts-foundry --auto=solo --class=ranger --name=Pipes --scenario=spouts --biome=foundry --quit=60
	run fx --auto=solo --class=mage --name=Sparks --scenario=fx --quit=60
	run party --auto=solo --class=priest --name=Pals --scenario=party --quit=60
	run interact --auto=solo --class=warrior --name=Hands --scenario=interact --quit=90
	run pl-sweep --auto=solo --class=priest --name=Lang --scenario=pl_sweep --quit=200
	run i18n --auto=solo --class=priest --name=Lang --scenario=i18n --quit=120
	run preview --auto=solo --class=mage --name=Aim --scenario=preview --quit=60
	run tooltips --auto=solo --class=warrior --name=Tips --scenario=tooltips --quit=60
	run ui-fit --auto=solo --class=priest --name=Fit --scenario=ui_fit --quit=200
	run ui-fit-pl --auto=solo --class=priest --name=Fit --scenario=ui_fit --lang=pl --quit=200
	run ui-fit-menus --scenario=ui_fit_menus --quit=120
	run ui-fit-menus-pl --scenario=ui_fit_menus --lang=pl --quit=120
	run lighting-rules --auto=solo --class=warrior --name=Lamp --scenario=lighting_rules --quit=150
	run tooltips-pl --auto=solo --class=priest --name=Tips --scenario=tooltips --lang=pl --quit=60
	run gear-names --scenario=gear_names --quit=60
	run loot-rarity --scenario=loot_rarity --quit=200
	run art-check --scenario=art_check --quit=120
	run hero-art --scenario=hero_art --quit=300
	run gamepad-menu --scenario=gamepad_menu --quit=60
	run gamepad --auto=solo --class=warrior --name=PadTester --scenario=gamepad --quit=60
	for c in warrior ranger mage priest; do
		run boons-$c --auto=solo --class=$c --name=Boon --scenario=boons --quit=380
	done
	run gfx --auto=solo --class=warrior --name=Gfx --scenario=gfx --quit=120
	run mods --auto=solo --class=warrior --name=Mods --scenario=mods --quit=200
	run drops --auto=solo --class=warrior --name=Loot --scenario=drops --quit=90
	run altars --auto=solo --class=warrior --name=Pious --scenario=altars --quit=60
	run stacks --auto=solo --class=priest --name=Stacker --scenario=stacks --quit=60
	run resume --auto=solo --class=warrior --name=Back --scenario=resume --quit=90
	run continue --auto=solo --class=ranger --gender=female --name=Saver --scenario=continue --quit=60
	timeout 60 $LB "$GODOT" --headless --path . -- --nosteam --profile=test_rebind --scenario=rebind --quit=20 > "$OUT/rebind.log" 2>&1
	report rebind
	timeout 60 $LB "$GODOT" --headless --path . -- --nosteam --profile=test_rebind --scenario=rebind_check --quit=20 > "$OUT/rebind-check.log" 2>&1
	report rebind-check
fi
if [ "$WHAT" = all ] || [ "$WHAT" = lan ]; then
	echo "== LAN (2 instances)"
	pair full-wm "--class=warrior --name=HostW --scenario=full --boss=morvath --quit=220" "--class=mage --name=ClientM --quit=220"
	pair full-pr "--class=priest --name=HostP --scenario=full --boss=vespera --quit=220" "--class=ranger --name=ClientR --quit=220"
	pair boss "--class=warrior --name=HostB --scenario=boss --boss=morvath --quit=300" "--class=priest --name=ClientB --quit=300"
	pair boss-vespera "--class=mage --name=HostV --scenario=boss --boss=vespera --quit=300" "--class=warrior --name=ClientV --quit=300"
	pair boss-amalgam "--class=mage --name=HostA --scenario=boss --biome=sewers --boss=murk_amalgam --quit=300" "--class=warrior --name=ClientA --quit=300"
	pair boss-ignis "--class=warrior --name=HostI --scenario=boss --biome=foundry --boss=ignis --quit=300" "--class=mage --name=ClientI --quit=300"
	pair boss-vulkania "--class=priest --name=HostU --scenario=boss --biome=foundry --boss=vulkania --quit=300" "--class=ranger --name=ClientU --quit=300"
	pair boss-malazar "--class=mage --name=HostZ --scenario=boss --biome=archives --boss=malazar --quit=300" "--class=warrior --name=ClientZ --quit=300"
	pair boss-devourer "--class=ranger --name=HostD --scenario=boss --biome=archives --boss=memory_devourer --quit=300" "--class=priest --name=ClientD --quit=300"
	pair boss-cernunnos "--class=warrior --name=HostC --scenario=boss --biome=kurgan --boss=cernunnos --quit=300" "--class=priest --name=ClientC --quit=300"
	pair boss-isolde "--class=ranger --name=HostQ --scenario=boss --biome=kurgan --boss=isolde --quit=300" "--class=mage --name=ClientQ --quit=300"
	pair boss-krazik "--class=ranger --name=HostK --scenario=boss --biome=sewers --boss=krazik --quit=300" "--class=priest --name=ClientK --quit=300"
	pair tank "--class=warrior --name=HostT --scenario=tank --quit=120" "--class=mage --name=ClientT --quit=120"
	pair host-leave "--class=mage --name=HostL --scenario=host_leave --quit=60" "--class=warrior --name=ClientL --quit=60"
	pair client-leave "--class=ranger --name=HostC --scenario=client_leave --quit=60" "--class=priest --name=ClientC --quit=60"
	pair continue-lan "--class=priest --name=HostS --scenario=continue_lan --quit=90" "--class=mage --gender=female --name=ClientS --quit=90"
	pair darkness "--class=mage --name=HostD --scenario=darkness --quit=90" "--class=warrior --name=ClientD --quit=90"
	pair anim-lan "--class=warrior --name=HostN --scenario=anim_lan --quit=90" "--class=mage --name=ClientN --quit=90"
	pair skills-lan "--class=warrior --name=HostK --scenario=skills_lan --quit=90" "--class=priest --name=ClientK --quit=90"
	pair economy-lan "--class=warrior --name=HostE --scenario=economy_lan --quit=120" "--class=mage --name=ClientE --quit=120"
	pair fx-lan "--class=priest --name=HostF --scenario=fx_lan --quit=60" "--class=warrior --name=ClientF --quit=60"
	pair target-lan "--class=priest --name=HostT --scenario=target_lan --quit=60" "--class=priest --name=ClientT --quit=60"
	pair lever-lan "--class=ranger --name=HostG --scenario=lever_lan --biome=sewers --quit=60" "--class=priest --name=ClientG --quit=60"
	pair rise-lan "--class=warrior --name=HostR --scenario=rise_lan --quit=90" "--class=mage --name=ClientR --quit=90"
	pair talents-lan "--class=warrior --name=HostT --scenario=talents_lan --quit=60" "--class=ranger --name=ClientT --quit=60"
	pair levelup-lan "--class=priest --name=HostU --scenario=levelup_lan --quit=60" "--class=warrior --name=ClientU --quit=60"
	pair party-lan "--class=priest --name=HostP --scenario=party_lan --quit=60" "--class=warrior --name=ClientP --quit=60"
	pair interact-lan "--class=warrior --name=HostH --scenario=interact_lan --quit=60" "--class=priest --name=ClientH --quit=60"
	pair i18n-lan "--class=mage --name=HostI --scenario=i18n_lan --quit=60" "--class=warrior --name=ClientI --quit=60"
	pair background-lan "--class=warrior --name=HostBg --scenario=background_lan --quit=60" "--class=mage --name=ClientBg --quit=60"
	group teleport-lan 2 "--class=warrior --name=HostTp --scenario=teleport_lan --quit=60" "--class=ranger --quit=60"
	pair smite-lan "--class=priest --name=HostSm --scenario=smite_lan --quit=60" "--class=warrior --name=ClientSm --quit=60"
	pair stacks-lan "--class=warrior --name=HostSt --scenario=stacks_lan --quit=60" "--class=mage --name=ClientSt --quit=60"
	pair resume-lan "--class=priest --name=HostRs --scenario=resume_lan --quit=120" "--class=ranger --name=ClientRs --quit=120"
	pair gfx-lan "--class=priest --name=HostGf --scenario=gfx_lan --quit=60" "--class=mage --name=ClientGf --quit=60"
	pair boons-lan "--class=warrior --name=HostBn --scenario=boons_lan --quit=90" "--class=mage --name=ClientBn --quit=90"
	pair mods-lan "--class=warrior --name=HostMd --scenario=mods_lan --quit=120" "--class=ranger --name=ClientMd --quit=120"
	pair drops-lan "--class=warrior --name=HostDr --scenario=drops_lan --quit=60" "--class=mage --name=ClientDr --quit=60"
	group ghost-lan 2 "--class=warrior --name=HostGh --scenario=ghost_lan --quit=90" "--class=priest --quit=90"
	group marker-lan 3 "--class=warrior --name=HostMk --scenario=marker_lan --quit=60" "--class=warrior --quit=60"
	pair wipe "--class=ranger --name=HostWipe --scenario=wipe --quit=60" "--class=priest --name=ClientWipe --quit=60"
fi
if [ "$WHAT" = steam ]; then
	echo "== Steam"
	timeout 60 $LB "$GODOT" --headless --path . -- --profile=test_steam --auto=steamhost --quit=40 > "$OUT/steam.log" 2>&1
	report steam
fi
echo "logs: $OUT"
exit $status
