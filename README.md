# Family-Home-Server-and-NAS
This is the setup process and any scripts used to set up our family's Home Server. It has a shared file storage area and private sections for file storage. The equipment used to set this up is:

## Equipment List
- Raspberry Pi 5 (8GB) - Acting as the Home server and NAS (plans to host touchscreen with dashboard and photo display)
- Raspberry Pi 1 - Acting as the Pi-hole (plans to make it host a domain and VPN for security)
- Raspberry Pi 2 - (plans to be the onsite backup)
- My Personal computer - (Plans to remote in for gaming, virtualisation and developer work)
- Zimablade - (plans to be the offsite backup)
- 4TB NAS HDD - For the Server
- 6TB HDD - (plans for offsite and local Backup)

## Software for setup currently
- Samba protocol (NAS)
- SSH public key protocol
- Pi-Hole Network wide Adblocker


## To Do List

- [ ] Setup File system and automated backup system on Pi 5 and Pi 2 for NAS
	- [x] Setup Pi 5 with NAS visability on Linux and Windows using Samba
	- [x] Setup Private User Sections and Shared Photo Section with Admin access to all files
	- [ ] Setup Pi 2 to perform smooth easy recovery
	- [ ] Automate weekly backup with Wake-up Over LAN on Pi 2
	- [ ] Setup HDD health monitor with 3 months history saved on the Pi 2 and Pi 5
	- [ ] Setup automated health alert by email

- [ ] Test recovery system and iteration system
	- [ ] Revert one file
	- [ ] Revert full disk
	- [ ] Full recovery of old data on disk using backup
	- [ ] Test email alert and HDD health monitoring
	- [ ] Test file access

- [ ] Build Inclosures and Tidy cables
	- [ ] Build Pi 2 inclosure
	- [ ] Build Router Cable management system
	- [ ] Build Pi 5 inclosure with photo frame

- [ ] Setup file and photo additional file access methods and syncing
	- [ ] Setup phone access
	- [ ] Setup phone photo syncing to users private space with ability to transfer to shared area using immich
	- [ ] Setup password manager
	- [ ] Setup VPN

- [ ] Test non-local network access
	- [ ] Test it is secure and get checked with Dad
	- [ ] Setup domain

- [ ] Attach screen to Pi 5 and build photo frame
	- [ ] Attach screen to Pi 5
	- [ ] Setup 6 am to 10 pm photo viewer
	- [ ] Setup dashboard

- [ ] Powersaving setup
	- [ ] Setup control of smart plugs for backup systems
	- [ ] Setup idle system for NAS HDD

- [ ] Test full system and ensure Pi 1 works when Pi 5 fails and visa versa also check send checks if each other are running
