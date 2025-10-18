## Raspberry Pi 5 (8GB) — 4TB NAS Setup

This guide walks through setting up a Raspberry Pi 5 (8GB) as a home NAS using a 4TB HDD and Samba. It assumes Windows for flashing and SSH from your PC.

- OS: Raspberry Pi OS (64-bit)
- Boot media: 32GB microSD
- Storage: 4TB NAS HDD via powered USB-to-SATA adapter

Before you start, set up SSH keys on Windows. See: SSH With Public Key on Windows (OpenSSH) — open in a new tab.

---

### Equipment used

- Raspberry Pi 5 (8GB)
- 4TB NAS HDD
- 27W USB‑C power supply
- Powered USB‑to‑SATA converter/enclosure
- 32GB microSD card

---

## Steps

### 1) Flash Raspberry Pi OS and preload your SSH public key

Use Raspberry Pi Imager:

1. Select Raspberry Pi OS (64-bit).
2. Press Ctrl+Shift+X for Advanced options.
3. In Services: Enable SSH and choose “Allow public-key authentication only”.
4. Paste the contents of your public key into the SSH key box.
	- SSH guide: SSH-With-Public-Key setup
5. Set a hostname (e.g., nas-pi.local) and Wi‑Fi/Ethernet as needed.
6. Write to the microSD.

---

### 2) First boot and SSH in

Insert the microSD into the Pi, connect network and power, then from Windows:

```powershell
ssh -i "C:\\Users\\<You>\\.ssh\\id_<mykey>" <user>@nas-pi.local
# or use the IP address
ssh -i "C:\\Users\\<You>\\.ssh\\id_<mykey>" <user>@<pi_ip>
```

Update base packages:

```bash
sudo apt update && sudo apt -y full-upgrade
```

---

### 3) Install required packages

```bash
sudo apt install -y samba samba-common-bin vim wakeonlan smartmontools rsync ntfs-3g fuse parted
```

Notes:
- `wakeonlan` is for sending WoL packets to other devices from the Pi.
- `smartmontools` helps check HDD health.
- `ntfs-3g` enables read/write NTFS support.
- `parted` handles >2TB partitioning (GPT).

---

### 4) Attach the HDD and identify the device

Plug in your powered USB-to-SATA adapter with the HDD attached.

List disks:

```bash
sudo fdisk -l
```

Find your drive path, e.g., `/dev/sda` (device) and later `/dev/sda1` (partition).

---

### 5) Partition the disk (GPT for >2TB)

For disks larger than 2TB use GPT and create one NTFS partition:

```bash
sudo parted /dev/sda
(parted) mklabel gpt
(parted) mkpart primary ntfs 0% 100%
(parted) print
(parted) quit
```

Adjust `/dev/sda` if your device letter differs. Confirm the new partition appears as `/dev/sda1` (or similar).

---

### 6) Format the partition (NTFS)

Create an NTFS filesystem on the new partition. The tool is `mkntfs` (no dot):

```bash
sudo mkntfs -f /dev/sda1
```

Tip: You can add a label, e.g. `-L NAS4TB`.

---

### 7) Create mount point and mount

```bash
sudo mkdir -p /mnt/nasdata
sudo mount -t ntfs /dev/sda1 /mnt/nasdata
lsblk -f
```

You should see `/dev/sda1` mounted at `/mnt/nasdata` and filesystem type `ntfs`.

---

### 8) Create a group and users

Create a group to manage access (example: `nasusers`). Add your admin user and any other users.

```bash
sudo groupadd nasusers
sudo usermod -aG nasusers <admin>
id <admin>
```

Create additional users as needed and add them to the group:

```bash
sudo adduser <user1>
sudo usermod -aG nasusers <user1>
sudo adduser <user2>
sudo usermod -aG nasusers <user2>
```

Note the UID/GID values from `id <user>` for fstab.

---

### 9) Configure auto-mount with fstab (NTFS)

Get the partition UUID:

```bash
sudo blkid /dev/sda1
```

Edit fstab:

```bash
sudo vim /etc/fstab
```

Add a line similar to this (replace UUID, uid/gid to match your admin user):

```
UUID=<uuid-from-blkid>  /mnt/nasdata  ntfs  defaults,uid=<uid>,gid=<gid>,umask=0007  0  0
```

Notes:
- `umask=0007` gives rwx to owner and group, no access to others.
- `uid/gid/umask` options apply to NTFS via ntfs-3g. For ext4, use Linux permissions instead (see note below).

Test before rebooting:

```bash
sudo umount /mnt/nasdata
sudo mount -a
lsblk -f
```

If `mount -a` returns an error, fix `/etc/fstab` immediately. Do not reboot until it mounts cleanly (a bad fstab can prevent boot).

Ext4 note: If you format the disk as ext4 instead of NTFS, omit uid/gid/umask in fstab and manage permissions with `chown/chmod` on the mounted directory. You can also run a small boot-time script if needed.

---

### 10) Prepare share directories and permissions

Create private directories per user and a common share, then set ownership to the admin user and group so group members can access:

```bash
sudo mkdir -p /mnt/nasdata/users/user1 /mnt/nasdata/users/user2 /mnt/nasdata/common
sudo chown -R <admin>:nasusers /mnt/nasdata
sudo chmod -R 770 /mnt/nasdata
```

`chmod 770` aligns with `umask=0007` in fstab (owner+group full, others none).

---

### 11) Configure Samba

Backup and edit Samba config:

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo vim /etc/samba/smb.conf
```

Under `[global]`, ensure at minimum:

```
[global]
	workgroup = WORKGROUP
	security = user
	map to guest = never
	server role = standalone server
```

Add private user shares and a common group share. Example:

```
[user1_share]
	path = /mnt/nasdata/users/user1
	valid users = user1
	read only = no
	browsable = yes

[user2_share]
	path = /mnt/nasdata/users/user2
	valid users = user2
	read only = no
	browsable = yes

[common]
	path = /mnt/nasdata/common
	valid users = @nasusers
	read only = no
	browsable = yes
```

Add Samba passwords for users (separate from Linux account passwords):

```bash
sudo smbpasswd -a user1
sudo smbpasswd -a user2
```

Restart Samba and check status:

```bash
sudo systemctl restart smbd nmbd
sudo systemctl status smbd --no-pager
```

On newer systems `nmbd` may not be present; `smbd` is sufficient.

---

### 12) Test from another computer

From Windows, map a network drive or connect via Explorer:

```
\\nas-pi.local\user1_share
\\nas-pi.local\common
```

Log in with the Samba username and Samba password you set with `smbpasswd`.

---

## Maintenance and useful commands

- Verify mounts and filesystems:

```bash
lsblk -f
df -h
sudo blkid
```

- Check disk health (SMART):

```bash
sudo smartctl -a /dev/sda
```

- Rsync example (backup common share to USB drive at `/media/usb`):

```bash
sudo rsync -avh --delete /mnt/nasdata/common/ /media/usb/common-backup/
```

---

## Notes and safety

- Always test `/etc/fstab` with `sudo mount -a` before rebooting. A broken fstab can prevent boot.
- For NTFS, `uid/gid/umask` are mount-time options; file-level Linux permissions are emulated. For native Linux permissions and best performance, consider formatting the data drive as ext4 if you don’t need Windows write access directly to the disk.
- Keep your SSH private key secure and use a passphrase. Refer to the SSH guide for details.


