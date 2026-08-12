#!/usr/bin/env bash
#
# Guard the property `make all-coverage` sells: its harness runs every
# requirements-based test and nothing else. gnattest drops an `--ignore` entry
# it cannot match without a word, and a suite or routine it fails to pick up
# leaves a smaller test set behind a report that still reads 100%.
#
# Usage: check-reqs-harness.sh MAIN_SUITE IGNORE_FILE REQS_SRC_DIR

set -euo pipefail

main_suite=${1:?usage: $0 MAIN_SUITE IGNORE_FILE REQS_SRC_DIR}
ignore_file=${2:?usage: $0 MAIN_SUITE IGNORE_FILE REQS_SRC_DIR}
reqs_src=${3:?usage: $0 MAIN_SUITE IGNORE_FILE REQS_SRC_DIR}

harness_dir=$(dirname "$main_suite")
status=0
expected=()

# One test package per LLR file, named for it (tests/reqs/README.md rule 3):
# llr_4_controller_1_vehicle_tests.ads -> Llr_4_Controller_1_Vehicle_Tests.
ada_unit_name() {
  awk -F_ 'BEGIN { OFS = "_" }
           { for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)
             print }' <<<"$1"
}

for spec in "$reqs_src"/llr_*_tests.ads; do
  [ -e "$spec" ] || break
  unit=$(basename "$spec" .ads)
  name=$(ada_unit_name "$unit")
  expected+=("$name")

  if ! grep -q "Add_Test (Result'Access, $name.Suite.Suite);" "$main_suite"; then
    printf 'ERROR: %s: %s is not registered.\n' "$main_suite" "$name" >&2
    printf '       Its routines would not run, and the coverage they produce\n' >&2
    printf '       is what the report counts as requirements-based.\n' >&2
    status=1
    continue
  fi

  # gnattest registers one test case per routine the spec declares.
  suite_body="$harness_dir/$unit-suite.adb"
  declared=$(grep -cE '^ *procedure Test_[0-9]' "$spec")
  registered=$(grep -c 'Add_Test' "$suite_body")

  if [ "$declared" -ne "$registered" ]; then
    printf 'ERROR: %s: %s declares %s routine(s), %s registered.\n' \
      "$main_suite" "$name" "$declared" "$registered" >&2
    printf '       %s is the harness gnattest generated.\n' "$suite_body" >&2
    status=1
  fi
done

if [ ${#expected[@]} -eq 0 ]; then
  printf 'ERROR: no llr_*_tests.ads under %s.\n' "$reqs_src" >&2
  exit 1
fi

# Anything else gnattest registered is a generated skeleton suite, which the
# ignore list was meant to keep out of this harness.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  for name in "${expected[@]}"; do
    [[ $line == *"$name.Suite.Suite"* ]] && continue 2
  done
  printf 'ERROR: %s: a generated skeleton suite reached the harness:\n' \
    "$main_suite" >&2
  printf '       %s\n' "$line" >&2
  printf '       Its coverage would count as requirements-based. Add the\n' >&2
  printf '       source it was generated from to %s.\n' "$ignore_file" >&2
  status=1
done < <(grep 'Add_Test' "$main_suite")

if [ $status -eq 0 ]; then
  printf 'requirements harness: %s suite(s), every routine registered, no skeletons\n' \
    "${#expected[@]}"
fi

exit $status
