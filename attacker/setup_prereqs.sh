#!/bin/bash
# ============================================================
# Attacker Machine — One-Time Prerequisite Setup
# Description : Installs Docker and whiptail, and pulls the
#               Metasploit Framework image. Run this once before
#               using setup_attacker.sh (the attack menu).
# Usage       : sudo bash setup_prereqs.sh
# Requirements: Ubuntu 18.04+ / Debian 9+ with internet access
# ============================================================

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
# STEP 2: Check and install whiptail (powers the attack-menu TUI)
# ============================================================
echo -e "\n${CYAN}[STEP 2] Checking whiptail installation...${NC}"
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
# STEP 3: Pull the Metasploit Framework image
# ============================================================
echo -e "\n${CYAN}[STEP 3] Pulling Metasploit Framework image...${NC}"
docker pull $IMAGE
echo -e "${GREEN}[OK] Image pulled successfully.${NC}"

# ============================================================
# STEP 4: Create local MSF data directory
#         Mounted into the container so that:
#         - loot, credentials, sessions persist between runs
#         - custom modules and scripts can be added from host
# ============================================================
echo -e "\n${CYAN}[STEP 4] Setting up persistent MSF data directory...${NC}"
mkdir -p "$MSF_DATA"
echo -e "${GREEN}[OK] MSF data directory ready at: $MSF_DATA${NC}"

echo -e "\n============================================"
echo -e "${GREEN}  Prerequisites ready.${NC}"
echo -e "============================================"
echo -e "  Now run the attack menu:"
echo -e "  ${YELLOW}sudo bash setup_attacker.sh${NC}"
echo -e "============================================"
