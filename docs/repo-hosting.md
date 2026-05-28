# Sileo Repo Hosting Guide

## Full workflow (runs on macOS)

```sh
# 1. Build the .deb
make package

# 2. Copy to repo pool
cp packages/com.iosautotool_*.deb repo/pool/main/

# 3. Regenerate index files
chmod +x scripts/update-repo.sh
./scripts/update-repo.sh

# 4. Commit and push
git add repo/
git commit -m "chore: update repo"
git push
```

`repo/pool/main/*.deb` files are gitignored — you add them manually before step 3 each release.

---

## GitHub Pages setup (two options)

### Option A — dedicated `gh-pages` branch

```sh
git subtree push --prefix repo origin gh-pages
```

Pages URL: `https://<username>.github.io/<reponame>/`

Then in GitHub → Settings → Pages → Source: **gh-pages** branch, root `/`.

### Option B — `docs/` folder on main branch

```sh
cp -r repo/* docs/repo/
git add docs/repo/
git commit -m "chore: update repo"
git push
```

Pages URL: `https://<username>.github.io/<reponame>/repo/`

Then in GitHub → Settings → Pages → Source: **main** branch, `/docs` folder.

**Option A is recommended** — cleaner separation, repo/ never mixed with source code.

---

## Adding to Sileo on device

1. Open Sileo → **Sources** tab → tap **+**
2. Enter: `https://<username>.github.io/<reponame>/`
3. Tap **Add Source**
4. Search for **iOS Auto Tool** → tap **Get** → **Confirm**
5. Device resprings, daemon starts automatically

---

## Dependencies on macOS

```sh
brew install dpkg   # provides dpkg-deb (required by update-repo.sh)
```

`gzip`, `bzip2`, `shasum` ship with macOS — no extra install needed.

---

## Bumping the version

1. Edit `control`: increment `Version:`
2. `make package`
3. Copy new `.deb` to `repo/pool/main/` (old .deb can stay for downgrade support)
4. `./scripts/update-repo.sh`
5. `git push`

Sileo checks for updates automatically when the user refreshes sources.

---

## GPG signing (optional, future)

Unsigned repos show a warning in Sileo but install fine. To sign later:

```sh
gpg --clearsign -o repo/InRelease repo/Release
```

Users must trust your GPG key once. Document key fingerprint in README.
