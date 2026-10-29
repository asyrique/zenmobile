#!/usr/bin/env bash
# Publishes end-to-end screenshots to the ci-screenshots branch and shows them
# inline in the GitHub Actions run summary.
#
# Usage: scripts/ci/publish-screenshots.sh <dir>
#   <dir> holds one folder per artifact (screenshots-android, screenshots-ios),
#   each with NN-step.png files.
# Needs GH_TOKEN with contents: write, and a public repository (the summary
# links to raw.githubusercontent.com).
set -euo pipefail

SRC="$(cd "$1" 2>/dev/null && pwd || true)"
BRANCH=ci-screenshots
KEEP_RUNS="${KEEP_RUNS:-30}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

if [[ -z "$SRC" ]] || [[ -z "$(find "$SRC" -name '*.png' -print -quit)" ]]; then
  echo "No screenshots in this run." >> "$SUMMARY"
  exit 0
fi

RUN_DIR="runs/${GITHUB_RUN_ID}"
WORK="$(mktemp -d)"
cd "$WORK"
git init -q
git remote add origin "${PUBLISH_REMOTE:-https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

publish() {
  if git fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then
    git checkout -q -B "$BRANCH" FETCH_HEAD
  else
    git checkout -q --orphan "$BRANCH"
    git rm -rqf . 2>/dev/null || true
  fi
  rm -rf "$RUN_DIR"
  mkdir -p "$RUN_DIR"
  for platform_dir in "$SRC"/*/; do
    platform="$(basename "$platform_dir")"
    platform="${platform#screenshots-}"
    mkdir -p "$RUN_DIR/$platform"
    cp "$platform_dir"*.png "$RUN_DIR/$platform/" 2>/dev/null || true
  done
  # Drop all but the newest runs (run ids increase).
  if [[ -d runs ]]; then
    ls -1 runs | sort -n | head -n "-$KEEP_RUNS" | sed 's|^|runs/|' | xargs -r git rm -rq --
  fi
  git add -A
  git commit -q -m "Screenshots for ${GITHUB_REPOSITORY} run ${GITHUB_RUN_ID} (${GITHUB_SHA:0:7})"
  git push -q origin "HEAD:refs/heads/$BRANCH"
}

# Another run may push in between; retry from a fresh fetch.
for attempt in 1 2 3; do
  if publish; then break; fi
  [[ $attempt == 3 ]] && { echo "Could not push screenshots" >&2; exit 1; }
  sleep $((attempt * 5))
done

BASE="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${BRANCH}/${RUN_DIR}"
{
  echo "## Screenshots"
  for platform_dir in "$RUN_DIR"/*/; do
    platform="$(basename "$platform_dir")"
    case "$platform" in
      ios) echo "### iOS" ;;
      android) echo "### Android" ;;
      *) echo "### $platform" ;;
    esac
    echo "<p>"
    for png in $(ls "$platform_dir" | sort); do
      name="${png%.png}"
      echo "<a href=\"$BASE/$platform/$png\"><img src=\"$BASE/$platform/$png\" width=\"180\" alt=\"$name\" title=\"$name\"></a>"
    done
    echo "</p>"
  done
} >> "$SUMMARY"
