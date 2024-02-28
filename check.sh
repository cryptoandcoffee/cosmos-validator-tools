#!/bin/bash

# Initial Setup
validator="YOUR_WALLET_HERE"
META_JSON_URL="https://raw.githubusercontent.com/akash-network/net/main/mainnet/meta.json"
RPC_ENDPOINT="http://api.akt.computer:1317"

LOG_FILE="/var/log/akash_validator_check.log"

echo "--------------------------" | tee -a $LOG_FILE
echo "$(date): Checking validator $validator" | tee -a $LOG_FILE
echo "--------------------------" | tee -a $LOG_FILE

# Function to log messages
log_message() {
  echo "$(date): $1" | tee -a $LOG_FILE
}

# Check if node is synced using the local CLI
check_sync_status() {
  log_message "Checking if node is synced using local CLI..."
  
  # Fetching the node status using the Akash CLI
  local node_status=$(akash status 2>&1) # Redirecting stderr to stdout in case of an error
  
  # Extracting the 'catching_up' status
  local catching_up=$(echo "$node_status" | jq -r '.SyncInfo.catching_up')
  
  if [ "$catching_up" == "false" ]; then
    log_message "Node is synced."
  elif [ "$catching_up" == "true" ]; then
    log_message "Node is not synced. Exiting."
    exit 1
  else
    log_message "Unable to determine sync status. Please check the Akash CLI and your node."
    exit 1
  fi
}

# Function to check and update Akash version
check_version() {
  local recommended_version=$(curl -s $META_JSON_URL | jq -r '.codebase.recommended_version')
  log_message "Recommended version is $recommended_version"

  local installed_version=$(akash version)

  if [ "$recommended_version" != "$installed_version" ]; then
    log_message "Updating Akash from $installed_version to $recommended_version..."
    if curl -sSfL https://raw.githubusercontent.com/akash-network/node/main/install.sh | sh -s -- $recommended_version; then
      systemctl stop akash-node
      cp ./bin/akash /usr/local/bin/akash
      systemctl start akash-node
      log_message "Update completed - node restarted with new binary"
      rm -rf ./bin
    else
      log_message "Failed to update Akash. Check logs for details."
    fi
  else
    log_message "Akash is up to date."
  fi
}

# Check Disk Space
check_diskspace() {
  local disk_space_warning_threshold=75 # Set disk space warning threshold to 75%
  local disk=$(df -h | awk '$NF=="/"{print $1}')

  for d in $disk; do
    local usage=$(df -h | grep "$d " | awk '{print $5}' | sed 's/%//') # Remove '%' for comparison
    if [ "$usage" -gt "$disk_space_warning_threshold" ]; then
      log_message "Disk space is low on $d, $usage% full"
    else
      log_message "Disk space is good on $d, $usage% full"
    fi
  done
  echo "--------------------------" | tee -a $LOG_FILE
}

# Check Validator Status via RPC
check_validator_status() {
  log_message "Testing RPC Response"
  local url="$RPC_ENDPOINT/cosmos/staking/v1beta1/validators/$validator"
  local response=$(curl -s "$url")
  local status=$(echo $response | jq -r .[].status)
  local jailed=$(echo $response | jq -r .[].jailed)

  if [[ $status == "BOND_STATUS_BONDED" ]]; then
    log_message "Validator is bonded: $validator"
  else
    log_message "Validator not bonded: $validator"
  fi

  if [[ $jailed == "false" ]]; then
    log_message "Validator is not jailed"
  else
    log_message "Validator is JAILED"
  fi
  echo "--------------------------" | tee -a $LOG_FILE
}

# Show Outstanding Rewards
show_outstanding_rewards() {
  log_message "Fetching Outstanding Rewards"
  local rewards_url="http://api.akash.world:1317/cosmos/distribution/v1beta1/validators/$validator/outstanding_rewards"
  local rewards_response=$(curl -s "$rewards_url")
  local rewards=$(echo $rewards_response | jq -r '.rewards.rewards[] | select(.denom == "uakt") | .amount')

  if [ -z "$rewards" ]; then
    log_message "No outstanding rewards found."
  else
    # Convert from uakt (microakt) to AKT for readability
    local rewards_in_akt=$(echo "scale=6; $rewards / 1000000" | bc)
    log_message "Outstanding Rewards: $rewards_in_akt AKT"
  fi
  echo "--------------------------" | tee -a $LOG_FILE
}

# Show Outstanding Commissions using the 1317 LCD endpoint
show_outstanding_commissions() {
  log_message "Fetching Outstanding Commissions via HTTP 1317 endpoint"

  local validator_address="$validator"
  local lcd_endpoint="http://api.akash.world:1317"
  local commissions_url="${lcd_endpoint}/cosmos/distribution/v1beta1/validators/${validator_address}/commission"
  
  # Fetching commission data
  local commission_response=$(curl -s "$commissions_url")
  local commission=$(echo $commission_response | jq -r '.commission.commission[] | select(.denom == "uakt") | .amount')

  if [ -z "$commission" ]; then
    log_message "No outstanding commissions found."
  else
    # Assuming the commission is in microakt (uakt), converting to AKT for readability
    local commission_in_akt=$(echo "$commission / 1000000" | bc -l)
    log_message "Outstanding Commissions: $commission_in_akt AKT"
  fi
  echo "--------------------------" | tee -a $LOG_FILE
}

# Check System Resources (CPU and Memory)
check_system_resources() {
  log_message "Checking system resources..."
  local cpu_load=$(top -bn1 | grep "load average:" | awk '{print $10,$11,$12}')
  local memory_usage=$(free -m | awk 'NR==2{printf "Memory Usage: %s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')
  
  log_message "CPU Load: $cpu_load"
  log_message "$memory_usage"
}

# Check Network Latency
check_network_latency() {
  log_message "Checking network latency..."
  local latency=$(ping -c 4 google.com | tail -1| awk '{print $4}' | cut -d '/' -f 2)
  log_message "Average Latency: $latency ms"
}

# Check Node Health
check_node_health() {
  log_message "Checking node health..."
  local error_count=$(journalctl -u akash-node | grep -i error | wc -l)
  if [ "$error_count" -gt 0 ]; then
    log_message "Node has $error_count errors in the logs."
  else
    log_message "No errors found in node logs."
  fi
}

# Check Security Posture
check_security_posture() {
  log_message "Checking security posture..."
  local open_ports=$(ss -tuln | grep LISTEN)
  log_message "Open Ports: $open_ports"
}

# Main execution flow
check_sync_status
check_version
check_diskspace
check_validator_status
show_outstanding_rewards
show_outstanding_commissions
check_system_resources
check_network_latency
check_node_health
check_security_posture
