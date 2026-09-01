#!/usr/bin/env bash
#
# Query paulmillr's public GitHub repositories, clone the eligible projects
# into ./current, and create two date-named archives:
#
#   YYYY.MM.DD-noble.tar.xz  noble* except noble-ed25519/noble-secp256k1
#   YYYY.MM.DD.tar.xz        everything else, including those two exceptions
#
# Repository names are shown without clone commands. When stdin is a terminal,
# the user can proceed, cancel, or supply a comma-separated skip list.
# Non-interactive runs proceed with every listed repository.
#
# Usage:
#   ./backup.sh             Create archives and refresh unsigned shasum.txt
#   ./backup.sh --checksum  Regenerate shasum.txt and shasum.txt.asc

if [ -z "${BASH_VERSION:-}" ]; then
  echo "ERROR: run this script with bash: bash $0" >&2
  exit 1
fi

set -euo pipefail
umask 077
export LC_ALL=C

UI_TTY=0
[ -t 1 ] && UI_TTY=1
UI_LOG_FILE=""
UI_LOG_DUMPED=0
if [ "$UI_TTY" -eq 1 ]; then
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_GRAY='\033[38;5;8m'
  C_RESET='\033[0m'
else
  C_RED=''
  C_GREEN=''
  C_GRAY=''
  C_RESET=''
fi

pending() {
  if [ "$UI_TTY" -eq 1 ]; then
    printf '  %b· %s…%b' "$C_GRAY" "$1" "$C_RESET"
  fi
  return 0
}

ok() {
  local label="$1"
  local detail="${2:-}"
  if [ "$UI_TTY" -eq 1 ]; then
    printf '\r\033[2K  %b✓%b %s' "$C_GREEN" "$C_RESET" "$label"
    [ -z "$detail" ] || printf '  %b%s%b' "$C_GRAY" "$detail" "$C_RESET"
    printf '\n'
  else
    printf '  ok   %s%s\n' "$label" "${detail:+  $detail}"
  fi
}

bad() {
  if [ "$UI_TTY" -eq 1 ]; then
    printf '\r\033[2K  %b✗ %s%b\n' "$C_RED" "$1" "$C_RESET" >&2
  else
    printf '  FAIL %s\n' "$1" >&2
  fi
}

info() {
  if [ "$UI_TTY" -eq 1 ]; then
    printf '  %b· %s%b\n' "$C_GRAY" "$1" "$C_RESET"
  else
    printf '  info %s\n' "$1"
  fi
}

warn() { info "$*"; }

dump_logs() {
  local line
  [ "$UI_LOG_DUMPED" -eq 0 ] || return 0
  UI_LOG_DUMPED=1
  [ -n "$UI_LOG_FILE" ] && [ -s "$UI_LOG_FILE" ] || return 0
  printf '\n  %bcommand logs%b\n' "$C_GRAY" "$C_RESET" >&2
  while IFS= read -r line || [ -n "$line" ]; do
    printf '  %b│%b %s\n' "$C_GRAY" "$C_RESET" "$line" >&2
  done <"$UI_LOG_FILE"
}

die() {
  bad "$*"
  exit 1
}

log_command() {
  local arg
  [ -n "$UI_LOG_FILE" ] || return 0
  printf '\n[%s]\n  $' "$1" >>"$UI_LOG_FILE"
  shift
  for arg in "$@"; do
    printf ' %q' "$arg" >>"$UI_LOG_FILE"
  done
  printf '\n' >>"$UI_LOG_FILE"
}

run_step() {
  local label="$1"
  local status
  shift
  pending "$label"
  log_command "$label" "$@"
  if "$@" >>"$UI_LOG_FILE" 2>&1; then
    ok "$label"
    return 0
  else
    status=$?
    bad "$label"
    return "$status"
  fi
}

capture_step() {
  local label="$1"
  local status
  shift
  pending "$label"
  log_command "$label" "$@"
  if CAPTURED_OUTPUT="$("$@" 2>>"$UI_LOG_FILE")"; then
    ok "$label"
    return 0
  else
    status=$?
    bad "$label"
    return "$status"
  fi
}

usage() {
  printf 'Usage: %s [--checksum]\n' "${0##*/}"
}

case "$#" in
  0) MODE="backup" ;;
  1)
    case "$1" in
      --checksum) MODE="checksum" ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "Unknown option: $1" ;;
    esac
    ;;
  *) usage >&2; die "Too many arguments." ;;
esac

for tool in chmod dirname mktemp mv rm; do
  command -v "$tool" >/dev/null 2>&1 || die "Required tool missing: $tool"
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SIGNING_KEY_FINGERPRINT="78A89CD10959782E23FF8447697079DA6878B89B"

UI_TMP_ROOT="${TMPDIR:-/tmp}"
[ -d "$UI_TMP_ROOT" ] || die "Temporary directory does not exist: $UI_TMP_ROOT"
UI_TMP_ROOT="$(cd "$UI_TMP_ROOT" && pwd -P)"
UI_LOG_DIR="$(mktemp -d "$UI_TMP_ROOT/backup-ui.XXXXXXXX")" \
  || die "Could not create UI log directory."
UI_LOG_FILE="$UI_LOG_DIR/commands.log"
: >"$UI_LOG_FILE"
NOBLE_PARTIAL=""
GENERAL_PARTIAL=""

cleanup_main() {
  local status=$?
  [ "$status" -eq 0 ] || dump_logs
  case "${NOBLE_PARTIAL:-}" in
    "$SCRIPT_DIR"/.*.partial.*) [ ! -e "$NOBLE_PARTIAL" ] || rm -f -- "$NOBLE_PARTIAL" ;;
  esac
  case "${GENERAL_PARTIAL:-}" in
    "$SCRIPT_DIR"/.*.partial.*) [ ! -e "$GENERAL_PARTIAL" ] || rm -f -- "$GENERAL_PARTIAL" ;;
  esac
  case "${UI_LOG_DIR:-}" in
    "$UI_TMP_ROOT"/backup-ui.*) [ ! -e "$UI_LOG_DIR" ] || rm -rf -- "$UI_LOG_DIR" ;;
  esac
}
trap cleanup_main EXIT

regenerate_checksums() (
  local sign_mode="${1:-sign}"
  local checksum_tool temp_dir manifest signature archive
  local archive_re='^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(-[A-Za-z0-9._-]+)?\.tar\.xz$'
  local -a archives

  case "$sign_mode" in
    sign|no-sign) ;;
    *) die "Internal error: invalid checksum mode: $sign_mode" ;;
  esac

  if command -v sha256sum >/dev/null 2>&1; then
    checksum_tool="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    checksum_tool="shasum"
  else
    die "Required tool missing: sha256sum or shasum"
  fi

  if [ "$sign_mode" = "sign" ]; then
    command -v gpg >/dev/null 2>&1 || die "Required tool missing: gpg"
  fi
  [ ! -L "$SCRIPT_DIR/shasum.txt" ] \
    || die "Refusing to replace symlink: $SCRIPT_DIR/shasum.txt"
  [ ! -L "$SCRIPT_DIR/shasum.txt.asc" ] \
    || die "Refusing to replace symlink: $SCRIPT_DIR/shasum.txt.asc"
  if [ -e "$SCRIPT_DIR/shasum.txt" ]; then
    [ -f "$SCRIPT_DIR/shasum.txt" ] \
      || die "Checksum destination is not a regular file: $SCRIPT_DIR/shasum.txt"
  fi
  if [ -e "$SCRIPT_DIR/shasum.txt.asc" ]; then
    [ -f "$SCRIPT_DIR/shasum.txt.asc" ] \
      || die "Signature destination is not a regular file: $SCRIPT_DIR/shasum.txt.asc"
  fi

  temp_dir="$(mktemp -d "$SCRIPT_DIR/.backup-checksum.XXXXXXXX")" \
    || die "Could not create checksum staging directory."
  manifest="$temp_dir/shasum.txt"
  signature="$temp_dir/shasum.txt.asc"

  cleanup_checksum_staging() {
    case "$temp_dir" in
      "$SCRIPT_DIR"/.backup-checksum.*) rm -rf -- "$temp_dir" ;;
      *) warn "Refusing to clean unexpected path: $temp_dir" ;;
    esac
  }
  trap cleanup_checksum_staging EXIT

  cd "$SCRIPT_DIR"
  shopt -s nullglob
  archives=([0-9]*.tar.xz)
  shopt -u nullglob
  [ "${#archives[@]}" -gt 0 ] || die "No date-named .tar.xz archives found."

  : >"$manifest"
  for archive in "${archives[@]}"; do
    [[ "$archive" =~ $archive_re ]] \
      || die "Archive has an unsupported name: $archive"
    [ -f "$archive" ] && [ ! -L "$archive" ] \
      || die "Archive is missing or is not a regular file: $archive"

    pending "checksum $archive"
    log_command "checksum $archive" "$checksum_tool" "$archive"
    if [ "$checksum_tool" = "sha256sum" ]; then
      if sha256sum "$archive" >>"$manifest" 2>>"$UI_LOG_FILE"; then
        ok "checksum $archive"
      else
        bad "checksum $archive"
        return 1
      fi
    else
      if shasum -a 256 "$archive" >>"$manifest" 2>>"$UI_LOG_FILE"; then
        ok "checksum $archive"
      else
        bad "checksum $archive"
        return 1
      fi
    fi
  done

  # Publish the manifest before invoking GPG so shasum.txt is regenerated even
  # if signing or pinentry fails. Remove the now-stale old signature first.
  chmod 644 "$manifest"
  rm -f -- "$SCRIPT_DIR/shasum.txt.asc"
  mv -- "$manifest" "$SCRIPT_DIR/shasum.txt"
  ok "write shasum.txt" "${#archives[@]} archives"

  if [ "$sign_mode" = "no-sign" ]; then
    ok "checksum manifest ready" "${#archives[@]} archives; unsigned"
    return 0
  fi

  if ! run_step "sign shasum.txt" \
      gpg --local-user "$SIGNING_KEY_FINGERPRINT" --armor --detach-sign \
          --output "$signature" "$SCRIPT_DIR/shasum.txt"; then
    return 1
  fi
  run_step "verify shasum.txt signature" \
    gpg --verify "$signature" "$SCRIPT_DIR/shasum.txt" || return 1
  chmod 644 "$signature"
  mv -- "$signature" "$SCRIPT_DIR/shasum.txt.asc"
  ok "checksum manifest ready" "${#archives[@]} archives"
)

if [ "$MODE" = "checksum" ]; then
  regenerate_checksums sign
  exit 0
fi

for tool in awk basename curl date git mkdir tar wc xz; do
  command -v "$tool" >/dev/null 2>&1 || die "Required tool missing: $tool"
done

human_size() {
  local bytes
  bytes="$(wc -c <"$1")"
  bytes="${bytes//[[:space:]]/}"

  awk -v bytes="$bytes" 'BEGIN {
    split("B KiB MiB GiB TiB", units, " ")
    size = bytes + 0
    unit = 1
    while (size >= 1024 && unit < 5) {
      size /= 1024
      unit++
    }
    if (unit == 1) {
      printf "%d %s", size, units[unit]
    } else {
      printf "%.1f %s", size, units[unit]
    }
  }'
}

if command -v jq >/dev/null 2>&1; then
  JSON_PARSER="jq"
elif command -v node >/dev/null 2>&1; then
  JSON_PARSER="node"
  warn "jq is unavailable; using Node.js to parse GitHub responses"
else
  die "Required JSON parser missing: install jq or Node.js"
fi

validate_repo_response() {
  if [ "$JSON_PARSER" = "jq" ]; then
    jq -e 'type == "array" and all(.[];
      (.name | type == "string") and
      (.archived | type == "boolean") and
      (.fork | type == "boolean"))' >/dev/null
  else
    node -e '
      let input = "";
      process.stdin.setEncoding("utf8");
      process.stdin.on("data", chunk => input += chunk);
      process.stdin.on("end", () => {
        try {
          const repos = JSON.parse(input);
          const valid = Array.isArray(repos) && repos.every(repo =>
            repo !== null && typeof repo === "object" &&
            typeof repo.name === "string" &&
            typeof repo.archived === "boolean" &&
            typeof repo.fork === "boolean");
          if (!valid) process.exitCode = 1;
        } catch (_) {
          process.exitCode = 1;
        }
      });
    '
  fi
}

repo_response_length() {
  if [ "$JSON_PARSER" = "jq" ]; then
    jq -r 'length'
  else
    node -e '
      let input = "";
      process.stdin.setEncoding("utf8");
      process.stdin.on("data", chunk => input += chunk);
      process.stdin.on("end", () => {
        process.stdout.write(String(JSON.parse(input).length));
      });
    '
  fi
}

eligible_repo_names() {
  if [ "$JSON_PARSER" = "jq" ]; then
    jq -r '.[] | select(.archived == false and .fork == false) | .name'
  else
    node -e '
      let input = "";
      process.stdin.setEncoding("utf8");
      process.stdin.on("data", chunk => input += chunk);
      process.stdin.on("end", () => {
        JSON.parse(input)
          .filter(repo => repo.archived === false && repo.fork === false)
          .forEach(repo => process.stdout.write(repo.name + "\n"));
      });
    '
  fi
}

check_xz_support() {
  local tmp_root="${TMPDIR:-/tmp}"
  local test_dir test_archive result=1

  [ -d "$tmp_root" ] || return 1
  tmp_root="$(cd "$tmp_root" && pwd -P)" || return 1
  test_dir="$(mktemp -d "$tmp_root/backup-xz-test.XXXXXXXX")" || return 1
  test_archive="$test_dir/test.tar.xz"
  mkdir "$test_dir/input"

  if XZ_OPT=-0 tar -cJf "$test_archive" -C "$test_dir" input \
     && xz -t "$test_archive" \
     && tar -tf "$test_archive" >/dev/null; then
    result=0
  fi

  case "$test_dir" in
    "$tmp_root"/backup-xz-test.*) rm -rf -- "$test_dir" ;;
    *) return 1 ;;
  esac
  return "$result"
}

run_step "check .tar.xz support" check_xz_support || exit 1

CURRENT_DIR="$SCRIPT_DIR/current"
TITLE="$(date -u +%Y.%m.%d)"
NOBLE_ARCHIVE="$SCRIPT_DIR/$TITLE-noble.tar.xz"
GENERAL_ARCHIVE="$SCRIPT_DIR/$TITLE.tar.xz"

is_ignored_repo() {
  case "$1" in
    backup|test-repo|unused-test-repo|paulmillr|paulmillr.github.io|\
    acvp-vectors|eth-vectors|qr-code-vectors|noble-hashes-vectors|\
    post-quantum-vectors|dotfiles-vsix|aesscr|git-sha256-repo-test|\
    integration-tests)
      return 0
      ;;
    *) return 1 ;;
  esac
}

REPOS=()
URLS=()
page=1
while :; do
  api_url="https://api.github.com/users/paulmillr/repos?type=owner&sort=full_name&direction=asc&per_page=100&page=$page"
  capture_step "fetch GitHub repositories (page $page)" \
    curl -fsSL --proto '=https' --tlsv1.2 \
         -H 'Accept: application/vnd.github+json' \
         -H 'X-GitHub-Api-Version: 2022-11-28' \
         "$api_url" || exit 1
  response="$CAPTURED_OUTPUT"
  printf '%s\n' "$response" | validate_repo_response 2>>"$UI_LOG_FILE" \
    || die "GitHub returned an invalid repository response on page $page."

  page_count="$(printf '%s\n' "$response" | repo_response_length 2>>"$UI_LOG_FILE")"
  while IFS= read -r repo; do
    [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
      || die "GitHub returned an unsafe repository name: $repo"
    is_ignored_repo "$repo" && continue

    for seen in "${REPOS[@]}"; do
      [ "$seen" != "$repo" ] || die "GitHub returned a duplicate repository: $repo"
    done
    REPOS[${#REPOS[@]}]="$repo"
    URLS[${#URLS[@]}]="git@github.com:paulmillr/$repo.git"
  done < <(printf '%s\n' "$response" | eligible_repo_names)

  [ "$page_count" -eq 100 ] || break
  page=$((page + 1))
  [ "$page" -le 10 ] || die "GitHub repository pagination exceeded 10 pages."
done

[ "${#REPOS[@]}" -gt 0 ] || die "GitHub returned no eligible repositories."

printf 'Projects (%s):\n' "${#REPOS[@]}"
for repo in "${REPOS[@]}"; do
  printf '  %s\n' "$repo"
done

SKIPPED_REPOS=()
if [ -t 0 ]; then
  printf 'Clone the listed projects and create both archives?\n' >&2
  printf '[y = all / N = cancel / s = choose projects to skip] ' >&2
  if ! IFS= read -r answer; then
    printf '\n' >&2
    die "Could not read confirmation."
  fi
  case "$answer" in
    y|Y|yes|YES|Yes) ;;
    s|S|skip|SKIP|Skip)
      printf 'Projects to skip (comma-separated): ' >&2
      if ! IFS= read -r skip_input; then
        printf '\n' >&2
        die "Could not read the skip list."
      fi
      [ -n "$skip_input" ] || die "The skip list is empty."

      IFS=',' read -r -a requested_skips <<<"$skip_input"
      for requested in "${requested_skips[@]}"; do
        # Repository names cannot contain whitespace, so removing it allows
        # input such as: qr,nip44, jsbt
        requested="${requested//[[:space:]]/}"
        [ -n "$requested" ] || die "The skip list contains an empty name."

        found=0
        for repo in "${REPOS[@]}"; do
          [ "$repo" != "$requested" ] || found=1
        done
        [ "$found" -eq 1 ] || die "Unknown repository in skip list: $requested"

        for skipped in "${SKIPPED_REPOS[@]}"; do
          [ "$skipped" != "$requested" ] \
            || die "Duplicate repository in skip list: $requested"
        done
        SKIPPED_REPOS[${#SKIPPED_REPOS[@]}]="$requested"
      done
      ;;
    *) info "cancelled; no projects were cloned"; exit 0 ;;
  esac
fi

should_skip() {
  local candidate="$1"
  local skipped

  for skipped in "${SKIPPED_REPOS[@]}"; do
    [ "$skipped" != "$candidate" ] || return 0
  done
  return 1
}

SELECTED_COUNT=0
SELECTED_NOBLE_COUNT=0
SELECTED_GENERAL_COUNT=0
for repo in "${REPOS[@]}"; do
  should_skip "$repo" && continue
  SELECTED_COUNT=$((SELECTED_COUNT + 1))
  case "$repo" in
    noble-ed25519|noble-secp256k1)
      SELECTED_GENERAL_COUNT=$((SELECTED_GENERAL_COUNT + 1))
      ;;
    noble*)
      SELECTED_NOBLE_COUNT=$((SELECTED_NOBLE_COUNT + 1))
      ;;
    *)
      SELECTED_GENERAL_COUNT=$((SELECTED_GENERAL_COUNT + 1))
      ;;
  esac
done
[ "$SELECTED_COUNT" -gt 0 ] || die "All listed repositories were skipped."
[ "$SELECTED_NOBLE_COUNT" -gt 0 ] \
  || die "The skip list leaves no projects for the noble archive."
[ "$SELECTED_GENERAL_COUNT" -gt 0 ] \
  || die "The skip list leaves no projects for the general archive."

if [ "${#SKIPPED_REPOS[@]}" -gt 0 ]; then
  info "skipping ${#SKIPPED_REPOS[@]} project(s): ${SKIPPED_REPOS[*]}"
fi

[ ! -e "$CURRENT_DIR" ] && [ ! -L "$CURRENT_DIR" ] \
  || die "Refusing to replace existing path: $CURRENT_DIR"
[ ! -e "$NOBLE_ARCHIVE" ] && [ ! -L "$NOBLE_ARCHIVE" ] \
  || die "Refusing to replace existing archive: $NOBLE_ARCHIVE"
[ ! -e "$GENERAL_ARCHIVE" ] && [ ! -L "$GENERAL_ARCHIVE" ] \
  || die "Refusing to replace existing archive: $GENERAL_ARCHIVE"

mkdir "$CURRENT_DIR"

NOBLE_PATHS=()
GENERAL_PATHS=()
index=0
while [ "$index" -lt "${#REPOS[@]}" ]; do
  repo="${REPOS[$index]}"
  url="${URLS[$index]}"
  destination="$CURRENT_DIR/$repo"

  if should_skip "$repo"; then
    index=$((index + 1))
    continue
  fi

  run_step "clone $repo" \
    git -c core.hooksPath=/dev/null clone --no-tags -- "$url" "$destination" \
    || exit 1
  [ -d "$destination" ] && [ ! -L "$destination" ] \
    || die "Clone did not create a regular directory: $destination"

  case "$repo" in
    noble-ed25519|noble-secp256k1)
      GENERAL_PATHS[${#GENERAL_PATHS[@]}]="current/$repo"
      ;;
    noble*)
      NOBLE_PATHS[${#NOBLE_PATHS[@]}]="current/$repo"
      ;;
    *)
      GENERAL_PATHS[${#GENERAL_PATHS[@]}]="current/$repo"
      ;;
  esac
  index=$((index + 1))
done

[ "${#NOBLE_PATHS[@]}" -gt 0 ] || die "No projects were selected for the noble archive."
[ "${#GENERAL_PATHS[@]}" -gt 0 ] || die "No projects were selected for the general archive."

NOBLE_PARTIAL="$(mktemp "$SCRIPT_DIR/.$TITLE-noble.tar.xz.partial.XXXXXXXX")"
GENERAL_PARTIAL="$(mktemp "$SCRIPT_DIR/.$TITLE.tar.xz.partial.XXXXXXXX")"

create_archive() (
  local output="$1"
  shift
  cd "$SCRIPT_DIR"
  XZ_OPT="${XZ_OPT:--9}" tar -cJf "$output" -- "$@"
)

run_step "archive $(basename "$NOBLE_ARCHIVE")" \
  create_archive "$NOBLE_PARTIAL" "${NOBLE_PATHS[@]}" || exit 1
run_step "archive $(basename "$GENERAL_ARCHIVE")" \
  create_archive "$GENERAL_PARTIAL" "${GENERAL_PATHS[@]}" || exit 1

# Publish only after both archives were created successfully.
[ ! -e "$NOBLE_ARCHIVE" ] && [ ! -L "$NOBLE_ARCHIVE" ] \
  || die "Archive appeared while backup was running: $NOBLE_ARCHIVE"
[ ! -e "$GENERAL_ARCHIVE" ] && [ ! -L "$GENERAL_ARCHIVE" ] \
  || die "Archive appeared while backup was running: $GENERAL_ARCHIVE"
mv -- "$NOBLE_PARTIAL" "$NOBLE_ARCHIVE"
NOBLE_PARTIAL=""
mv -- "$GENERAL_PARTIAL" "$GENERAL_ARCHIVE"
GENERAL_PARTIAL=""
chmod 644 "$NOBLE_ARCHIVE" "$GENERAL_ARCHIVE"

regenerate_checksums no-sign

NOBLE_SIZE="$(human_size "$NOBLE_ARCHIVE")"
GENERAL_SIZE="$(human_size "$GENERAL_ARCHIVE")"

printf '\n'
ok "backup complete" "${#REPOS[@]} listed, $SELECTED_COUNT archived"
info "projects  $CURRENT_DIR"
info "noble     $NOBLE_ARCHIVE ($NOBLE_SIZE)"
info "general   $GENERAL_ARCHIVE ($GENERAL_SIZE)"
