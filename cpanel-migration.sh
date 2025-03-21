#!/bin/bash
#########################################################################
# cPanel Migration Tool Front-End (Enhanced Disk Checks + Cleanup + Warnings)
# Author: Matt Hodges
#########################################################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

LOGFILE="/var/log/cpanel-migration_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1  # Log stdout & stderr

WARN_FREE_SPACE_MB=15000   # 15GB - warning threshold
FAIL_FREE_SPACE_MB=10000   # 10GB - failure threshold

echo -e "${GREEN}Welcome to the cPanel Account Migration Tool!${NC}"
echo -e "${YELLOW}This script can migrate any number of cPanel accounts (1, multiple, or ALL).${NC}\n"
echo "Migration started at $(date)" | tee -a "$LOGFILE"

# 1. Prompt for Source & Target Server Info
read -p "Source VM hostname/IP: " SOURCE_VM
echo "Source VM: $SOURCE_VM" >> "$LOGFILE"

read -p "Source VM SSH port [22]: " SOURCE_SSH_PORT
SOURCE_SSH_PORT=${SOURCE_SSH_PORT:-22}
echo "Source SSH Port: $SOURCE_SSH_PORT" >> "$LOGFILE"

read -p "Target VM hostname/IP: " TARGET_VM
echo "Target VM: $TARGET_VM" >> "$LOGFILE"

read -p "Target VM SSH port [22]: " TARGET_SSH_PORT
TARGET_SSH_PORT=${TARGET_SSH_PORT:-22}
echo "Target SSH Port: $TARGET_SSH_PORT" >> "$LOGFILE"

# 2. Prompt for root passwords (if using password-based SSH)
echo -e "${YELLOW}If using password-based SSH, enter them now. If you use SSH keys, press Enter to skip.${NC}"
read -s -p "Root password for Source VM ($SOURCE_VM): " SOURCE_VM_PASSWORD
echo
read -s -p "Root password for Target VM ($TARGET_VM): " TARGET_VM_PASSWORD
echo

################################################################################
# Disk Space Check Functions
################################################################################

check_remote_disk_space() {
    local server="$1"
    local port="$2"
    local password="$3"
    local path="$4"
    local warn_threshold="$5"
    local fail_threshold="$6"

    echo -e "${YELLOW}Checking disk space on $server:$path...${NC}"
    local free_space
    free_space=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" root@"$server" "df -m $path | awk 'NR==2 {print \$4}'" 2>/dev/null)

    if [[ -z "$free_space" || ! "$free_space" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Unable to determine disk space on $server:$path.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}$server:$path has $free_space MB free.${NC}"

    if (( free_space < fail_threshold )); then
        echo -e "${RED}Error: Not enough free space on $server:$path. Required: ${fail_threshold}MB, Available: ${free_space}MB.${NC}"
        exit 1
    elif (( free_space < warn_threshold )); then
        echo -e "${YELLOW}Warning: $server:$path is above the fail threshold but below the warning threshold of ${warn_threshold}MB.${NC}"
        echo -e "${YELLOW}Migrations may succeed, but you're close to the limit.${NC}"
    fi
}

check_local_disk_space() {
    local path="$1"
    local warn_threshold="$2"
    local fail_threshold="$3"

    echo -e "${YELLOW}Checking local disk space at $path...${NC}"
    local free_space
    free_space=$(df -m "$path" | awk 'NR==2 {print $4}' 2>/dev/null)

    if [[ -z "$free_space" || ! "$free_space" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Unable to determine local disk space at $path.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Local path $path has $free_space MB free.${NC}"

    if (( free_space < fail_threshold )); then
        echo -e "${RED}Error: Not enough free space at $path. Required: ${fail_threshold}MB, Available: ${free_space}MB.${NC}"
        exit 1
    elif (( free_space < warn_threshold )); then
        echo -e "${YELLOW}Warning: $path is above fail threshold but below the warning threshold of ${warn_threshold}MB.${NC}"
        echo -e "${YELLOW}Migrations may succeed, but you're close to the limit.${NC}"
    fi
}

################################################################################
# 3. Perform Disk Space Checks
################################################################################

echo -e "${GREEN}Performing disk space checks on Source VM (/home), Jumpbox (/tmp), and Target VM (/home)${NC}"

# Source VM: /home
check_remote_disk_space "$SOURCE_VM" "$SOURCE_SSH_PORT" "$SOURCE_VM_PASSWORD" "/home" \
    "$WARN_FREE_SPACE_MB" "$FAIL_FREE_SPACE_MB"

# Jumpbox local: /tmp
check_local_disk_space "/tmp" "$WARN_FREE_SPACE_MB" "$FAIL_FREE_SPACE_MB"

# Target VM: /home
check_remote_disk_space "$TARGET_VM" "$TARGET_SSH_PORT" "$TARGET_VM_PASSWORD" "/home" \
    "$WARN_FREE_SPACE_MB" "$FAIL_FREE_SPACE_MB"

echo -e "${GREEN}Disk space checks passed (with possible warnings). Proceeding...${NC}"

################################################################################
# 4. Retrieve cPanel user list from Source
################################################################################
echo -e "\nRetrieving cPanel usernames from $SOURCE_VM (via /var/cpanel/users)..."
CPANEL_ACCOUNTS_LIST=$(sshpass -p "$SOURCE_VM_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$SOURCE_SSH_PORT" \
  root@$SOURCE_VM "ls /var/cpanel/users | xargs echo" 2>/dev/null)

if [[ -z "$CPANEL_ACCOUNTS_LIST" ]]; then
  echo -e "${RED}Error: No cPanel user files found in /var/cpanel/users on the source server.${NC}"
  exit 1
fi

echo -e "${GREEN}Available cPanel accounts on $SOURCE_VM:${NC}"
echo "$CPANEL_ACCOUNTS_LIST" | tr ' ' '\n'

echo -e "${YELLOW}\nEnter account names to migrate (space-separated), or type 'ALL' to migrate everything:${NC}"
read -r CPANEL_ACCOUNTS

if [[ "$CPANEL_ACCOUNTS" == "ALL" ]]; then
  CPANEL_ACCOUNTS=$CPANEL_ACCOUNTS_LIST
fi

echo "Selected accounts for migration: $CPANEL_ACCOUNTS" >> "$LOGFILE"

################################################################################
# 5. Domain Conflict Disclaimer
################################################################################
echo -e "${YELLOW}\nIMPORTANT DOMAIN DISCLAIMER:${NC}"
echo -e "  cPanel will NOT create a truly separate account under a new username if the same domain(s)"
echo -e "  already exist on the target server. The domain data might merge or skip."
echo -e "  To truly create a new account with the same domain, you must remove that domain"
echo -e "  from the existing account on the target, or rename the domain in the backup.\n"
echo "Domain conflict warning displayed to user at $(date)" >> "$LOGFILE"

################################################################################
# 6. Build JSON list with rename logic
################################################################################
renamed_accounts="["
first_item=1
max_length=16
suffix="_bak"

for acct in $CPANEL_ACCOUNTS; do
  # Check if acct exists on target
  account_exists=$(sshpass -p "$TARGET_VM_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$TARGET_SSH_PORT" \
    root@$TARGET_VM "test -f /var/cpanel/users/$acct && echo 'yes' || echo 'no'")

  if [[ $account_exists == "yes" ]]; then
    base="$acct"
    new_user="${base}${suffix}"

    # Ensure valid cPanel username length
    if [ ${#new_user} -gt $max_length ]; then
      keep=$(( max_length - ${#suffix} ))
      base="${base:0:$keep}"
      new_user="${base}${suffix}"
    fi

    echo -e "${YELLOW}User '$acct' exists on target. Renaming to '$new_user'.${NC}"
    echo "Renaming existing user '$acct' to '$new_user'" >> "$LOGFILE"
  else
    new_user="$acct"
  fi

  if [ $first_item -eq 1 ]; then
    renamed_accounts+="{\"orig\":\"$acct\",\"new\":\"$new_user\"}"
    first_item=0
  else
    renamed_accounts+=",{\"orig\":\"$acct\",\"new\":\"$new_user\"}"
  fi
done

renamed_accounts+="]"

echo -e "\n${GREEN}Final JSON for accounts:${NC} $renamed_accounts"
echo -e "${YELLOW}We will restore each original user to the 'new' user above.${NC}\n"
echo "Final account rename JSON: $renamed_accounts" >> "$LOGFILE"

################################################################################
# 7. Confirm & Run the Playbook
################################################################################
echo -e "${YELLOW}Proceed with migration? (y/n)${NC}"
read -r confirm
if [[ $confirm != "y" ]]; then
  echo -e "${RED}Migration cancelled.${NC}"
  echo "Migration cancelled by user at $(date)" >> "$LOGFILE"
  exit 0
fi

echo "Migration confirmed. Running Ansible playbook at $(date)" >> "$LOGFILE"

ANSIBLE_STDOUT_CALLBACK=debug ansible-playbook cpanel_migration.yml \
  -e "cpanel_accounts=$renamed_accounts \
       source_vm=$SOURCE_VM source_ssh_port=$SOURCE_SSH_PORT \
       target_vm=$TARGET_VM target_ssh_port=$TARGET_SSH_PORT \
       source_vm_password='$SOURCE_VM_PASSWORD' \
       target_vm_password='$TARGET_VM_PASSWORD'"

echo -e "${GREEN}\nMigration process complete. Check Ansible output for details.${NC}"
echo "Migration completed at $(date)" >> "$LOGFILE"

# Final Summary
echo -e "${YELLOW}========================================================${NC}"
echo -e "${GREEN}All specified cPanel accounts have been migrated to the target server: ${TARGET_VM}.${NC}"
echo -e "${YELLOW}If the same domain(s) existed on the target, cPanel may have merged or skipped domain data.${NC}"
echo -e "${YELLOW}For a fully independent account, remove conflicting domains before migration.${NC}"
echo -e "Please log in to WHM on https://${TARGET_VM}:2087 to confirm the final outcome."
echo -e "Migration log stored at: ${LOGFILE}"
echo -e "${GREEN}Thank you for using the cPanel Account Migration Tool!${NC}"
echo -e "${YELLOW}========================================================${NC}\n"
