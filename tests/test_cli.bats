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

  run "${CLI}" --version
  [ "${status}" -eq 0 ]
  [[ "${output}" == "safari 0.1.0" ]]
}
