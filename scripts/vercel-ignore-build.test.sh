#!/usr/bin/env bash
# Tests for scripts/vercel-ignore-build.sh (Vercel Ignored Build Step).
# Exit 0 = skip the build, exit 1 = build. Run: bash scripts/vercel-ignore-build.test.sh
set -u
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vercel-ignore-build.sh"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
fails=0
tmp=""

setup() {
  tmp="$(mktemp -d)"
  cd "$tmp" || exit 2
  git init -q
  # Rename detection on, so dropping --no-renames reproduces the original bug.
  git config diff.renames true
  mkdir -p src/app src/lib docs
  printf 'export default function Page() {\n  return null;\n}\n' > src/app/page.tsx
  printf '# Notes\n' > docs/notes.md
  printf 'export const example = 1;\n' > docs/example.ts
  printf '# Readme\n' > README.md
  git add -A && git commit -q -m base
  base="$(git rev-parse HEAD)"
}

commit() { git add -A && git commit -q --allow-empty -m change; }

# check NAME EXPECTED_STATUS [STDERR_REGEX]; runs the script with $prev.
check() {
  local name="$1" want="$2" re="${3:-}" got err
  err="$(VERCEL_GIT_PREVIOUS_SHA="$prev" bash "$script" 2>&1 >/dev/null)"
  got=$?
  if [ "$got" != "$want" ]; then
    echo "not ok - $name (exit $got, want $want)"; fails=$((fails + 1))
  elif [ -n "$re" ] && ! grep -Eq "$re" <<< "$err"; then
    echo "not ok - $name (stderr did not match /$re/: $err)"; fails=$((fails + 1))
  elif [ "$re" = "^$" ] && [ -n "$err" ]; then
    echo "not ok - $name (unexpected stderr: $err)"; fails=$((fails + 1))
  else
    echo "ok - $name"
  fi
  cd / && rm -rf "$tmp"
}

setup; echo more >> docs/notes.md; commit; prev="$base"; check "docs-only change skips" 0 '^$'
setup; echo 'export default 1;' > src/app/page.tsx; commit; prev="$base"; check "code change builds" 1
setup; echo more >> README.md; echo 'export default 1;' > src/app/page.tsx; commit; prev="$base"; check "mixed change builds" 1
setup; echo x >> docs/notes.md; commit; prev=""; check "missing previous SHA builds" 1
setup; echo x >> docs/notes.md; commit; prev=0123456789abcdef0123456789abcdef01234567
check "unknown previous SHA builds and shows git's error" 1 'fatal: .*0123456789abcdef'
setup; echo x >> docs/notes.md; commit; prev="$base"; tree="$(git rev-parse "$base^{tree}")"
rm -f ".git/objects/${tree:0:2}/${tree:2}"; check "failing git diff builds and shows git's error" 1 'fatal|error'
setup; commit; prev="$base"; check "empty diff builds" 1
setup; git mv src/app/page.tsx docs/page.tsx; commit; prev="$base"; check "rename code into docs/ builds" 1
setup; git mv docs/example.ts src/lib/example.ts; commit; prev="$base"; check "rename docs into src/ builds" 1
setup; git mv docs/notes.md docs/renamed-notes.md; commit; prev="$base"; check "rename within docs skips" 0

[ "$fails" -eq 0 ] && echo "# pass" || echo "# fail $fails"
exit $(( fails > 0 ))
