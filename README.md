# RingQ-Devs/services

Signed apt mirror for FreeSWITCH 1.10.12 (Debian bookworm) + vendored FusionPBX installer.
Published via GitHub Pages at <https://ringq-devs.github.io/services/>.

Background and design rationale lives in the consumer repo: [`ringq_cloudapp/docs/PLAN-freeswitch-mirror.md`](https://github.com/RingQ-Devs/ringq_cloudapp/blob/main/docs/PLAN-freeswitch-mirror.md).

---

## Repo layout

```
main branch (source of truth, not directly served)
├── .github/workflows/publish-apt.yml   ← CI: rebuilds gh-pages on push
├── conf/distributions                  ← reprepro config (codename, signing key)
├── keys/                               ← public GPG keys (clients fetch these)
│   ├── ringq-services-archive-keyring.asc   (ASCII)
│   └── ringq-services-archive-keyring.gpg   (binary, used by signed-by=)
├── pool/main/f/freeswitch/             ← FreeSWITCH .deb packages
├── extras/                             ← source tarball, FusionPBX installer tarball (built by CI)
├── fusionpbx-install/debian/           ← vendored FusionPBX installer (patched to use our mirror)
└── README.md                           ← this file

gh-pages branch (what GitHub Pages serves — built by CI)
├── dists/bookworm/                     ← signed apt metadata
│   ├── InRelease, Release, Release.gpg
│   └── main/binary-amd64/Packages, Packages.gz
├── pool/main/...                       ← .debs at reprepro-managed paths
├── keys/                               ← same public keys as main
└── extras/                             ← freeswitch source tarball + fusionpbx-install.tar.gz
```

Anything inside the `exclude_assets` list in `.github/workflows/publish-apt.yml` (currently `.github`, `conf`, `db`, `tools`, `fusionpbx-install`) is in `main` but NOT published to `gh-pages`. The `fusionpbx-install/` source tree is excluded because the workflow tars it into `extras/fusionpbx-install-debian.tar.gz` for clients to consume.

---

## How clients consume this mirror

On every new RingQ VM (set up by `ringq_installer_*.sh`):

```sh
sudo curl -fsSL https://ringq-devs.github.io/services/keys/ringq-services-archive-keyring.gpg \
    -o /usr/share/keyrings/ringq-services-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/ringq-services-archive-keyring.gpg] https://ringq-devs.github.io/services/ bookworm main" \
    | sudo tee /etc/apt/sources.list.d/ringq-services.list

# Pin to 1.10.x so apt can't pick 1.11.0 even if SignalWire's repo is also added.
sudo tee /etc/apt/preferences.d/freeswitch-pin.pref >/dev/null <<'EOF'
Package: freeswitch* libfreeswitch*
Pin: version 1.10*
Pin-Priority: 1001
EOF

sudo apt-get update
sudo apt-get install -y freeswitch  # resolves to 1.10.12 from our mirror
```

---

## Maintainer operations

### Add or update a .deb in the mirror

```sh
# 1. Drop the .deb into the right pool path
cp some-package_1.0_amd64.deb pool/main/f/freeswitch/   # adjust dir by source-package letter

# 2. Commit + push
git add pool/
git commit -m "Add some-package 1.0"
git push
```

CI auto-runs: `reprepro` rebuilds `dists/bookworm/` from scratch off the current `pool/`, signs `Release` / `InRelease` with the signing subkey from secret `APT_SIGNING_KEY`, and force-pushes `gh-pages`. Takes ~3 min.

The workflow is idempotent — re-runs always rebuild from whatever's in `pool/`, so deleting a .deb from `main` and pushing removes it from the mirror on the next run.

### Update the vendored FusionPBX installer

The vendored copy at `fusionpbx-install/debian/` is a snapshot of `/usr/src/telephony-setup.sh/debian/` from a working RingQ server, with RingQ-specific patches applied to `resources/switch/package-release.sh` and `resources/switch/repo.sh` (uses our mirror instead of `signalwire.com`, populates `/etc/freeswitch/` from vanilla templates, no sound packages).

```sh
# Snapshot the current upstream from a working server
ssh root@<healthy-ringq-server> 'tar -czf /tmp/fpbx.tar.gz -C /usr/src telephony-setup.sh'
scp root@<healthy-ringq-server>:/tmp/fpbx.tar.gz /tmp/

# Replace the local tree
rm -rf fusionpbx-install
mkdir fusionpbx-install
tar -xzf /tmp/fpbx.tar.gz -C fusionpbx-install --strip-components=1

# Strip non-Debian OS dirs (we only ship Debian)
rm -rf fusionpbx-install/centos fusionpbx-install/devuan fusionpbx-install/freebsd \
       fusionpbx-install/ubuntu fusionpbx-install/windows

# Re-apply the RingQ patches to resources/switch/package-release.sh and repo.sh
# (see git history for the exact diffs — search for "RingQ patch")

git add fusionpbx-install/
git commit -m "Refresh vendored FusionPBX installer from upstream"
git push
```

CI re-tars `fusionpbx-install/debian/` into `extras/fusionpbx-install-debian.tar.gz` on push.

### Verify the mirror is live after a push

```sh
# Metadata signed and reachable?
curl -fsSL https://ringq-devs.github.io/services/dists/bookworm/InRelease > /tmp/InRelease
curl -fsSL https://ringq-devs.github.io/services/keys/ringq-services-archive-keyring.gpg > /tmp/keyring.gpg
gpg --no-default-keyring --keyring /tmp/keyring.gpg --verify /tmp/InRelease

# Specific .deb fetchable?
curl -fsI https://ringq-devs.github.io/services/pool/main/f/freeswitch/freeswitch_1.10.12-release-10222002881-a88d069d6f~bookworm_amd64.deb

# FusionPBX tarball has the expected top-level layout (debian/ not fusionpbx-install/debian/)?
curl -fsSL https://ringq-devs.github.io/services/extras/fusionpbx-install-debian.tar.gz | tar -tzf - | head -3
```

### Rotate the GPG signing subkey (yearly)

On the offline machine that holds the master key:

```sh
export GNUPGHOME=/path/to/offline/.gnupg
gpg --edit-key <master-fingerprint>
  > addkey                # RSA 4096, sign-only, 1 year expiry
  > save

# Export the new subkey for CI
gpg --armor --export-secret-subkeys <new-subkey-id!> > new-signing-subkey.asc
```

In GitHub: Settings → Secrets and variables → Actions → update `APT_SIGNING_KEY` with the contents of `new-signing-subkey.asc`, and update `RINGQ_SIGNING_KEY_ID` with the new subkey fingerprint.

Re-export the public keyring (master + new subkey) and commit:

```sh
gpg --export <master-fingerprint> > keys/ringq-services-archive-keyring.gpg
gpg --armor --export <master-fingerprint> > keys/ringq-services-archive-keyring.asc
git add keys/ && git commit -m "Rotate signing subkey" && git push
```

Servers don't need any action — they already trust the master, which signs the new subkey.

### Emergency: revoke a compromised master

1. Generate revocation cert offline (you saved one at bootstrap)
2. Import + push: `gpg --import master-revocation.asc && gpg --armor --export <fp> > keys/...`
3. Generate a brand new master + subkey, repeat bootstrap
4. Update apt sources on the fleet to use new keyring path (one-shot Redis flag via `jobs.sh`)

---

## CI workflow (`.github/workflows/publish-apt.yml`)

Triggers on push to `main` when these paths change:

- `pool/**`, `conf/**`, `keys/**`, `extras/**`, `fusionpbx-install/**`, `.github/workflows/publish-apt.yml`

What it does in order:

1. Import signing subkey from `APT_SIGNING_KEY` secret, mark trusted, prime gpg-agent
2. Migrate any legacy `pool/main/_incoming/*.deb` to `pool/main/f/freeswitch/` (idempotent)
3. Wipe `dists/` and `db/`, run `reprepro includedeb` for every .deb in `pool/main/f/freeswitch/`
4. Verify `dists/bookworm/InRelease` is signed and verifies against the public keyring
5. Smoke-test `apt-get update` inside a `debian:bookworm-slim` container against the local repo state
6. Tar `fusionpbx-install/debian/` into `extras/fusionpbx-install-debian.tar.gz` (with `debian/` at top level)
7. Force-push the working tree (minus `exclude_assets`) to the `gh-pages` branch via `peaceiris/actions-gh-pages@v3`
8. Smoke-test the live URL (non-fatal — only a warning on first run before Pages is enabled)

GitHub Pages serves the `gh-pages` branch root.

### Required secrets

| Secret | Purpose |
|---|---|
| `APT_SIGNING_KEY` | ASCII-armored export of the private signing subkey (master stays offline) |
| `APT_SIGNING_KEY_PASSPHRASE` | Passphrase for the signing subkey |
| `RINGQ_SIGNING_KEY_ID` | Full fingerprint of the signing subkey (used by `reprepro` `SignWith` in `conf/distributions`) |

---

## Troubleshooting

### "Workflow ran but the live tarball doesn't have my change"

The path-filter likely didn't match. Check `.github/workflows/publish-apt.yml`'s `on.push.paths`. The workflow file itself triggers re-runs — pushing a one-line tweak to it forces a rebuild against the current state of `main`.

### "Workflow failed on `gpg --verify`"

Either the signing key wasn't imported (check `APT_SIGNING_KEY` secret is intact and base64-clean), or `conf/distributions`'s `SignWith:` fingerprint doesn't match the imported key.

### "apt clients see version `1.11.0`, not `1.10.12`"

The pin file isn't in place on the client. See "How clients consume this mirror" above — `apt-mark hold` alone isn't enough; the version pin must exist at `/etc/apt/preferences.d/freeswitch-pin.pref`.

### "GitHub size warning on push"

The 50MB `freeswitch-sounds-en-us-callie_*.deb` triggers the cosmetic GitHub warning. Push succeeds — file is under the hard 100MB limit. If you ever want to silence it, recompress with `xz` (~30MB).

### "Need to fix a broken FreeSWITCH on a server"

Manual recovery runbook is in [`ringq_cloudapp/ringq/app/scripts/jobs.sh`](https://github.com/RingQ-Devs/ringq_cloudapp/blob/main/ringq/app/scripts/jobs.sh)'s drift-heal logic, or trigger it remotely by setting `restart_jobs=1` in Redis on the broken server.

---

## Related repos

- [`ringq_cloudapp`](https://github.com/RingQ-Devs/ringq_cloudapp) — the RingQ application code, including the installer scripts (`globaldownload/ringq_installer_*.sh`) and the per-server runtime helper (`ringq/app/scripts/jobs.sh`) that talk to this mirror
- `vupdate.ringq.io` — RingQ's file server, still rsynced for `baseapp/1-10` artifacts (this mirror replaced `baseapp/11`)
