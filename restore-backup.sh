#!/usr/bin/env bash
#
# restore-backup.sh — restore paulmillr projects from the signed backup repo
#
# Steps:
#   1. Shallow-clone https://github.com/paulmillr/backup (last commit only)
#   2. Verify the pinned GPG signer and every archive checksum
#   3. Validate and unpack the newest archive set (YYYY.MM.DD*.tar.xz)
#   4. Place projects into ~/Developer/{noble,scure,micro}/<name>,
#      dropping prefixes (scure-base -> scure/base)
#   5. For each newly restored project: init recursive submodules,
#      npm ci, npm run build
#
# Portable: works on Debian/Linux and macOS (bash 3.2+, shasum fallback).
# Requires: git, curl, gpg, tar + xz, node/npm, and standard Unix tools.
#
# Usage:
#   bash restore-backup.sh ~/Developer
#   bash restore-backup.sh ~/Developer --update

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

usage() {
  printf 'Usage: %s DESTINATION [--update]\n' "${0##*/}"
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

case "$#" in
  0)
    usage >&2
    die "Destination argument is required."
    ;;
  1)
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
    esac
    DEV_DIR="$1"
    UPDATE_REPOS=0
    ;;
  2)
    DEV_DIR="$1"
    if [ "$2" != "--update" ]; then
      usage >&2
      die "Unknown option: $2"
    fi
    UPDATE_REPOS=1
    ;;
  *)
    usage >&2
    die "Too many arguments."
    ;;
esac

BACKUP_REPO="${BACKUP_REPO:-https://github.com/paulmillr/backup.git}"

# This is Paul Miller's primary signing-key fingerprint. Keep it in the
# audited script: accepting an environment override would undo the pin.
EXPECTED_SIGNING_FINGERPRINT="78A89CD10959782E23FF8447697079DA6878B89B"
PGP_KEY_URL="https://github.com/paulmillr.gpg"

case "$DEV_DIR" in
  /*) ;;
  *) die "DEV_DIR must be an absolute path: $DEV_DIR" ;;
esac
[ "$DEV_DIR" != "/" ] || die "Refusing to use / as DEV_DIR."

for tool in awk curl find git gpg mktemp mv npm readlink sed tar xz; do
  command -v "$tool" >/dev/null 2>&1 || die "Required tool missing: $tool"
done

TMP_ROOT="${TMPDIR:-/tmp}"
[ -d "$TMP_ROOT" ] || die "Temporary directory does not exist: $TMP_ROOT"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
WORK_DIR="$(mktemp -d "$TMP_ROOT/restore-backup.XXXXXXXX")" \
  || die "Could not create a temporary directory."
chmod 700 "$WORK_DIR"
UI_LOG_FILE="$WORK_DIR/commands.log"
: >"$UI_LOG_FILE"

cleanup() {
  local status=$?
  [ "$status" -eq 0 ] || dump_logs
  # Only remove the exact, private directory created above.
  case "${WORK_DIR:-}" in
    "$TMP_ROOT"/restore-backup.*)
      [ ! -e "$WORK_DIR" ] || rm -rf -- "$WORK_DIR"
      ;;
    *)
      warn "Refusing to clean unexpected temporary path: ${WORK_DIR:-<empty>}"
      ;;
  esac
}
trap cleanup EXIT

# Ignore ambient Git configuration that could redirect the clone or install
# hooks. Repository-local configuration is handled defensively below.
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CONFIG_COUNT \
      GIT_CONFIG_PARAMETERS GIT_DIR GIT_INDEX_FILE GIT_NAMESPACE \
      GIT_OBJECT_DIRECTORY GIT_TEMPLATE_DIR GIT_WORK_TREE
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_TERMINAL_PROMPT=0

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

archive_has_safe_paths() {
  local archive="$1"
  local listing="$2"
  local member metadata entry_type

  tar -tf "$archive" >"$listing" || return 1
  [ -s "$listing" ] || return 1

  while IFS= read -r member || [ -n "$member" ]; do
    case "$member" in
      ""|/*|..|../*|*/../*|*/..)
        warn "Unsafe archive member in $archive: $member"
        return 1
        ;;
    esac
  done <"$listing"

  # Reject devices, FIFOs, sockets, and hard links before extraction.
  tar -tvf "$archive" >"$listing.types" || return 1
  while IFS= read -r metadata || [ -n "$metadata" ]; do
    entry_type="${metadata%"${metadata#?}"}"
    case "$entry_type" in
      -|d|l) ;;
      *)
        warn "Unsupported archive entry type '$entry_type' in $archive"
        return 1
        ;;
    esac
  done <"$listing.types"
}

symlink_stays_in_tree() {
  local root="$1"
  local link="$2"
  local relative target parent combined component
  local depth=0
  local old_ifs="$IFS"
  local -a components

  relative="${link#"$root"/}"
  target="$(readlink "$link")" || return 1
  case "$target" in
    ""|/*) return 1 ;;
  esac

  case "$relative" in
    */*) parent="${relative%/*}" ;;
    *) parent="." ;;
  esac
  combined="$parent/$target"

  IFS='/' read -r -a components <<<"$combined"
  IFS="$old_ifs"
  for component in "${components[@]}"; do
    case "$component" in
      ""|.) ;;
      ..)
        depth=$((depth - 1))
        [ "$depth" -ge 0 ] || return 1
        ;;
      *) depth=$((depth + 1)) ;;
    esac
  done
}

validate_extracted_tree() {
  local root="$1"
  local special link

  special="$(find "$root" ! -type f ! -type d ! -type l -print | sed -n '1p')"
  if [ -n "$special" ]; then
    warn "archive created an unsupported file type: $special"
    return 1
  fi

  while IFS= read -r link; do
    if ! symlink_stays_in_tree "$root" "$link"; then
      warn "archive contains a symlink escaping its extraction tree: $link"
      return 1
    fi
  done < <(find "$root" -type l -print)

  # Never retain setuid or setgid bits from an archive.
  find "$root" \( -type f -o -type d \) -exec chmod u-s,g-s {} +
}

# ---------------------------------------------------------------------------
# 1. Clone (last commit only)
# ---------------------------------------------------------------------------
run_step "clone signed backup" \
  git -c core.hooksPath=/dev/null \
      clone --depth 1 --single-branch --no-tags -- "$BACKUP_REPO" "$WORK_DIR/backup" \
  || exit 1
cd "$WORK_DIR/backup"

# ---------------------------------------------------------------------------
# 2. Verify the signature and every archive listed by the signed manifest.
# ---------------------------------------------------------------------------
[ -f shasum.txt ] && [ ! -L shasum.txt ] \
  || die "A regular shasum.txt was not found in the backup repo."
[ -f shasum.txt.asc ] && [ ! -L shasum.txt.asc ] \
  || die "A regular shasum.txt.asc was not found in the backup repo."

export GNUPGHOME="$WORK_DIR/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
run_step "download signing key" \
  curl -fsSL --proto '=https' --tlsv1.2 "$PGP_KEY_URL" \
       -o "$WORK_DIR/signing-key.asc" || exit 1
run_step "import signing key" \
  gpg --batch --no-autostart --no-tty --quiet \
      --import "$WORK_DIR/signing-key.asc" || exit 1
capture_step "verify manifest signature" \
  gpg --batch --no-autostart --no-tty --status-fd 1 \
      --verify shasum.txt.asc shasum.txt || exit 1
GPG_STATUS="$CAPTURED_OUTPUT"
VALID_PRIMARY_FINGERPRINT="$(printf '%s\n' "$GPG_STATUS" \
  | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {print $NF}')"
[ "$VALID_PRIMARY_FINGERPRINT" = "$EXPECTED_SIGNING_FINGERPRINT" ] \
  || die "Signature is valid but not from the pinned signing key."
ok "pinned signer" "${EXPECTED_SIGNING_FINGERPRINT:0:12}"

pending "verify archive checksums"
printf '\n[verify archive checksums]\n' >>"$UI_LOG_FILE"
ARCHIVES=()
MANIFEST_RE='^([0-9a-f]{64})  ([0-9]{4}\.[0-9]{2}\.[0-9]{2}(-[A-Za-z0-9._-]+)?\.tar\.xz)$'
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ $MANIFEST_RE ]] \
    || die "Malformed or unsafe line in signed manifest: $line"
  expected="${BASH_REMATCH[1]}"
  archive="${BASH_REMATCH[2]}"

  [ -f "$archive" ] && [ ! -L "$archive" ] \
    || die "Manifest archive is missing or is not a regular file: $archive"
  for seen in "${ARCHIVES[@]}"; do
    [ "$seen" != "$archive" ] || die "Duplicate archive in manifest: $archive"
  done

  actual="$(sha256_file "$archive" 2>>"$UI_LOG_FILE")"
  [ "$actual" = "$expected" ] || die "Checksum verification FAILED: $archive"
  ARCHIVES[${#ARCHIVES[@]}]="$archive"
done < shasum.txt
[ "${#ARCHIVES[@]}" -gt 0 ] || die "The signed manifest contains no archives."

# Refuse date-named archives that are present but omitted from the manifest;
# otherwise such a file could be selected as the newest without verification.
shopt -s nullglob
for archive in [0-9]*.tar.xz; do
  listed=0
  for seen in "${ARCHIVES[@]}"; do
    [ "$seen" != "$archive" ] || listed=1
  done
  [ "$listed" -eq 1 ] || die "Archive is not covered by signed manifest: $archive"
done
shopt -u nullglob
ok "verify archive checksums" "${#ARCHIVES[@]} archives"

# ---------------------------------------------------------------------------
# 3. Validate and unpack the newest archive set. Each archive gets an isolated
#    staging directory to prevent entries in one archive affecting another.
# ---------------------------------------------------------------------------
TITLE=""
for archive in "${ARCHIVES[@]}"; do
  candidate="${archive:0:10}"
  if [ -z "$TITLE" ] || [[ "$candidate" > "$TITLE" ]]; then
    TITLE="$candidate"
  fi
done
[ -n "$TITLE" ] || die "No archive (*.tar.xz) found in backup repo."
info "latest archive set  $TITLE"

UNPACK_ROOT="$WORK_DIR/unpacked"
mkdir -p "$UNPACK_ROOT"
STAGES=()
for archive in "${ARCHIVES[@]}"; do
  [ "${archive:0:10}" = "$TITLE" ] || continue
  stage="$UNPACK_ROOT/$archive"
  listing="$WORK_DIR/$archive.list"
  mkdir -p "$stage"
  run_step "validate $archive" archive_has_safe_paths "$archive" "$listing" \
    || exit 1
  run_step "extract $archive" \
    tar --no-same-owner --no-same-permissions -xf "$archive" -C "$stage" \
    || exit 1
  run_step "inspect $archive" validate_extracted_tree "$stage" || exit 1
  STAGES[${#STAGES[@]}]="$stage"
done
[ "${#STAGES[@]}" -gt 0 ] || die "No archives selected for $TITLE."

# ---------------------------------------------------------------------------
# 4. Place projects into $DEV_DIR/{noble,scure,micro}/<suffix>.
# ---------------------------------------------------------------------------
mkdir -p "$DEV_DIR"
DEV_DIR="$(cd "$DEV_DIR" && pwd -P)"
[ "$DEV_DIR" != "/" ] || die "Refusing to use / as DEV_DIR."

for namespace in noble scure micro; do
  namespace_dir="$DEV_DIR/$namespace"
  [ ! -L "$namespace_dir" ] || die "Destination namespace is a symlink: $namespace_dir"
  if [ -e "$namespace_dir" ]; then
    [ -d "$namespace_dir" ] || die "Destination namespace is not a directory: $namespace_dir"
  else
    mkdir "$namespace_dir"
  fi
done

# Git operations use the signed snapshot by default. Updating branches from
# unsigned network state is deliberately opt-in via UPDATE_REPOS=1.
git_for_restore() {
  git -c core.hooksPath=/dev/null \
      -c core.fsmonitor=false \
      -c protocol.ext.allow=never \
      -c protocol.file.allow=never "$@"
}

process_project() (
  local project="$1"
  local name
  cd "$project" || return 1
  name="$(basename "$project")"

  if [ -L .git ]; then
    bad "$name has a symlinked .git"
    return 1
  elif [ -d .git ] || [ -f .git ]; then
    if [ "$UPDATE_REPOS" -eq 1 ]; then
      run_step "update $name" \
        git_for_restore pull --ff-only --no-recurse-submodules || return 1
    fi
    if [ -f .gitmodules ] && [ ! -L .gitmodules ]; then
      run_step "sync submodules for $name" \
        git_for_restore submodule sync --recursive || return 1
      run_step "initialize submodules for $name" \
        git_for_restore submodule update --init --recursive || return 1
    elif [ -L .gitmodules ]; then
      bad "$name has a symlinked .gitmodules"
      return 1
    fi
  else
    info "$name: Git steps skipped; not a repository"
  fi

  if [ -f package.json ] && [ ! -L package.json ]; then
    if [ -L package-lock.json ] || [ -L npm-shrinkwrap.json ]; then
      bad "$name has a symlinked npm lockfile"
      return 1
    elif [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
      run_step "install $name" npm ci --no-audit --no-fund || return 1
      run_step "build $name" npm run build --if-present || return 1
    else
      bad "$name has no regular npm lockfile"
      return 1
    fi
  elif [ -L package.json ]; then
    bad "$name has a symlinked package.json"
    return 1
  else
    info "$name: npm steps skipped; no package.json"
  fi
)

validate_project_symlinks() {
  local project="$1"
  local link

  while IFS= read -r link; do
    symlink_stays_in_tree "$project" "$link" || return 1
  done < <(find "$project" -type l -print)
}

FOUND=0
CANDIDATES=0
RESTORED_PROJECTS=()
FAILED=""
for stage in "${STAGES[@]}"; do
  while IFS= read -r src; do
    FOUND=1
    name="$(basename "$src")"
    if [[ ! "$name" =~ ^(noble|scure|micro)-([A-Za-z0-9][A-Za-z0-9._-]*)$ ]]; then
      die "Unsafe project directory name: $name"
    fi
    prefix="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]}"
    dest="$DEV_DIR/$prefix/$suffix"

    if [ -e "$dest" ] || [ -L "$dest" ]; then
      info "$name skipped; destination already exists"
      continue
    fi
    CANDIDATES=$((CANDIDATES + 1))

    if ! validate_project_symlinks "$src"; then
      bad "$name contains a symlink that would escape after placement"
      FAILED="$FAILED$dest"$'\n'
      continue
    fi
    if ! process_project "$src"; then
      FAILED="$FAILED$dest"$'\n'
      continue
    fi
    if ! validate_project_symlinks "$src"; then
      bad "$name contains a symlink that would escape after placement"
      FAILED="$FAILED$dest"$'\n'
      continue
    fi

    mv -- "$src" "$dest"
    RESTORED_PROJECTS[${#RESTORED_PROJECTS[@]}]="$dest"
    ok "restore $name" "$prefix/$suffix"
  done < <(find "$stage" -mindepth 2 -maxdepth 2 -type d \
             \( -name 'noble-*' -o -name 'scure-*' -o -name 'micro-*' \) -print)
done

[ "$FOUND" -eq 1 ] || die "No noble-*/scure-*/micro-* projects found in archive."

# ---------------------------------------------------------------------------
# 5. Report the atomic restore result. Failed projects remain only in the
#    temporary staging area and are removed on exit, so a retry starts cleanly.
# ---------------------------------------------------------------------------
if [ "$CANDIDATES" -eq 0 ]; then
  info "all matching projects already exist; nothing new was built"
fi

printf '\n'
if [ -n "$FAILED" ]; then
  bad "projects not restored:"
  printf '%s' "$FAILED" | sed 's/^/    /' >&2
  exit 1
fi
ok "restore complete" "${#RESTORED_PROJECTS[@]} projects → $DEV_DIR"
