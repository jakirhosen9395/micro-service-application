# GitHub Setup on Ubuntu (Vagrant / Ubuntu 24.04) — Git + SSH Key Authentication

This guide documents how to install Git, configure your identity, generate an SSH key, add it to GitHub, verify SSH authentication, and manage branch merges.

Account: **https://github.com/jakirhosen9395**  
OS: **Ubuntu 24.04 (Noble)**  
User in VM: **vagrant**

---

## 1) SSH into the VM

From your host machine (where the `Vagrantfile` is located):

```bash
vagrant ssh
```

---

## 2) Install Git and OpenSSH client

Inside the VM:

```bash
sudo apt update
sudo apt install -y git openssh-client
```

Verify installation:

```bash
git --version
ssh -V
```

---

## 3) Configure Git identity (name + email)

Inside the VM:

```bash
git config --global user.name "Md Jakir Hosen"
git config --global user.email "jakirhosen9395@gmail.com"
git config --global init.defaultBranch main
```

Confirm:

```bash
git config --global --list
```

You should see:

- `user.name=Md Jakir Hosen`
- `user.email=jakirhosen9395@gmail.com`
- `init.defaultbranch=main`

---

## 4) Generate an SSH key (ED25519)

Inside the VM:

```bash
ssh-keygen -t ed25519 -C "jakirhosen9395@gmail.com"
```

When prompted:

- **File location:** press **Enter** to accept default: `~/.ssh/id_ed25519`
- **Passphrase:** optional (recommended for extra security)

This creates:

- Private key: `~/.ssh/id_ed25519`
- Public key: `~/.ssh/id_ed25519.pub`

---

## 5) Start ssh-agent and add your key

Inside the VM:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

---

## 6) Copy the public key

Inside the VM:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the full output (starts with `ssh-ed25519 ...`).  
**Do NOT share your private key** (`~/.ssh/id_ed25519`). Only the `.pub` key is safe to copy.

---

## 7) Add the SSH key to GitHub

In your browser (GitHub):

1. Go to **Settings**
2. Go to **SSH and GPG keys**
3. Click **New SSH key**
4. Title: something like `Ubuntu24 Vagrant VM`
5. Paste the public key you copied
6. Click **Add SSH key**

---

## 8) Test SSH authentication

Inside the VM:

```bash
ssh -T git@github.com
```

The first time, you may see a host authenticity prompt like:

```text
The authenticity of host 'github.com (...)' can't be established.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type:

```text
yes
```

Expected successful message:

```text
Hi jakirhosen9395! You've successfully authenticated, but GitHub does not provide shell access.
```

That means SSH authentication is working correctly.

---

## 9) Clone a repository using SSH

Use this format:

```bash
git clone git@github.com:jakirhosen9395/REPO_NAME.git
```

Example (replace `REPO_NAME`):

```bash
git clone git@github.com:jakirhosen9395/REPO_NAME.git
cd REPO_NAME
```

---

## 10) Basic Git workflow (commit + push)

Inside your repo folder:

```bash
git status
git add .
git commit -m "Initial commit"
git push
```

---

## 11) Branch Promotion (Force Merge)

Use this workflow to promote code across branches in order:  
`source-code` → `development` → `staging` → `production`

> ⚠️ **Warning:** These commands use `--force-with-lease` which overwrites the target branch history. Use with caution in shared repositories.

### 1) Force `source-code` → `development`

```bash
git fetch origin

git checkout development
git reset --hard origin/source-code
git push --force-with-lease origin development
```

---

### 2) Force `development` → `staging`

```bash
git fetch origin

git checkout staging
git reset --hard origin/development
git push --force-with-lease origin staging
```

---

### 3) Force `staging` → `production`

```bash
git fetch origin

git checkout production
git reset --hard origin/staging
git push --force-with-lease origin production
```

---

### Optional: Verify before pushing (safe check)

```bash
git log --oneline --decorate -5
git status
```

---

## Troubleshooting

### A) `Permission denied (publickey)`

- Make sure you added the **public key** to GitHub correctly.
- Check your key is loaded:

```bash
ssh-add -l
```

If nothing is listed, add it again:

```bash
ssh-add ~/.ssh/id_ed25519
```

### B) Wrong remote URL (HTTPS instead of SSH)

Check:

```bash
git remote -v
git fetch --prune origin
```

If it shows `https://...`, switch to SSH:

```bash
git remote set-url origin git@github.com:jakirhosen9395/REPO_NAME.git
```

### C) Keep SSH keys persistent across VM rebuilds

If you destroy/recreate the VM often (`vagrant destroy`), keys created inside the VM will be lost unless stored on the host (e.g., in a synced folder like `/data`).

One approach is to store keys on the host-shared folder and link them into `~/.ssh`.

> Only do this if your host folder permissions are secure.

---

## Security notes

- **Never** upload your private key (`id_ed25519`) to GitHub.
- Only upload the **public key** (`id_ed25519.pub`).
- Using a passphrase is recommended if your threat model requires it.

---

**Done ✅** — Git + SSH access is configured and branch promotion workflow is ready for GitHub account `jakirhosen9395`.
