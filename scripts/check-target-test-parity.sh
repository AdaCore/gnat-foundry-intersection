#!/usr/bin/env bash
#
# Guard the property `make test-target` sells: every test citing a requirement id
# runs on target. A unit left out of the cross harness must therefore cite none
# in its test bodies -- and must itself exist, because gnattest drops an entry it
# cannot match without a word, so a typo would silently shorten the run.
#
# Usage: check-target-test-parity.sh IGNORE_FILE SRC_DIR TESTS_DIR

set -euo pipefail

ignore_file=${1:?usage: $0 IGNORE_FILE SRC_DIR TESTS_DIR}
src_dir=${2:?usage: $0 IGNORE_FILE SRC_DIR TESTS_DIR}
tests_dir=${3:?usage: $0 IGNORE_FILE SRC_DIR TESTS_DIR}

# A test declares its trace with a `--@covers` tag (see engine/requirements'
# ada_tests.py, the authority on the syntax). A payload starting with `none`
# cites nothing -- the rest of that line is prose, and a requirement id may well
# appear in it as the reason. So match the tag, not any mention of an id.
COVERS_RE='--[[:space:]]*@covers[[:space:]]'
NONE_RE='--[[:space:]]*@covers[[:space:]]+none([[:space:]:_-]|$)'
ID_RE='(hlr|llr)_[a-z0-9_]*\.[0-9]+'

# The enumerated exceptions: requirement citations knowingly verified host-only.
# Every entry carries its reason and its follow-up, and an entry that stops being
# needed is itself an error -- so this list cannot outlive what justifies it, and
# it stays the only way a citation escapes the target run.
WAIVED_CITATIONS=()

declare -A waiver_used=()

status=0
entries=0

while IFS= read -r unit || [ -n "$unit" ]; do
  [ -n "$unit" ] || continue
  entries=$((entries + 1))

  if ! find "$src_dir" -type f -name "$unit" | grep -q .; then
    printf 'ERROR: %s: no source named "%s" under %s.\n' \
      "$ignore_file" "$unit" "$src_dir" >&2
    printf '       gnattest ignores an unmatched entry silently, so the list must\n' >&2
    printf '       hold bare filenames only -- no comments, no typos.\n' >&2
    status=1
    continue
  fi

  while IFS= read -r body; do
    [ -n "$body" ] || continue
    # `-e`: both patterns start with `--`, which grep would read as an option.
    while IFS= read -r line; do
      [ -n "$line" ] || continue

      unwaived=()
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        if [[ " ${WAIVED_CITATIONS[*]} " == *" $id "* ]]; then
          waiver_used["$id"]=1
        else
          unwaived+=("$id")
        fi
      done < <(grep -oE -e "$ID_RE" <<<"$line" || true)

      if [ ${#unwaived[@]} -gt 0 ]; then
        printf 'ERROR: %s is left out of the cross harness but cites a requirement id:\n' \
          "$body" >&2
        printf '       %s\n' "$line" >&2
        printf '       not waived: %s\n' "${unwaived[*]}" >&2
        status=1
      fi
    done < <(grep -nE -e "$COVERS_RE" "$body" | grep -vE -e "$NONE_RE" || true)
  done < <(find "$tests_dir" -type f -name "${unit%.*}-test_data*.ad[bs]")
done <"$ignore_file"

if [ "$entries" -eq 0 ]; then
  printf 'ERROR: %s lists no units at all.\n' "$ignore_file" >&2
  status=1
fi

# A waiver nothing needs is as much a defect as a missing one: it would silently
# license the next citation to go off target.
for id in "${WAIVED_CITATIONS[@]}"; do
  if [ -z "${waiver_used[$id]:-}" ]; then
    printf 'ERROR: %s is waived in %s but no ignored unit cites it.\n' \
      "$id" "$(basename "$0")" >&2
    printf '       Drop the waiver -- the citation it excused is gone.\n' >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  printf 'target test parity: %s host-only unit(s), %s waived citation(s): %s\n' \
    "$entries" "${#WAIVED_CITATIONS[@]}" "${WAIVED_CITATIONS[*]}"
fi

exit "$status"
