#!/bin/bash
# Linux mirror of tests/Run-Tests.ps1: the Octave stages exactly as Invoke-TestStage
# runs them, the strict C99 stages ported from tests/Test-*.ps1, and the package
# check (its Octave code is read from tests/Test-Package.ps1). The Qt editor stage
# is not run. Usage: tests/run-tests-linux.sh REPO OUTDIR [JOBS] [STAGE...]
# Needs octave-cli, mkoctfile, gcc and git on PATH. Stages run in parallel
# (JOBS, default 6), each with its own TMPDIR; logs and summary.txt go to OUTDIR.
set -u
R="$(cd "$1" && pwd)"; G="$2"; J="${3:-6}"; shift 3 2>/dev/null || shift $#
ONLY=" $* "
rm -rf "$G"; mkdir -p "$G"
OCT="octave-cli --quiet --no-window-system"
SETUP="addpath('$R'); ob_setup('tests');"
CFLAGS=(-std=c99 -O2 -Wall -Wextra -Werror)
{ echo "revision $(git -C "$R" rev-parse HEAD)"; octave-cli --version | head -1; gcc --version | head -1
  head -1 /etc/os-release | cut -d= -f2; echo "started $(date -u +%FT%TZ)"; } > "$G/environment.txt"

cg_stage() {  # DIR MANIFEST PREP VERIFY  (@OUT@ = DIR)
  local d=$1 man=$2 prep=${3//@OUT@/$1} ver=${4//@OUT@/$1} n=0 name source sa
  $OCT --eval "$SETUP $prep" || { echo "PREP FAILED"; return 1; }
  $OCT --eval "c=jsondecode(fileread('$d/$man')); if iscell(c), c=[c{:}]; end; for k=1:numel(c), printf('%s\t%s\t%d\n', c(k).name, c(k).source, c(k).standalone); end" > "$d/list.tsv" || return 1
  while IFS=$'\t' read -r name source sa; do
    local args=("${CFLAGS[@]}"); [ "$sa" = 1 ] && args+=(-DOB_STANDALONE)
    gcc "${args[@]}" "$d/$source" -lm -o "$d/$name.bin" || { echo "COMPILE FAILED $name"; return 1; }
    if [ "$sa" = 1 ]; then "$d/$name.bin" > "$d/$name.csv" || { echo "RUN FAILED $name"; return 1; }
    else "$d/$name.bin" || { echo "RUN FAILED $name"; return 1; }; fi
    n=$((n+1))
  done < "$d/list.tsv"
  echo "compiled (gcc ${CFLAGS[*]}) and ran $n cases"
  $OCT --eval "$SETUP $ver" || { echo "VERIFY FAILED"; return 1; }
}

cin_stage() {  # tests/Test-CInputLookup.ps1
  local d=$1 c
  $OCT --eval "$SETUP test_ob_c_input_lookup('$d'); test_ob_c_number_format('$d');" || return 1
  for c in 0 1; do
    gcc "${CFLAGS[@]}" -pedantic "$d/c-input-lookup-$c.c" -lm -o "$d/c-input-lookup-$c.bin" || { echo "COMPILE FAILED c-input-lookup-$c"; return 1; }
    "$d/c-input-lookup-$c.bin" || { echo "ORACLE FAILED continuous=$c"; return 1; }
  done
  gcc "${CFLAGS[@]}" -pedantic-errors "$d/c-number-format.c" -lm -o "$d/c-number-format.bin" || return 1
  "$d/c-number-format.bin" || return 1
  echo "C input lookup and number formatting verification passed"
}

pkg_stage() {  # tests/Test-Package.ps1, with -nodeps when Octave is older than DESCRIPTION's Depends
  local d=$1 v expr
  v=$(sed -n 's/^Version: *//p' "$R/DESCRIPTION")
  git -C "$R" archive --format=tar.gz --prefix="octave-blocks-$v/" --output="$d/octave-blocks-$v.tar.gz" HEAD || return 1
  expr=$(sed -n '/^\$expression = @"/,/^"@/p' "$R/tests/Test-Package.ps1" | sed '1d;$d')
  expr=${expr//\$folder/$d}; expr=${expr//\$releaseVersion/$v}
  expr=$(sed "s/pkg('install',/pkg('install',pkg_install_args{:},/" <<<"$expr")
  expr="if compare_versions(OCTAVE_VERSION,'11.3.0','<'), printf('Octave %s is below Depends 11.3.0: installing with -nodeps\n',OCTAVE_VERSION); pkg_install_args={'-nodeps'}; else pkg_install_args={}; end; $expr"
  $OCT --eval "$expr"
}

run_stage() {  # NAME KIND ARGS...
  local n=$1 kind=$2; shift 2
  [ "$ONLY" != "  " ] && [[ "$ONLY" != *" $n "* ]] && return 0
  local d="$G/$n" s; mkdir -p "$d/scratch"; s=$(date +%s)
  ( export TMPDIR="$d/scratch" TMP="$d/scratch" TEMP="$d/scratch"; cd "$R" || exit 1
    case $kind in
      oct) $OCT --eval "$SETUP $1" ;;
      cg) cg_stage "$d" "$@" ;;
      cin) cin_stage "$d" ;;
      pkg) pkg_stage "$d" ;;
    esac ) > "$G/$n.log" 2>&1
  local code=$?
  echo "$n exit=$code seconds=$(( $(date +%s)-s ))" >> "$G/summary.txt"
}
throttle() { while [ "$(jobs -rp | wc -l)" -ge "$J" ]; do sleep 1; done; }

STAGES_FILE=$(mktemp)
sed -n "/^\\\$definitions = @(/,/^)/p" "$R/tests/Run-Tests.ps1" | grep -o "Name='[^']*'; Code='[^']*'" | while read -r line; do
  name=$(sed "s/^Name='\([^']*\)'.*/\1/" <<<"$line"); code=$(sed "s/.*Code='\(.*\)'$/\1/" <<<"$line")
  printf '%s\t%s\n' "$name" "$code"
done > "$STAGES_FILE"
while IFS=$'\t' read -r name code; do throttle; run_stage "$name" oct "$code" & done < "$STAGES_FILE"
throttle; run_stage c-codegen cg manifest.json "test_ob_codegen('@OUT@');" "verify_ob_codegen('@OUT@');" &
throttle; run_stage c-combined cg combined-manifest.json "test_ob_combined_codegen('@OUT@',false,false);" "test_ob_combined_codegen('@OUT@',true);" &
throttle; run_stage c-input cin &
throttle; run_stage c-event cg event-manifest.json "test_ob_event_codegen('@OUT@',false,'.*',false);" "test_ob_event_codegen('@OUT@',true);" &
throttle; run_stage c-edges cg event-edge-manifest.json "test_ob_event_codegen_edges('@OUT@',false,false);" "test_ob_event_codegen_edges('@OUT@',true);" &
throttle; run_stage c-hierarchy cg event-hierarchy-manifest.json "test_ob_event_codegen_hierarchy('@OUT@',false,false);" "test_ob_event_codegen_hierarchy('@OUT@',true);" &
throttle; run_stage package pkg &
wait
rm -f "$STAGES_FILE"
echo "finished $(date -u +%FT%TZ)" >> "$G/environment.txt"
sort "$G/summary.txt"
pass=$(grep -c ' exit=0 ' "$G/summary.txt"); total=$(wc -l < "$G/summary.txt")
echo "$pass of $total stages passed (editor stage not run on Linux)"
[ "$pass" -eq "$total" ]
