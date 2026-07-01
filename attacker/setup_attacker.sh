#!/bin/bash
# ============================================================
# Metasploit Framework Docker Auto-Setup Script
# Description : Pull and run Metasploit Framework as a Docker
#               container on the attacker machine. Includes
#               nmap and other recon tools.
# Usage       : sudo bash setup_attacker.sh
# Requirements: Ubuntu 18.04+ / Debian 9+ with internet access
# ============================================================

CONTAINER_NAME="msf"
IMAGE="metasploitframework/metasploit-framework"
MSF_DATA="$HOME/.msf4"

# Terminal color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# STEP 0: Repair Kali's archive keyring if the package index is
#         unsigned (NO_PUBKEY / "repository is not signed"). This
#         happens on Kali images with a stale kali-archive-keyring
#         and blocks apt-get update for every step below, including
#         Docker's own install script.
# ============================================================
if grep -qi '^ID=kali' /etc/os-release 2>/dev/null; then
  echo -e "${CYAN}[STEP 0] Kali detected — checking package index signature...${NC}"
  if ! apt-get update -qq 2>/dev/null; then
    echo -e "${YELLOW}[INFO] Package index is unsigned (stale keyring). Repairing kali-archive-keyring...${NC}"
    apt-get update -qq --allow-unauthenticated
    apt-get install -y --allow-unauthenticated --reinstall kali-archive-keyring
    if ! apt-get update -qq; then
      echo -e "${RED}[ERROR] Could not repair the Kali keyring automatically.${NC}"
      echo -e "${YELLOW}[HINT] Try manually:${NC}"
      echo -e "  sudo apt-get update --allow-unauthenticated"
      echo -e "  sudo apt-get install --reinstall kali-archive-keyring"
      exit 1
    fi
    echo -e "${GREEN}[OK] Kali archive keyring repaired.${NC}"
  else
    echo -e "${GREEN}[OK] Package index is valid.${NC}"
  fi
fi

# ============================================================
# STEP 1: Check and install Docker if not present
# ============================================================
echo -e "${CYAN}[STEP 1] Checking Docker installation...${NC}"
if ! command -v docker &> /dev/null; then
  echo -e "${YELLOW}[INFO] Docker not found. Installing via get.docker.com (official script — avoids distro repo/keyring issues, e.g. on Kali)...${NC}"
  if ! curl -fsSL https://get.docker.com | sh; then
    echo -e "${RED}[ERROR] Docker installation failed. Aborting.${NC}"
    exit 1
  fi
  systemctl enable --now docker
  # Add the invoking user (not root) to the docker group to allow running without sudo
  if [ -n "$SUDO_USER" ]; then
    usermod -aG docker "$SUDO_USER"
  fi
  echo -e "${GREEN}[OK] Docker installed. You may need to re-login for group change to take effect.${NC}"
else
  echo -e "${GREEN}[OK] Docker is already installed: $(docker --version)${NC}"
fi

if ! command -v docker &> /dev/null; then
  echo -e "${RED}[ERROR] Docker still not available after installation attempt. Aborting.${NC}"
  exit 1
fi

# ============================================================
# STEP 1b: Check and install whiptail (powers the TUI prompt)
# ============================================================
echo -e "\n${CYAN}[STEP 1b] Checking whiptail installation...${NC}"
if ! command -v whiptail &> /dev/null; then
  echo -e "${YELLOW}[INFO] whiptail not found. Installing...${NC}"
  if ! (apt update -qq && apt install -y whiptail); then
    echo -e "${RED}[ERROR] whiptail installation failed. Aborting.${NC}"
    exit 1
  fi
  echo -e "${GREEN}[OK] whiptail installed.${NC}"
else
  echo -e "${GREEN}[OK] whiptail is already installed.${NC}"
fi

# ============================================================
# STEP 2: Remove existing MSF container if it already exists
# ============================================================
echo -e "\n${CYAN}[STEP 2] Checking for existing container...${NC}"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo -e "${YELLOW}[INFO] Found existing container '$CONTAINER_NAME'. Removing it...${NC}"
  docker stop $CONTAINER_NAME 2>/dev/null
  docker rm $CONTAINER_NAME 2>/dev/null
  echo -e "${GREEN}[OK] Old container removed.${NC}"
else
  echo -e "${GREEN}[OK] No existing container found. Proceeding...${NC}"
fi

# ============================================================
# STEP 3: Pull the latest Metasploit Framework image
# ============================================================
echo -e "\n${CYAN}[STEP 3] Pulling Metasploit Framework image...${NC}"
docker pull $IMAGE
echo -e "${GREEN}[OK] Image pulled successfully.${NC}"

# ============================================================
# STEP 4: Create local MSF data directory
#         Mounted into container so that:
#         - loot, credentials, sessions persist between runs
#         - custom modules and scripts can be added from host
# ============================================================
echo -e "\n${CYAN}[STEP 4] Setting up persistent MSF data directory...${NC}"
mkdir -p "$MSF_DATA"
echo -e "${GREEN}[OK] MSF data directory ready at: $MSF_DATA${NC}"

# ============================================================
# STEP 5: Ask user for target IP via whiptail TUI input box
# ============================================================
echo -e "\n${CYAN}[STEP 5] Target configuration...${NC}"

TARGET_IP=$(whiptail --title "Metasploit Attacker Setup" \
  --inputbox "Enter target IP (Metasploitable2 host IP):" 10 60 "192.168.2.20" \
  3>&1 1>&2 2>&3)
TUI_EXIT=$?

if [ $TUI_EXIT -ne 0 ] || [ -z "$TARGET_IP" ]; then
  echo -e "${YELLOW}[WARN] No target IP provided. You can set RHOSTS manually inside msfconsole.${NC}"
  TARGET_IP="<TARGET_IP>"
else
  echo -e "${GREEN}[OK] Target IP set to: $TARGET_IP${NC}"
fi

# ============================================================
# STEP 6: Run Metasploit container
#   --network host    : use host network so MSF can reach target
#   -v               : mount local .msf4 for persistent data
#   -e LHOST         : set attacker IP automatically
#   -it              : interactive terminal for msfconsole
# ============================================================
echo -e "\n${CYAN}[STEP 6] Starting Metasploit Framework container...${NC}"

LHOST=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}[INFO] Attacker IP (LHOST): ${LHOST}${NC}"
echo -e "${YELLOW}[INFO] Target IP  (RHOSTS): ${TARGET_IP}${NC}"
echo ""

docker run -it \
  --name $CONTAINER_NAME \
  --network host \
  -e LHOST="$LHOST" \
  -e RHOSTS="$TARGET_IP" \
  -v "$MSF_DATA":/home/msf/.msf4 \
  $IMAGE \
  msfconsole -q -x "setg LHOST $LHOST; setg RHOSTS $TARGET_IP"

# ============================================================
# STEP 7: Cleanup after exit — remove container
#         (data is preserved in $MSF_DATA on host)
# ============================================================
echo -e "\n${CYAN}[STEP 7] Cleaning up container after exit...${NC}"
docker rm $CONTAINER_NAME 2>/dev/null
echo -e "${GREEN}[OK] Container removed. MSF data preserved at: $MSF_DATA${NC}"

# ============================================================
# SUMMARY — Quick reference for next run
# ============================================================
echo -e "\n============================================"
echo -e "${GREEN}  Metasploit session ended.${NC}"
echo -e "============================================"
echo -e "  To start again:"
echo -e "  ${YELLOW}sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/sudichai/metasploitable2-docker-lab/master/attacker/setup_attacker.sh)\"${NC}"
echo -e ""
echo -e "  Useful MSF modules for Metasploitable2:"
echo -e "  ${CYAN}exploit/unix/ftp/vsftpd_234_backdoor${NC}      (port 21)"
echo -e "  ${CYAN}exploit/multi/samba/usermap_script${NC}        (port 445)"
echo -e "  ${CYAN}exploit/unix/irc/unreal_ircd_3281_backdoor${NC} (port 6667)"
echo -e "  ${CYAN}exploit/unix/misc/distcc_exec${NC}             (port 3632)"
echo -e "  ${CYAN}exploit/multi/misc/java_rmi_server${NC}        (port 1099)"
echo -e "  ${CYAN}exploit/multi/http/tomcat_mgr_deploy${NC}      (port 8180)"
echo -e "  ${CYAN}auxiliary/scanner/postgres/postgres_login${NC} (port 5432)"
echo -e "  ${CYAN}auxiliary/scanner/mysql/mysql_login${NC}       (port 3306)"
echo -e "============================================"
