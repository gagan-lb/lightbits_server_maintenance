#!/bin/bash

# Usage function
usage() {
    echo "Usage: $0"
    echo "This script manages server maintenance tasks, including disabling/enabling servers and Lightbits services."
    exit 1
}

# Function to run commands on the remote server
run_remote_command() {
    local server=$1
    local password=$2
    local command=$3
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$server" "$command"
}

# Function to get server name and status
get_server_info() {
    local hostname=$1
    local username=$2
    local password=$3

    echo "Connecting to $username@$hostname..."
    output=$(run_remote_command "$username@$hostname" "$password" "
        ip addr show
        echo '---'
        lbcli list nodes
        echo '---'
        lbcli list servers
        ") || { echo "Failed to connect. Please check the hostname, username, and password."; return 1; }

    # Extract hostname
    echo "Hostname: $hostname"

    # Extract all IP addresses from the output
    local ip_addresses=$(echo "$output" | grep -oP 'inet \d+\.\d+\.\d+\.\d+' | awk '{print $2}' | grep -v '^127\.0\.0\.1')
    if [ -z "$ip_addresses" ]; then
        echo "Error: Could not extract valid IP addresses. Please check the network configuration."
        return 1
    fi

    # Extract node information
    local node_info=$(echo "$output" | sed -n '/Name\s\+UUID\s\+State\s\+NVMe endpoint/,/^$/p')
    local server_info=$(echo "$output" | sed -n '/NAME\s\+UUID\s\+State/,/^$/p')

    # Loop through IP addresses to find corresponding node
    server_name=""
    server_state=""

    for ip in $ip_addresses; do
        # Find the node associated with the IP
        local node_line=$(echo "$node_info" | grep "$ip")
        if [ -n "$node_line" ]; then
            local node_name=$(echo "$node_line" | awk '{print $1}')
            server_name=$(echo "$node_name" | sed 's/-0$//')  # Remove the trailing -0 to get the server name
            break  # Exit the loop once we find the first matching IP
        fi
    done

    if [ -z "$server_name" ]; then
        echo "Error: Could not map any IP addresses to a server. Please check the lbcli output."
        return 1
    fi

    # Get the server's state
    server_state=$(echo "$server_info" | grep "$server_name" | awk '{print $3}')

    if [ -n "$server_state" ]; then
        echo "Server name: $server_name"
        echo "Current state: $server_state"
        return 0
    fi

    return 1
}

# Function to disable the server
disable_server() {
    local hostname=$1
    local username=$2
    local password=$3
    local server_name=$4

    echo "Disabling server $server_name..."
    sleep 5  # Add 5 seconds delay
    run_remote_command "$username@$hostname" "$password" "sudo lbcli disable server --name=$server_name" > /dev/null 2>&1
    sleep 5  # Add 5 seconds delay after executing lbcli disable

    # Check server status after action
    local check_output=$(run_remote_command "$username@$hostname" "$password" "lbcli list servers | grep $server_name")
    local new_state=$(echo "$check_output" | awk '{print $3}')
    if [ "$new_state" == "Disabled" ]; then
        echo "Server $server_name has been disabled successfully."
    else
        echo "Error: Failed to disable server $server_name. Current state: $new_state."
    fi
}

# Function to enable the server
enable_server() {
    local hostname=$1
    local username=$2
    local password=$3
    local server_name=$4

    echo "Enabling server $server_name..."
    sleep 5  # Add 5 seconds delay
    run_remote_command "$username@$hostname" "$password" "sudo lbcli enable server --name=$server_name" > /dev/null 2>&1
    sleep 5  # Add 5 seconds delay after executing lbcli enable

    # Check server status after action
    local check_output=$(run_remote_command "$username@$hostname" "$password" "lbcli list servers | grep $server_name")
    local new_state=$(echo "$check_output" | awk '{print $3}')
    if [ "$new_state" == "Enabled" ]; then
        echo "Server $server_name has been enabled successfully."
    else
        echo "Error: Failed to enable server $server_name. Current state: $new_state."
    fi
}

# Function to disable and stop Lightbits services
disable_stop_lightbits_services() {
    local hostname=$1
    local username=$2
    local password=$3

    local services=(
        "api-service"
        "profile-generator"
        "node-manager"
        "cluster-manager"
        "discovery-service"
        "lightbox-exporter"
        "upgrade-manager"
        "etcd"
    )

    echo "Disabling and stopping Lightbits services..."
    sleep 5  # Add 5 seconds delay
    for service in "${services[@]}"; do
        run_remote_command "$username@$hostname" "$password" "sudo systemctl disable $service && sudo systemctl stop $service" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "  - $service: Disabled and stopped"
        else
            echo "  - $service: Failed to disable and stop"
        fi
        sleep 5  # Add 5 seconds delay after each service
    done

    echo "All Lightbits services have been processed."
}

# Function to enable and start Lightbits services
enable_start_lightbits_services() {
    local hostname=$1
    local username=$2
    local password=$3

    local services=(
        "profile-generator"
        "etcd"
        "cluster-manager"
        "node-manager"
        "discovery-service"
        "lightbox-exporter"
        "upgrade-manager"
        "api-service"
    )

    echo "Enabling and starting Lightbits services..."
    sleep 5  # Add 5 seconds delay
    for service in "${services[@]}"; do
        run_remote_command "$username@$hostname" "$password" "sudo systemctl enable --now $service" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "  - $service: Enabled and started"
        else
            echo "  - $service: Failed to enable and start"
        fi
        sleep 5  # Add 5 seconds delay after each service
    done

    echo "All Lightbits services have been processed."
}

# Function to check Lightbits services status
check_lightbits_services() {
    local hostname=$1
    local username=$2
    local password=$3

    local services=(
        "profile-generator"
        "etcd"
        "cluster-manager"
        "node-manager"
        "discovery-service"
        "lightbox-exporter"
        "upgrade-manager"
        "api-service"
    )

    echo "Checking status of Lightbits services..."
    sleep 5  # Add 5 seconds delay
    for service in "${services[@]}"; do
        status=$(run_remote_command "$username@$hostname" "$password" "systemctl is-active $service")
        echo "  - $service: $status"
    done
}

# Pre-Maintenance function
pre_maintenance() {
    read -p "Enter the hostname: " hostname
    read -p "Enter the username (default: root): " username
    username=${username:-root}
    read -s -p "Enter the password: " password
    echo

    if get_server_info "$hostname" "$username" "$password"; then
        echo  # Add extra space
        if [[ "$server_state" == "Enabled" ]]; then
            read -p "Do you want to disable server $server_name? (y/n): " disable_choice
            if [[ $disable_choice =~ ^[Yy]$ ]]; then
                disable_server "$hostname" "$username" "$password" "$server_name"
            else
                echo "Server will remain enabled."
            fi
        elif [[ "$server_state" == "Disabled" ]]; then
            echo "Server $server_name is already disabled."
        fi
        echo  # Add extra space

        read -p "Do you want to disable and stop Lightbits services? (y/n): " lightbits_choice
        if [[ $lightbits_choice =~ ^[Yy]$ ]]; then
            echo  # Add extra space
            disable_stop_lightbits_services "$hostname" "$username" "$password"
        else
            echo "Lightbits services will remain unchanged."
        fi
    fi
    echo  # Add extra space
}

# Post-Maintenance function
post_maintenance() {
    read -p "Enter the hostname: " hostname
    read -p "Enter the username (default: root): " username
    username=${username:-root}
    read -s -p "Enter the password: " password
    echo

    if ! run_remote_command "$username@$hostname" "$password" "echo 'Connection successful'" > /dev/null 2>&1; then
        echo "Error: Failed to connect to the server. Please check your credentials and try again."
        return 1
    fi

    echo "Successfully connected to $hostname"
    echo  # Add extra space

    check_lightbits_services "$hostname" "$username" "$password"
    echo  # Add extra space

    read -p "Do you want to enable and start Lightbits services? (y/n): " enable_services_choice
    if [[ $enable_services_choice =~ ^[Yy]$ ]]; then
        echo  # Add extra space
        enable_start_lightbits_services "$hostname" "$username" "$password"
    else
        echo "Skipping enabling Lightbits services."
    fi
    echo  # Add extra space

    read -p "Do you want to enable the server? (y/n): " enable_server_choice
    if [[ $enable_server_choice =~ ^[Yy]$ ]]; then
        echo "Retrieving server information..."
        server_info=$(run_remote_command "$username@$hostname" "$password" "sudo lbcli list servers")
        server_name=$(echo "$server_info" | awk 'NR==2 {print $1}')
        if [ -z "$server_name" ]; then
            echo "Error: Failed to retrieve server name. Please check the server manually."
        else
            enable_server "$hostname" "$username" "$password" "$server_name"
        fi
        
        echo  # Add extra space
        read -p "Do you want to check the status of all Lightbits services? (y/n): " check_services_choice
        if [[ $check_services_choice =~ ^[Yy]$ ]]; then
            echo  # Add extra space
            check_lightbits_services "$hostname" "$username" "$password"
        else
            echo "Skipping service status check."
        fi
    else
        echo "Skipping server enablement."
    fi
    echo  # Add extra space
}

# Main function
main() {
    while true; do
        echo -e "\nLightbits Server Maintenance Script"
        echo "1) Pre-Maintenance"
        echo "2) Post-Maintenance"
        echo "3) Exit"
        read -p "Enter your choice (1/2/3): " choice

        case $choice in
            1)
                pre_maintenance
                ;;
            2)
                post_maintenance
                ;;
            3)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Run the main function
main

# Exit the script
exit 0
