# FreeSWITCH 1.10.12 apt Mirror — Setup Runbook

These artifacts populate the **`RingQ-Devs/services`** GitHub repo, which serves a signed apt mirror of FreeSWITCH 1.10.12 via GitHub Pages.

Background and design rationale: [`docs/PLAN-freeswitch-mirror.md`](../../docs/PLAN-freeswitch-mirror.md).

---

## What's in this folder

| Path | Purpose |
|---|---|
| `conf/distributions` | reprepro config — declares the `bookworm` suite |
| `scripts/bootstrap-gpg.sh` | One-time GPG master + signing-subkey generator. **Run on your local machine, not a server.** |
| `scripts/download-fs-debs.sh` | Bulk-downloads every working 1.10.12 `.deb` from SignalWire. Run on a RingQ server with `auth.conf` configured. |
| `scripts/build-and-publish.sh` | Local dry-run of what the GitHub Actions workflow does — useful for testing before pushing |
| `workflows/publish-apt.yml` | GitHub Actions workflow — lives at `.github/workflows/publish-apt.yml` in the services repo |

---

## End-to-end setup

### Step 1 — Create the GitHub repo (your action, ~30 sec)

1. Go to https://github.com/organizations/RingQ-Devs/repositories/new
2. Repository name: **`services`**
3. Visibility: Private (recommended) or Public (also fine — apt-source data is non-sensitive)
4. Initialize: leave empty (no README, no gitignore)
5. Click **Create repository**

Don't clone yet. Come back when done.

### Step 2 — Generate GPG keys (your action, ~2 min)

On your **local machine** (not a server — the private master key must stay offline):

```bash
cd /Users/jaybayron/Herd/Github/ringq_cloudapp/tools/freeswitch-mirror
bash scripts/bootstrap-gpg.sh
```

The script will:
1. Generate an Ed25519 master key (5-year expiry).
2. Generate an RSA 4096 signing subkey (1-year expiry).
3. Print:
   - The **public keyring** (binary) → save to `keys/ringq-services-archive-keyring.gpg` in the services repo.
   - The **signing subkey private export** → paste into GitHub Secret `APT_SIGNING_KEY`.
   - The **passphrase** → paste into GitHub Secret `APT_SIGNING_KEY_PASSPHRASE`.
4. Print the master-key revocation cert → save **offline** (1Password / vault), NOT in any repo.

### Step 3 — Set GitHub Actions secrets (your action, ~1 min)

In the `RingQ-Devs/services` repo:
1. **Settings → Secrets and variables → Actions → New repository secret**
2. Add two secrets using the values from Step 2:
   - `APT_SIGNING_KEY` — the ASCII-armored exported subkey
   - `APT_SIGNING_KEY_PASSPHRASE` — the passphrase

### Step 4 — Bulk-download the .deb files (your action, ~5 min)

SSH into any healthy RingQ production server (it already has SignalWire's `auth.conf`). Then:

```bash
# scp the download script up to the server
scp scripts/download-fs-debs.sh root@<server-ip>:/tmp/

# then on the server:
ssh root@<server-ip>
bash /tmp/download-fs-debs.sh /tmp/fs-mirror-pool
```

When done, pull the directory back to your laptop:
```bash
scp -r root@<server-ip>:/tmp/fs-mirror-pool ./
```

You should now have a `fs-mirror-pool/` folder with ~45 `.deb` files.

### Step 5 — Populate and push the services repo (your action, ~2 min)

```bash
git clone git@github.com:RingQ-Devs/services.git ~/RingQ-services
cd ~/RingQ-services

# Copy the artifacts from this folder
cp -r /Users/jaybayron/Herd/Github/ringq_cloudapp/tools/freeswitch-mirror/conf .
mkdir -p .github/workflows
cp /Users/jaybayron/Herd/Github/ringq_cloudapp/tools/freeswitch-mirror/workflows/publish-apt.yml .github/workflows/
cp /Users/jaybayron/Herd/Github/ringq_cloudapp/tools/freeswitch-mirror/README.md ./README.md

# Stage the public key (from Step 2) and the .deb files
mkdir -p keys pool/main
cp /path/to/ringq-services-archive-keyring.gpg keys/

# Move .debs into the pool — reprepro will sort them on first run
mkdir -p pool/main/_incoming
cp ~/fs-mirror-pool/*.deb pool/main/_incoming/

# Commit and push
git add .
git commit -m "Initial FreeSWITCH 1.10.12 mirror"
git push -u origin main
```

### Step 6 — Watch the workflow build the mirror (~3 min)

The push triggers `.github/workflows/publish-apt.yml`. It will:
1. Import the signing subkey from secrets
2. Run `reprepro includedeb bookworm pool/main/_incoming/*.deb`
3. Build `dists/bookworm/InRelease` and friends
4. Force-push the published tree to `gh-pages` branch

Watch progress at `https://github.com/RingQ-Devs/services/actions`.

### Step 7 — Enable GitHub Pages (your action, ~30 sec)

Once the workflow has pushed `gh-pages`:

1. **Settings → Pages**
2. Source: **Deploy from a branch**
3. Branch: **`gh-pages`** / Folder: **`/ (root)`**
4. Save.

Within ~1 minute, the mirror is live at:
`https://ringq-devs.github.io/services/`

### Step 8 — Smoke test (my action, you observe)

Tell me the mirror is live and I'll run the verification steps from `docs/PLAN-freeswitch-mirror.md` Phase 5 against a fresh Debian container.

### Step 9 — Wire the mirror into RingQ scripts (my action)

Once Step 8 passes, I edit:
- `globaldownload/ringq_installer_staging.sh` + `ringq_installer.sh` → point at the mirror
- `ringq/app/scripts/jobs.sh` → tighten apt pin

---

## After it's live

- **Adding a new module .deb**: drop into `pool/main/_incoming/`, commit + push. CI republishes.
- **Yearly subkey rotation**: re-run `bootstrap-gpg.sh` with `--rotate-subkey`, update the secret, push.
- **Emergency key rotation**: see `docs/PLAN-freeswitch-mirror.md` Phase 4.3.

---

## Rollback

If the mirror breaks for any reason, existing servers are unaffected (they're held + pinned). For new installs, revert the installer's apt source block back to SignalWire — see `docs/PLAN-freeswitch-mirror.md` Phase 6.
