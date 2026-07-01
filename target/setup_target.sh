#!/bin/bash
# ============================================================
# Metasploitable2 Docker Auto-Setup Script
# Description : Pull and run Metasploitable2 as a Docker container
#               using host network mode so all vulnerable services
#               are accessible directly via the host IP.
# Usage       : sudo bash setup_target.sh
# Requirements: Ubuntu 18.04+ / Debian 9+ with internet access
# WARNING     : This machine will expose intentionally vulnerable
#               services. Run only in an isolated lab network.
# ============================================================

CONTAINER_NAME="metasploitable"
IMAGE="tleemcjr/metasploitable2"

# Terminal color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ports exposed by Metasploitable2 (verified against live netstat output)
PORTS=(21 22 23 25 80 111 139 445 512 513 514 1099 1524 2049 2121 3306 3632 5432 5900 6000 6667 6697 8009 8180 8787)

# ============================================================
# STEP 1: Check and install Docker if not present
# ============================================================
echo -e "${CYAN}[STEP 1] Checking Docker installation...${NC}"
if ! command -v docker &> /dev/null; then
  echo -e "${YELLOW}[INFO] Docker not found. Installing docker.io...${NC}"
  apt update -qq && apt install -y docker.io
  systemctl enable --now docker
  echo -e "${GREEN}[OK] Docker installed successfully.${NC}"
else
  echo -e "${GREEN}[OK] Docker is already installed: $(docker --version)${NC}"
fi

# ============================================================
# STEP 2: Remove existing container if it already exists
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
# STEP 3: Pull the latest Metasploitable2 image
# ============================================================
echo -e "\n${CYAN}[STEP 3] Pulling Metasploitable2 image...${NC}"
docker pull $IMAGE
echo -e "${GREEN}[OK] Image pulled successfully.${NC}"

# ============================================================
# STEP 4: Start the container in detached mode
#   --network host           : share host network (same IP as host)
#   --restart unless-stopped : auto-restart on reboot or crash
#   tail -f /dev/null        : keep container alive after services.sh
# ============================================================
echo -e "\n${CYAN}[STEP 4] Starting Metasploitable2 container...${NC}"
docker run -d \
  --name $CONTAINER_NAME \
  --network host \
  --restart unless-stopped \
  $IMAGE \
  sh -c "/bin/services.sh && tail -f /dev/null"

# Wait for slow-starting services (Tomcat, UnrealIRCd) to fully bind their ports
echo -e "${YELLOW}[INFO] Waiting 30 seconds for all services to come up...${NC}"
for i in $(seq 30 -1 1); do
  printf "\r  ${YELLOW}Waiting... %2d seconds remaining${NC}" $i
  sleep 1
done
echo ""

# ============================================================
# STEP 5: Verify container is running
# ============================================================
echo -e "\n${CYAN}[STEP 5] Verifying container status...${NC}"
CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER_NAME 2>/dev/null)
if [ "$CONTAINER_STATUS" == "running" ]; then
  echo -e "${GREEN}[OK] Container is running.${NC}"
else
  echo -e "${RED}[ERROR] Container failed to start. Status: $CONTAINER_STATUS${NC}"
  echo -e "${YELLOW}[HINT] Check logs with: sudo docker logs $CONTAINER_NAME${NC}"
  exit 1
fi

# ============================================================
# STEP 6: Check ports from inside the container
#         (more reliable than checking from host — avoids
#          false negatives caused by timing differences)
# ============================================================
echo -e "\n${CYAN}[STEP 6] Checking service ports (from inside container)...${NC}"
PASS=0
FAIL=0
for PORT in "${PORTS[@]}"; do
  if docker exec $CONTAINER_NAME netstat -tulpn 2>/dev/null | grep -q ":${PORT} "; then
    echo -e "  Port ${PORT}: ${GREEN}OPEN${NC}"
    ((PASS++))
  else
    echo -e "  Port ${PORT}: ${RED}CLOSED${NC}"
    ((FAIL++))
  fi
done

# ============================================================
# STEP 7: Verify key processes are running inside the container
# ============================================================
echo -e "\n${CYAN}[STEP 7] Checking running processes inside container...${NC}"
SERVICES=("apache2" "mysqld" "postgres" "proftpd" "smbd" "nmbd" "tomcat" "unrealircd" "xinetd" "distccd" "rmiregistry")
for SVC in "${SERVICES[@]}"; do
  if docker exec $CONTAINER_NAME ps aux 2>/dev/null | grep -v grep | grep -q "$SVC"; then
    echo -e "  ${GREEN}[OK]${NC} $SVC"
  else
    echo -e "  ${RED}[MISSING]${NC} $SVC"
  fi
done

# ============================================================
# SUMMARY
# ============================================================
HOST_IP=$(hostname -I | awk '{print $1}')
echo -e "\n============================================"
echo -e "${GREEN}  Metasploitable2 is ready!${NC}"
echo -e "============================================"
echo -e "  Target IP   : ${CYAN}${HOST_IP}${NC}"
echo -e "  Ports open  : ${GREEN}${PASS}${NC} / $((PASS + FAIL))"
echo -e ""
echo -e "  Useful commands:"
echo -e "  ${YELLOW}sudo docker ps${NC}                              — check container status"
echo -e "  ${YELLOW}sudo docker logs $CONTAINER_NAME${NC}            — view startup logs"
echo -e "  ${YELLOW}sudo docker exec -it $CONTAINER_NAME bash${NC}   — open shell inside"
echo -e "  ${YELLOW}sudo docker stop $CONTAINER_NAME${NC}            — stop container"
echo -e "  ${YELLOW}sudo docker start $CONTAINER_NAME${NC}           — start again"
echo -e "============================================"
