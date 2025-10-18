## SSH with Public Key on Windows (OpenSSH)

Set up a secure SSH using OpenSSH on Windows that can be used to SSH into multiple different devices with one password. Run commands in PowerShell as your normal user (not Administrator) so keys are saved under your profile.

---

### 1) Check for OpenSSH Client

Open PowerShell and check if OpenSSH is available.

```powershell
# Show SSH version/help (installed if this prints usage or a version)
ssh -V
```

If it’s not installed:

- Install via PowerShell/Command Prompt:

```powershell
# Check capability status
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'

# Install if State = NotPresent (may require restart of PowerShell)
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

Note: Keep using a non-elevated PowerShell/ Command Prompt window for key generation to ensure keys save under your user profile.

---

### 2) Generate your SSH key pair

Github recommended: use an Ed25519 key. Windows defaults to 2048-bit RSA Key. If your remote device is older and doesn’t support Ed25519, use RSA 4096.

Choose a short name for your key files (replaces `<mykey>` below) by defualt it sets name to `id_rsa`. Keys will be saved to `C:\Users\<You>\.ssh\<mykey>` by default.

```powershell
# Default command will save file as id_rsa
ssh-keygen

# Ed25519 with your own key name (Recommended)
ssh-keygen -t ed25519 -f <mykey>
```

When prompted:

- Press Enter to accept the filename shown (it matches `-f`).
- Enter a passphrase for added security. 

NOTE: while the passphrase can be left blank it is highly recommended incase someone is able to steal/copy the private key file as it will encrypt the private key file. You’ll be asked for a password when you want to SSH with the key. If not the it is recommended you keep it on an USB or external drive so it is only accessible when plugged in.

---

### 3) Locate your keys

By default keys are stored in your `.ssh` folder:

- Private key: `C:\Users\<You>\.ssh\<mykey>`
- Public key:  `C:\Users\<You>\.ssh\<mykey>.pub`

Important safety notes:

- DO NOT share your private key (`<mykey>`), it is called a private key for a reason!! Keep it secret and backed up securely. 
- If you must transfer your private key between machines, do it offline using trusted external storage.

Note: For explanations and more info as to why this is important security procedures, look into the diffie-hellman key exchange.

To view your public key so you can copy/paste it from:

- Opening the file with notepad/text editor and copy and paste all of it (recommended as easiest).
- Or use powershell:

```powershell
Get-Content "path\to\public\key\<mykey>.pub"
```

---

### 4) Provide your public key to the remote device

You need to place the contents of `<mykey>.pub` into the remote user’s `~/.ssh/authorized_keys` file. For the all Raspberry pi's on the system this was done using option C which is the easiest.

Option A — copy/paste on the remote device (Linux/macOS/Raspberry Pi):

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "<paste the single-line contents of <mykey>.pub here>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Option B — transfer the public key using scp from Windows:

```powershell
# Replace <user> and <device> with your remote username and IP/hostname
scp "path\to\public\key\<mykey>.pub" <user>@<device>:/tmp/<mykey>.pub
```

Then on the remote device:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat /tmp/<mykey>.pub >> ~/.ssh/authorized_keys
rm /tmp/<mykey>.pub
chmod 600 ~/.ssh/authorized_keys
```

Option C - Raspberry Pi Imager
#### Step 1)

Open Raspberry Pi Imager

#### Step 2)

Press Ctrl+Shift+x then go to `Services` and tick `Enable SSH` then `Allow public-key authentication only`

#### Step 3)

Paste the single-line contents of `<mykey>.pub` into the text box. if no text box exist press `ADD SSH KEY` one should appear

#### Step 4)

Setup your Raspberry Pi and flash the desired OS to the drive/SD card

Tip: Many home devices support mDNS hostnames like `raspberrypi.local` or `hostname.local`.

---

### 5) Connect using your key

From Windows, connect with your private key file. If you set a passphrase, you’ll be prompted for it.

```powershell
ssh <user_on_device_your_connecting_to>@<device_IP_or_hostname.local> -i "path\to\the\private\key"
```

If the key is correctly installed on the remote device, you should be logged in without entering the account password. If you have encrypted the private key file then you will need the password that you used to encrypt the private key. 

To connect to different devices that have the same public key just change the `<user>` and `<device_IP_or_hostname.local>`

---

### 7) Troubleshooting

- Permission denied (publickey): Ensure your public key is in `~/.ssh/authorized_keys` on the remote and file permissions are strict (`~/.ssh` 700, `authorized_keys` 600).
- Server doesn’t support Ed25519: Generate an RSA 4096 key instead (see step 2).
- Host key changed warning: Edit or remove the matching line in `C:\Users\<You>\.ssh\known_hosts`.
- Verbose output to diagnose connection:

```powershell
ssh -v <user>@<device_IP_or_hostname.local> -i "path\to\the\private\key"
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
- Generate key (Ed25519): `ssh-keygen -t ed25519  -f "<mykey>"`
- Show public key: `Get-Content "path\to\public\key\<mykey>.pub"`
- Copy pubkey via scp: `scp "path\to\public\key\<mykey>.pub" <user>@<device>:/tmp/<mykey>.pub`
- Connect: `ssh <user_of_device_connecting_to>@<device_IP_or_hostname.local> -i "path\to\the\private\key" `

