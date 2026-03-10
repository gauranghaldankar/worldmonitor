#!/usr/bin/env bash
set -euo pipefail

# Sync fork with upstream (koala73/worldmonitor) and push to origin.
# Creates a git tag before merging so you can roll back easily.
#
# Usage:
#   ./update.sh          # fetch, tag, merge, push
#   ./update.sh --dry    # fetch and show what would change (no merge)
#   ./update.sh --list   # list all pre-sync backup tags
#   ./update.sh --rollback pre-sync/2026-03-10_143022  # revert to a tag
#

UPSTREAM="upstream"
BRANCH="main"
TAG_PREFIX="pre-sync"

# ── Helpers ──────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# ── Subcommands ──────────────────────────────────────────────────────

list_tags() {
  echo "Pre-sync backup tags (newest first):"
  echo ""
  git tag -l "${TAG_PREFIX}/*" --sort=-creatordate --format='  %(refname:short)  %(creatordate:short)  %(subject)' | head -30
  count=$(git tag -l "${TAG_PREFIX}/*" | wc -l | tr -d ' ')
  [ "$count" -eq 0 ] && echo "  (none yet — run ./update.sh to create one)"
  echo ""
  echo "To see what changed after a sync:"
  echo "  git diff <tag>..HEAD"
  echo ""
  echo "To roll back:"
  echo "  ./update.sh --rollback <tag>"
}

dry_run() {
  info "Fetching ${UPSTREAM}/${BRANCH}..."
  git fetch "$UPSTREAM" "$BRANCH"

  local_head=$(git rev-parse HEAD)
  upstream_head=$(git rev-parse "${UPSTREAM}/${BRANCH}")

  if [ "$local_head" = "$upstream_head" ]; then
    info "Already up to date. Nothing to do."
    exit 0
  fi

  ahead=$(git rev-list --count "${UPSTREAM}/${BRANCH}..HEAD")
  behind=$(git rev-list --count "HEAD..${UPSTREAM}/${BRANCH}")

  echo ""
  echo "Current branch is ${behind} commit(s) behind and ${ahead} commit(s) ahead of ${UPSTREAM}/${BRANCH}."
  echo ""
  echo "Incoming commits:"
  git log --oneline "HEAD..${UPSTREAM}/${BRANCH}" | head -30
  echo ""
  echo "Run ./update.sh (without --dry) to merge these changes."
}

rollback() {
  local tag="$1"
  git tag -l "$tag" | grep -q . || die "Tag '$tag' not found. Run ./update.sh --list to see available tags."

  info "Current HEAD: $(git log --oneline -1)"
  info "Rolling back to: ${tag} ($(git log --oneline -1 "$tag"))"
  echo ""
  read -rp "This will reset main to ${tag}. Continue? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  git reset --hard "$tag"
  info "Rolled back to ${tag}."
  echo ""
  echo "Local main is now at $(git log --oneline -1)."
  echo "To push this rollback to your fork: git push origin main --force-with-lease"
}

do_sync() {
  # Ensure clean working tree
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "Working tree has uncommitted changes. Commit or stash them first."
  fi

  # Ensure we're on the right branch
  current=$(git branch --show-current)
  [ "$current" = "$BRANCH" ] || die "Not on ${BRANCH} branch (currently on '${current}'). Switch first: git checkout ${BRANCH}"

  # Fetch upstream
  info "Fetching ${UPSTREAM}/${BRANCH}..."
  git fetch "$UPSTREAM" "$BRANCH"

  # Check if there's anything new
  local_head=$(git rev-parse HEAD)
  upstream_head=$(git rev-parse "${UPSTREAM}/${BRANCH}")

  if [ "$local_head" = "$upstream_head" ]; then
    info "Already up to date with ${UPSTREAM}/${BRANCH}. Nothing to do."
    exit 0
  fi

  behind=$(git rev-list --count "HEAD..${UPSTREAM}/${BRANCH}")
  info "${behind} new commit(s) from upstream."

  # Create backup tag
  tag="${TAG_PREFIX}/$(date +%Y-%m-%d_%H%M%S)"
  git tag -a "$tag" -m "Pre-sync backup before merging ${behind} upstream commit(s)"
  info "Created backup tag: ${tag}"

  # Merge
  info "Merging ${UPSTREAM}/${BRANCH}..."
  if git merge "${UPSTREAM}/${BRANCH}" -m "Merge upstream/${BRANCH}: sync $(date +%Y-%m-%d)"; then
    info "Merge successful."
  else
    echo ""
    echo "MERGE CONFLICT detected. Resolve conflicts, then:"
    echo "  git add <resolved-files>"
    echo "  git commit"
    echo "  git push origin ${BRANCH}"
    echo ""
    echo "To abort and roll back:"
    echo "  git merge --abort"
    echo "  (your backup tag: ${tag})"
    exit 1
  fi

  # Push to fork
  info "Pushing to origin/${BRANCH}..."
  git push origin "$BRANCH"

  # Summary
  echo ""
  echo "Sync complete."
  echo "  Backup tag : ${tag}"
  echo "  New commits: ${behind}"
  echo "  To rollback: ./update.sh --rollback ${tag}"
}

# ── Main ─────────────────────────────────────────────────────────────

case "${1:-}" in
  --dry)      dry_run ;;
  --list)     list_tags ;;
  --rollback) [ -n "${2:-}" ] || die "Usage: ./update.sh --rollback <tag>"; rollback "$2" ;;
  --help|-h)
    echo "Usage: ./update.sh [--dry | --list | --rollback <tag> | --help]"
    echo ""
    echo "  (no args)    Fetch upstream, tag current state, merge, push"
    echo "  --dry        Show what would change without merging"
    echo "  --list       List all pre-sync backup tags"
    echo "  --rollback   Reset to a previous backup tag"
    ;;
  "") do_sync ;;
  *)  die "Unknown option: $1. Run ./update.sh --help" ;;
esac
