# Secure GitHub Repository Setup

## Pre-Push Security Checklist

⚠️ **BEFORE PUSHING TO GITHUB, VERIFY:**

```powershell
# Run in the VDS folder
cd "D:\school\CyberSecurity\Opdrachten\VTCS\Project 2\VDS"

# Check what would be committed (should NOT include .key or .conf files)
git status

# Verify .gitignore is working - these should show as ignored:
git check-ignore -v user-packages/admin1/host_admin1.key
git check-ignore -v user-packages/admin1/admin.conf
```

**Expected output**: Files should show as ignored by `.gitignore`

---

## Step 1: Initialize Git Repository (Local)

```powershell
cd "D:\school\CyberSecurity\Opdrachten\VTCS\Project 2\VDS"

# Initialize (if not already)
git init

# Verify .gitignore is working
git status
```

**What should be tracked:**
- ✅ `*.md` files (README, documentation)
- ✅ `*.sh` scripts
- ✅ `docker-compose.yml`
- ✅ `Dockerfile` files

**What should be IGNORED:**
- ❌ `*.key` (SSH private keys)
- ❌ `*.conf` (WireGuard configs with private keys)
- ❌ `.env` files

---

## Step 2: Create Private GitHub Repository

### Option A: GitHub CLI (Recommended)
```powershell
# Install GitHub CLI if needed: winget install GitHub.cli
gh auth login
gh repo create vtcs-cyber-range --private --source=. --remote=origin
```

### Option B: GitHub Web UI
1. Go to https://github.com/new
2. Repository name: `vtcs-cyber-range` (or your choice)
3. **Select: Private** ⚠️ CRITICAL
4. Do NOT initialize with README (you already have one)
5. Create repository
6. Copy the SSH URL: `git@github.com:YOUR-USERNAME/vtcs-cyber-range.git`

---

## Step 3: Configure Git (First Time Only)

```powershell
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

---

## Step 4: Add Remote and Push

```powershell
# Add GitHub as remote
git remote add origin git@github.com:YOUR-USERNAME/vtcs-cyber-range.git

# Stage all files (gitignore will exclude secrets)
git add .

# VERIFY before committing - NO .key or .conf files should appear:
git status

# Commit
git commit -m "Initial commit: VTCS Cyber Range POC"

# Push to GitHub
git branch -M main
git push -u origin main
```

---

## Step 5: Verify Security on GitHub

After pushing, check on GitHub:
1. Go to your repository
2. Navigate to `user-packages/admin1/`
3. **Verify**: Only `README.md` should be visible (NO `.key` or `.conf` files)

---

## SSH Key Setup for GitHub (If Needed)

If you don't have SSH keys for GitHub:

```powershell
# Generate key
ssh-keygen -t ed25519 -C "your.email@example.com"

# Start SSH agent
Get-Service ssh-agent | Set-Service -StartupType Manual
Start-Service ssh-agent

# Add key to agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519

# Copy public key
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | Set-Clipboard
```

Then add to GitHub:
1. GitHub → Settings → SSH and GPG keys → New SSH key
2. Paste your public key
3. Test: `ssh -T git@github.com`

---

## Alternative: HTTPS with Token

If SSH doesn't work, use HTTPS:

```powershell
git remote add origin https://github.com/YOUR-USERNAME/vtcs-cyber-range.git
```

When prompted, use:
- Username: your GitHub username
- Password: a Personal Access Token (not your password!)

Create token at: https://github.com/settings/tokens

---

## Secrets Management

### What's in the repo (safe):
- Documentation with example credentials (for reference only)
- Scripts that generate keys (not the keys themselves)
- Docker/infrastructure configuration

### What's NOT in the repo (handled separately):
| Secret | Where to Store |
|--------|----------------|
| SSH keys (`.key`) | Distribute to users directly (USB, encrypted email, etc.) |
| VPN configs (`.conf`) | Distribute to users directly |
| Root password | Only in your secure password manager |

### Distributing User Packages

Since keys/configs are gitignored, distribute them separately:

1. **Secure channel**: Encrypted email, USB drive, or in-person
2. **Per-user folders**: Give each admin/student only their own folder
3. **Never**: Send via unencrypted chat, public share links, etc.

---

## Emergency: Accidentally Committed Secrets?

If you accidentally committed secrets:

```powershell
# Remove from git history (keeps local file)
git rm --cached user-packages/admin1/host_admin1.key
git commit -m "Remove accidentally committed key"

# For thorough cleanup (rewrites history):
# Install git-filter-repo: pip install git-filter-repo
git filter-repo --path user-packages/admin1/host_admin1.key --invert-paths

# Force push (if already pushed)
git push --force
```

⚠️ **After exposing keys**: Regenerate ALL exposed keys immediately!

---

## Repository Structure After Push

```
vtcs-cyber-range/
├── .gitignore           ✅ Tracked
├── README.md            ✅ Tracked
├── MASTER-DOCUMENTATION.md  ✅ Tracked (no passwords)
├── GITHUB-SETUP.md      ✅ Tracked
├── docs/
│   ├── architecture.md  ✅ Tracked
│   ├── security.md      ✅ Tracked
│   └── runbook.md       ✅ Tracked
├── infra/               ✅ Tracked (scripts only)
├── scenarios/           ✅ Tracked
├── scripts/             ✅ Tracked
└── user-packages/       ❌ EXCLUDED (distribute separately)
```

## Distributing User Packages

Since `user-packages/` is excluded from git, distribute them separately:

| Method | Security | Recommended For |
|--------|----------|-----------------|
| USB drive | High | In-person handoff |
| Encrypted zip via email | Medium | Remote distribution |
| Secure file sharing (OneDrive with link expiry) | Medium | Convenience |
| Unencrypted email/chat | ❌ Never | - |

Each user gets ONLY their own folder (admin1 gets admin1/, red1 gets red1/, etc.)
