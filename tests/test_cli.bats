#!/usr/bin/env bats

setup() {
  export CLI="${BATS_TEST_DIRNAME}/../bin/safari"
  export BOOKMARKS_FIXTURE="${BATS_TEST_DIRNAME}/fixtures/bookmarks.plist"
  export MALFORMED_BOOKMARKS="${BATS_TEST_DIRNAME}/fixtures/malformed.plist"
  export SAFARI_BOOKMARKS_FILE="${BOOKMARKS_FIXTURE}"
  export HISTORY_SQL="${BATS_TEST_DIRNAME}/fixtures/history.sql"
  export HISTORY_FIXTURE="${BATS_TEST_TMPDIR}/History.db"
  export MALFORMED_HISTORY="${BATS_TEST_DIRNAME}/fixtures/malformed-history.db"
  sqlite3 "${HISTORY_FIXTURE}" < "${HISTORY_SQL}"
  export SAFARI_HISTORY_FILE="${HISTORY_FIXTURE}"
}

add_relative_history_entries() {
  sqlite3 "${HISTORY_FIXTURE}" <<'SQL'
INSERT INTO history_items (id, url) VALUES
  (3, 'https://recent.example/'),
  (4, 'https://day.example/'),
  (5, 'https://week.example/'),
  (6, 'https://month.example/'),
  (7, 'https://old.example/'),
  (8, 'https://future.example/');

INSERT INTO history_visits (id, history_item, visit_time, title) VALUES
  (4, 3, strftime('%s', 'now') - 978307200 - (30 * 60), 'Recent visit'),
  (5, 4, strftime('%s', 'now') - 978307200 - (3 * 86400), 'Day-old visit'),
  (6, 5, strftime('%s', 'now') - 978307200 - (10 * 86400), 'Week-old visit'),
  (7, 6, strftime('%s', 'now') - 978307200 - (45 * 86400), 'Month-old visit'),
  (8, 7, strftime('%s', 'now') - 978307200 - (70 * 86400), 'Old visit'),
  (9, 8, strftime('%s', 'now') - 978307200 + (60 * 60), 'Future visit');
SQL
}

@test "bookmarks list prints human-readable bookmarks" {
  run "${CLI}" bookmarks list
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Favorites / Example"* ]]
  [[ "${output}" == *"  https://example.com/"* ]]
  [[ "${output}" == *"- Bookmarks Menu / Development / Apple Developer"* ]]
  [[ "${output}" == *"- Bookmarks Menu / Visible title"* ]]
  [[ "${output}" != *"Reading item"* ]]
  [[ "${output}" != *"reading.example"* ]]
}

@test "bookmarks ls is an alias for list" {
  run "${CLI}" bookmarks list
  [ "${status}" -eq 0 ]
  local list_output="${output}"

  run "${CLI}" bookmarks ls
  [ "${status}" -eq 0 ]
  [ "${output}" = "${list_output}" ]
}

@test "bookmarks list --json prints bookmark records" {
  run "${CLI}" bookmarks list --json
  [ "${status}" -eq 0 ]
  [[ "${output}" == \[* ]]
  [[ "${output}" == *'"title" : "Example"'* ]]
  [[ "${output}" == *'"url" : "https://example.com/"'* ]]
  [[ "${output}" == *'"path" : ['* ]]
  [[ "${output}" != *"Reading item"* ]]
}

@test "bookmarks list accepts a file option" {
  unset SAFARI_BOOKMARKS_FILE
  run "${CLI}" bookmarks list --file "${BOOKMARKS_FIXTURE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Favorites / Example"* ]]
}

@test "reading-list list prints Reading List entries" {
  run "${CLI}" reading-list list
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Reading item"* ]]
  [[ "${output}" != *"Reading List / "* ]]
  [[ "${output}" == *"  https://reading.example/"* ]]
  [[ "${output}" != *"Example"* ]]
  [[ "${output}" != *"com.apple.ReadingList"* ]]
}

@test "reading-list ls is an alias for list" {
  run "${CLI}" reading-list list
  [ "${status}" -eq 0 ]
  local list_output="${output}"

  run "${CLI}" reading-list ls
  [ "${status}" -eq 0 ]
  [ "${output}" = "${list_output}" ]
}

@test "reading-list list --json prints Reading List records" {
  run "${CLI}" reading-list list --json
  [ "${status}" -eq 0 ]
  [[ "${output}" == \[* ]]
  [[ "${output}" == *'"title" : "Reading item"'* ]]
  [[ "${output}" == *'"url" : "https://reading.example/"'* ]]
  [[ "${output}" == *'"path" : ['* ]]
  [[ "${output}" != *"Example"* ]]
}

@test "empty reading-list output has the correct label" {
  local empty_fixture="${BATS_TEST_TMPDIR}/empty.plist"
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Children</key><array/></dict></plist>' > "${empty_fixture}"

  run "${CLI}" reading-list list --file "${empty_fixture}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "No Reading List entries found." ]
}

@test "history list prints visits newest first" {
  run "${CLI}" history list
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- https://example.org/article"* ]]
  [[ "${output}" == *"- Middle visit"* ]]
  [[ "${output}" == *"- Older visit"* ]]
  [ "$(printf '%s\n' "${output}" | awk '/^- / { print; exit }')" = "- https://example.org/article" ]
  [ "$(printf '%s\n' "${output}" | awk '/^- / { count++; if (count == 2) { print; exit } }')" = "- Middle visit" ]
}

@test "history ls is an alias for list" {
  run "${CLI}" history list
  [ "${status}" -eq 0 ]
  local list_output="${output}"

  run "${CLI}" history ls
  [ "${status}" -eq 0 ]
  [ "${output}" = "${list_output}" ]
}

@test "history list --json prints visit records" {
  run "${CLI}" history list --json
  [ "${status}" -eq 0 ]
  [[ "${output}" == \[* ]]
  [ "$(printf '%s\n' "${output}" | jq 'length')" -eq 3 ]
  [ "$(printf '%s\n' "${output}" | jq -r '.[0].title')" = "https://example.org/article" ]
  [ "$(printf '%s\n' "${output}" | jq -r '.[0].url')" = "https://example.org/article" ]
  [ "$(printf '%s\n' "${output}" | jq -r '.[0].visited_at')" = "2001-01-01T00:05:00.000Z" ]
}

@test "history list filters visits from the last two hours" {
  add_relative_history_entries

  run "${CLI}" history list --last 2h --json
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | jq 'length')" -eq 1 ]
  [ "$(printf '%s\n' "${output}" | jq -r '.[0].title')" = "Recent visit" ]
}

@test "history list prints filtered human-readable visits" {
  add_relative_history_entries

  run "${CLI}" history list --last 2w
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Recent visit"* ]]
  [[ "${output}" == *"- Week-old visit"* ]]
  [[ "${output}" != *"- Month-old visit"* ]]
}

@test "history list filters visits from the last two days" {
  add_relative_history_entries

  run "${CLI}" history list --json --last 2d
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | jq 'length')" -eq 1 ]
  [ "$(printf '%s\n' "${output}" | jq -r '.[0].title')" = "Recent visit" ]
}

@test "history list filters visits from the last two weeks" {
  add_relative_history_entries

  run "${CLI}" history list --last 2w --json
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | jq 'length')" -eq 3 ]
  [[ "${output}" != *"Month-old visit"* ]]
  [[ "${output}" != *"Future visit"* ]]
}

@test "history list filters visits from the last two months" {
  add_relative_history_entries

  run "${CLI}" history list --last 2mo --json
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | jq 'length')" -eq 4 ]
  [[ "${output}" == *"Month-old visit"* ]]
  [[ "${output}" != *"Old visit"* ]]
  [[ "${output}" != *"Future visit"* ]]
}

@test "history ls accepts a time filter" {
  add_relative_history_entries

  run "${CLI}" history ls --last 2w --json
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | jq 'length')" -eq 3 ]
}

@test "history list returns an empty result for an unmatched time filter" {
  run "${CLI}" history list --last 1h --json
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | jq 'length')" -eq 0 ]
}

@test "history list validates time filters" {
  local duration
  for duration in 0h 1m 1.5h 2y; do
    run "${CLI}" history list --last "${duration}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"invalid history duration '${duration}'"* ]]
  done

  run "${CLI}" history list --last
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"--last requires a duration"* ]]

  run "${CLI}" history list --last -1h
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"--last requires a duration"* ]]

  run "${CLI}" history list --last 1h --last 2h
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"--last may only be specified once"* ]]
}

@test "history list time filters do not modify the database" {
  add_relative_history_entries
  local before
  local after
  before="$(cksum "${HISTORY_FIXTURE}")"

  run "${CLI}" history list --last 2w --json
  [ "${status}" -eq 0 ]

  after="$(cksum "${HISTORY_FIXTURE}")"
  [ "${before}" = "${after}" ]
}

@test "history list accepts a file option" {
  unset SAFARI_HISTORY_FILE
  run "${CLI}" history list --file "${HISTORY_FIXTURE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Older visit"* ]]
}

@test "history list falls back to the URL for an empty title" {
  sqlite3 "${HISTORY_FIXTURE}" "INSERT INTO history_visits (id, history_item, visit_time, title) VALUES (4, 1, 400.0, '');"

  run "${CLI}" history list --json
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | jq -r '.[] | select(.visited_at == "2001-01-01T00:06:40.000Z") | .title')" = "https://example.com/" ]
}

@test "history list rejects an invalid visit time" {
  sqlite3 "${HISTORY_FIXTURE}" "INSERT INTO history_visits (id, history_item, visit_time, title) VALUES (4, 1, 'invalid', 'Bad time');"

  run "${CLI}" history list
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"invalid visit time"* ]]
}

@test "history list does not modify the database" {
  local before
  local after
  before="$(cksum "${HISTORY_FIXTURE}")"

  run "${CLI}" history list --json
  [ "${status}" -eq 0 ]

  after="$(cksum "${HISTORY_FIXTURE}")"
  [ "${before}" = "${after}" ]
}

@test "history list reports a missing database" {
  export SAFARI_HISTORY_FILE="${BATS_TEST_TMPDIR}/does-not-exist.db"
  run "${CLI}" history list
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"History database not found"* ]]
}

@test "history list with --file works when HOME is unset" {
  unset SAFARI_HISTORY_FILE
  run env -u HOME "${CLI}" history list --file "${HISTORY_FIXTURE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Older visit"* ]]
}

@test "list commands reject an option as a --file path" {
  run "${CLI}" bookmarks list --file --json
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"--file requires a path"* ]]

  run "${CLI}" history list --file --json
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"--file requires a path"* ]]
}

@test "history list reports an invalid database" {
  export SAFARI_HISTORY_FILE="${MALFORMED_HISTORY}"
  run "${CLI}" history list
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"could not read or parse"* ]]
}

@test "bookmarks list does not modify the plist" {
  local before
  local after
  before="$(cksum "${BOOKMARKS_FIXTURE}")"

  run "${CLI}" bookmarks list --json
  [ "${status}" -eq 0 ]

  after="$(cksum "${BOOKMARKS_FIXTURE}")"
  [ "${before}" = "${after}" ]
}

@test "bookmarks list reports a missing plist" {
  export SAFARI_BOOKMARKS_FILE="${BATS_TEST_TMPDIR}/does-not-exist.plist"
  run "${CLI}" bookmarks list
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Bookmarks file not found"* ]]
}

@test "bookmarks list with --file works when HOME is unset" {
  unset SAFARI_BOOKMARKS_FILE
  run env -u HOME "${CLI}" bookmarks list --file "${BOOKMARKS_FIXTURE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"- Favorites / Example"* ]]
}

@test "bookmarks list reports an invalid plist" {
  export SAFARI_BOOKMARKS_FILE="${MALFORMED_BOOKMARKS}"
  run "${CLI}" bookmarks list
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"could not read or parse"* ]]
}

@test "help and version are available" {
  run "${CLI}" --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"bookmarks list"* ]]

  run "${CLI}" history --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--last DURATION"* ]]

  run "${CLI}" --version
  [ "${status}" -eq 0 ]
  [[ "${output}" == "safari 0.1.0" ]]
}
