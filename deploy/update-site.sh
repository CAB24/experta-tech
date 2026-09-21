#!/usr/bin/env bash
# Installed by the administrator; never execute deployment code pulled from main.
set -Eeuo pipefail
umask 022
export GIT_TERMINAL_PROMPT=0

base=/srv/experta-tech
repository=https://github.com/CAB24/experta-tech.git
gitdir="$base/repository.git"
releases="$base/releases"

[[ -d "$base" && ! -L "$base" && -d "$releases" && ! -L "$releases" ]]
exec 9>"$base/deploy.lock"
flock -n 9 || exit 0

if [[ ! -d "$gitdir" ]]; then
  git init --bare "$gitdir"
  git --git-dir="$gitdir" remote add origin "$repository"
fi
[[ "$(git --git-dir="$gitdir" remote get-url origin)" == "$repository" ]]
git --git-dir="$gitdir" fetch --quiet --depth=1 origin refs/heads/main
revision=$(git --git-dir="$gitdir" rev-parse --verify 'FETCH_HEAD^{commit}')
[[ "$revision" =~ ^[0-9a-f]{40}$ ]]
destination="$releases/$revision"

if [[ "$(readlink "$base/current" || true)" == "$destination" ]]; then
  echo "Already deployed $revision"
  exit 0
fi

staging=$(mktemp -d "$releases/.incoming.XXXXXXXX")
# Leave an unsuccessful staging directory for inspection; never disturb current.
git --git-dir="$gitdir" archive "$revision" -- \
  index.html stack.html certificates.html partners.html robots.txt sitemap.xml assets \
  | tar -xf - -C "$staging"
if [[ -n "$(find "$staging" -type l -print -quit)" ]]; then
  echo 'Refusing to publish symbolic links' >&2
  exit 1
fi
for path in index.html stack.html certificates.html partners.html assets/styles.css assets/app.js assets/images/ilya-noskov.jpg; do
  [[ -s "$staging/$path" ]] || { echo "Missing file: $path" >&2; exit 1; }
done
chmod 755 "$staging"
find "$staging" -type d -exec chmod 755 {} +
find "$staging" -type f -exec chmod 644 {} +
if [[ ! -e "$destination" ]]; then
  mv "$staging" "$destination"
else
  echo "Reusing saved release $revision; inspection copy kept at $staging"
fi
if [[ -L "$base/current" ]]; then
  ln -sfn "$(readlink "$base/current")" "$base/previous.next"
  mv -Tf "$base/previous.next" "$base/previous"
elif [[ -e "$base/current" ]]; then
  echo 'Refusing to replace a non-symlink current directory' >&2
  exit 1
fi
ln -sfn "$destination" "$base/current.next"
mv -Tf "$base/current.next" "$base/current"
printf '%s\n' "$revision" > "$base/deployed-commit"
echo "Deployed $revision from GitHub main"
