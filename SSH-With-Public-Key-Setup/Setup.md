## SSH with Public Key on Windows (OpenSSH)

Set up secure, passwordless SSH using OpenSSH on Windows. Run commands in PowerShell as your normal user (not Administrator) so keys are saved under your profile.

---

### 1) Check for OpenSSH Client

Open PowerShell and check if OpenSSH is available.

```powershell
# Show SSH version/help (installed if this prints usage or a version)
ssh -V
```

If it’s not installed:

- Windows 10/11: Settings > Apps > Optional features > Add a feature > “OpenSSH Client”.
- Or install via PowerShell (optional):

```powershell
# Check capability status
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'

# Install if State = NotPresent (may require restart of PowerShell)
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

Note: Keep using a non-elevated PowerShell window for key generation to ensure keys save under your user profile.

---

### 2) Generate your SSH key pair

Recommended: use an Ed25519 key (modern and compact). If your remote device is older and doesn’t support Ed25519, use RSA 4096.

Choose a short name for your key files (replaces `<mykey>` below). Keys will be saved to `C:\Users\<You>\.ssh\id_<mykey>`.

```powershell
# Ed25519 (recommended)
ssh-keygen -t ed25519 -a 100 -C "<label_or_email>" -f "$env:USERPROFILE\.ssh\id_<mykey>"

# RSA 4096 (fallback if Ed25519 unsupported)
ssh-keygen -t rsa -b 4096 -o -a 100 -C "<label_or_email>" -f "$env:USERPROFILE\.ssh\id_<mykey>"
```

When prompted:

- Press Enter to accept the filename shown (it matches `-f`).
- Enter a passphrase for added security (recommended). You’ll be asked for it when using the key.

---

### 3) Locate your keys

Your keys are stored in your `.ssh` folder:

- Private key: `C:\Users\<You>\.ssh\id_<mykey>`
- Public key:  `C:\Users\<You>\.ssh\id_<mykey>.pub`

Important safety notes:

- DO NOT share your private key (`id_<mykey>`). Keep it secret and backed up securely.
- If you must transfer your private key between machines, do it offline using trusted external storage.

To view your public key so you can copy/paste it:

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_<mykey>.pub"
```

---

### 4) Provide your public key to the remote device

You need to place the contents of `id_<mykey>.pub` into the remote user’s `~/.ssh/authorized_keys` file.

Option A — copy/paste on the remote device (Linux/macOS/Raspberry Pi):

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "<paste the single-line contents of id_<mykey>.pub here>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Option B — transfer the public key using scp from Windows:

```powershell
# Replace <user> and <device> with your remote username and IP/hostname
scp "$env:USERPROFILE\.ssh\id_<mykey>.pub" <user>@<device>:/tmp/<mykey>.pub
```

Then on the remote device:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat /tmp/<mykey>.pub >> ~/.ssh/authorized_keys
rm /tmp/<mykey>.pub
chmod 600 ~/.ssh/authorized_keys
```

Tip: Many home devices support mDNS hostnames like `raspberrypi.local` or `hostname.local`.

---

### 5) Connect using your key

From Windows, connect with your private key file. If you set a passphrase, you’ll be prompted for it.

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_<mykey>" <user>@<device_IP_or_hostname.local>
```

If the key is correctly installed on the remote device, you should be logged in without entering the account password.

---

### 6) Optional: use the Windows ssh-agent (to skip -i each time)

You can run the ssh-agent service and add your key once per session so you don’t need to pass `-i` each time.

```powershell
# Start the agent and set it to run automatically
Start-Service ssh-agent
Set-Service -Name ssh-agent -StartupType Automatic

# Add your key (enter your passphrase if prompted)
ssh-add "$env:USERPROFILE\.ssh\id_<mykey>"

# Now you can simply run:
ssh <user>@<device_IP_or_hostname.local>
```

---

### 7) Troubleshooting

- Permission denied (publickey): Ensure your public key is in `~/.ssh/authorized_keys` on the remote and file permissions are strict (`~/.ssh` 700, `authorized_keys` 600).
- Server doesn’t support Ed25519: Generate an RSA 4096 key instead (see step 2).
- Host key changed warning: Edit or remove the matching line in `C:\Users\<You>\.ssh\known_hosts`.
- Verbose output to diagnose connection:

```powershell
ssh -v -i "$env:USERPROFILE\.ssh\id_<mykey>" <user>@<device_IP_or_hostname.local>
```

---

### 8) Security reminders

- Never share your private key.
- Use a passphrase to protect your key in case it’s stolen.
- Back up your private key securely (ideally offline). Avoid emailing keys.
- Rotate/replace keys periodically and remove unused keys from remote devices.

---

### Quick reference

- Check SSH: `ssh -V`
- Generate key (Ed25519): `ssh-keygen -t ed25519 -a 100 -C "<label>" -f "$env:USERPROFILE\.ssh\id_<mykey>"`
- Show public key: `Get-Content "$env:USERPROFILE\.ssh\id_<mykey>.pub"`
- Copy pubkey via scp: `scp "$env:USERPROFILE\.ssh\id_<mykey>.pub" <user>@<device>:/tmp/<mykey>.pub`
- Connect: `ssh -i "$env:USERPROFILE\.ssh\id_<mykey>" <user>@<device>`

