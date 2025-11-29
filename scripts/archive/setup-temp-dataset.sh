#!/usr/bin/env bash
# Setup script for creating the temp ZFS dataset on naspi
# This should be run BEFORE deploying the NixOS configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}NasPi Temp Dataset Setup${NC}"
echo -e "${GREEN}==================================================${NC}"
echo ""

# Check if running on naspi
if [[ "$(hostname)" != "naspi" ]]; then
  echo -e "${RED}ERROR: This script must be run on naspi${NC}"
  echo "Current hostname: $(hostname)"
  exit 1
fi

# Check if rpool exists
if ! zpool list rpool &>/dev/null; then
  echo -e "${RED}ERROR: ZFS pool 'rpool' not found${NC}"
  exit 1
fi

echo -e "${GREEN}✓ ZFS pool 'rpool' found${NC}"

# Check if rpool/data exists
if ! zfs list rpool/data &>/dev/null; then
  echo -e "${RED}ERROR: Dataset 'rpool/data' not found${NC}"
  echo "The temp dataset must be created as a child of rpool/data"
  exit 1
fi

echo -e "${GREEN}✓ Parent dataset 'rpool/data' found${NC}"

# Check if rpool/data/temp already exists
if zfs list rpool/data/temp &>/dev/null; then
  echo -e "${YELLOW}⚠ Dataset 'rpool/data/temp' already exists${NC}"
  echo ""
  echo "Current properties:"
  zfs get -o name,property,value compression,encryption,com.sun:auto-snapshot,quota,mounted,mountpoint rpool/data/temp
  echo ""
  read -r -p "Do you want to destroy and recreate it? (yes/no): " answer
  if [[ $answer == "yes" ]]; then
    echo -e "${YELLOW}Destroying existing dataset...${NC}"
    zfs destroy -r rpool/data/temp
    echo -e "${GREEN}✓ Dataset destroyed${NC}"
  else
    echo "Keeping existing dataset. Exiting."
    exit 0
  fi
fi

echo ""
echo -e "${GREEN}Creating ZFS dataset: rpool/data/temp${NC}"
echo ""

# Create the dataset
zfs create rpool/data/temp

echo -e "${GREEN}✓ Dataset created${NC}"

# Set properties
echo "Setting dataset properties..."

# Fast compression for better performance
zfs set compression=zstd-fast rpool/data/temp
echo -e "${GREEN}  ✓ compression=zstd-fast${NC}"

# Disable auto-snapshots (temporary data doesn't need backups)
zfs set com.sun:auto-snapshot=false rpool/data/temp
echo -e "${GREEN}  ✓ com.sun:auto-snapshot=false${NC}"

# Optional: Set a quota (default 100GB, adjust as needed)
# Uncomment the line below to set a quota
# zfs set quota=100G rpool/data/temp
# echo -e "${GREEN}  ✓ quota=100G${NC}"

echo ""
echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}Dataset Configuration Complete${NC}"
echo -e "${GREEN}==================================================${NC}"
echo ""
echo "Dataset properties:"
zfs get -o name,property,value all rpool/data/temp | grep -E "compression|encryption|auto-snapshot|quota|mounted|mountpoint"

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Deploy the NixOS configuration:"
echo "   ${YELLOW}./scripts/naspi-deploy.sh naspi.local switch${NC}"
echo ""
echo "2. After deployment, the share will be available at:"
echo "   ${YELLOW}smb://naspi/temp${NC}"
echo ""
echo -e "${GREEN}✓ Setup complete!${NC}"
