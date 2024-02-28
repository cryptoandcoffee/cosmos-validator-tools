#!/bin/bash

# Validator Operator Address
validator_address=""

# Wallet Address (Delegator Address for the Validator)
wallet_address=""

# Akash Node URL
akash_node="https://akash-rpc.polkachu.com:443"

# Initialize variables to store totals
total_rewards_uakt=0
total_commissions_uakt=0
total_sent_uakt=0

# Number of transactions to query in one go
limit=1000

# Function to fetch and sum amounts from transactions based on message action
fetch_and_sum() {
    local message_action="$1"
    local total_variable_name="$2"
    local page=1
    local more_pages=true

    while $more_pages; do
        transactions=$(akash query txs --node="$akash_node" --events "message.sender=${wallet_address}" --events "message.action=${message_action}" --page ${page} --limit ${limit} -o json 2>&1)

        # Check if the output contains the word "error"
        if [[ ! "$transactions" =~ "error" ]]; then
            break
        else
            # If there is an error, print a retrying message
            echo "Retrying..."
            # Optional: sleep for a few seconds before retrying
            sleep 3
        fi
    done

    if [ "$(echo $transactions | jq '.txs | length')" -eq 0 ]; then
        more_pages=false
    else
        amounts=$(echo "$transactions" | jq -r '.txs[] | .logs[] | .events[] | select(.type == "withdraw_rewards" or .type == "withdraw_commission" or .type == "transfer") | .attributes[] | select(.key == "amount") | .value' | grep -o '[0-9]*')

        for amount in $amounts; do
            eval $total_variable_name'=$(($'"$total_variable_name"' + amount))'
        done

        if [ "$(echo $transactions | jq '.txs | length')" -lt $limit ]; then
            more_pages=false
        else
            ((page++))
        fi
    fi
}

# Function to fetch and sum sent transactions amount
fetch_and_sum_sent() {
    local page=1
    local more_pages=true

    while $more_pages; do
        transactions=$(akash query txs --node="$akash_node" --events "transfer.sender=${wallet_address}" --page ${page} --limit ${limit} -o json)

        if [ "$(echo $transactions | jq '.txs | length')" -eq 0 ]; then
            more_pages=false
        else
            amounts=$(echo "$transactions" | jq -r '.txs[] | .logs[] | .events[] | select(.type == "transfer") | .attributes[] | select(.key == "amount") | .value' | grep -o '[0-9]*')

            for amount in $amounts; do
                total_sent_uakt=$(($total_sent_uakt + amount))
            done

            if [ "$(echo $transactions | jq '.txs | length')" -lt $limit ]; then
                more_pages=false
            else
                ((page++))
            fi
        fi
    done
}

# Fetch and sum rewards, commissions, and sent amounts
fetch_and_sum "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward" "total_rewards_uakt"
fetch_and_sum "/cosmos.distribution.v1beta1.MsgWithdrawValidatorCommission" "total_commissions_uakt"
fetch_and_sum_sent

# Convert totals from uakt to AKT
total_rewards_akt=$(echo "scale=6; $total_rewards_uakt / 1000000" | bc)
total_commissions_akt=$(echo "scale=6; $total_commissions_uakt / 1000000" | bc)
total_sent_akt=$(echo "scale=6; $total_sent_uakt / 1000000" | bc)

# Fetch AKT to USD exchange rate
akt_usd_price=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=akash-network&vs_currencies=usd" | jq -r '.["akash-network"].usd')

# Convert total earnings and sent amounts to USD
total_rewards_usd=$(echo "scale=2; $total_rewards_akt * $akt_usd_price" | bc)
total_commissions_usd=$(echo "scale=2; $total_commissions_akt * $akt_usd_price" | bc)
total_sent_usd=$(echo "scale=2; $total_sent_akt * $akt_usd_price" | bc)

echo "Total Rewards: $total_rewards_akt AKT ($total_rewards_usd USD)"
echo "Total Commissions: $total_commissions_akt AKT ($total_commissions_usd USD)"
echo "Total Sent: $total_sent_akt AKT ($total_sent_usd USD)"
