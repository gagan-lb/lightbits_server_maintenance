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
    echo "Extracted hostname: $hostname"

    # Extract all IP addresses from the output
    local ip_addresses=$(echo "$output" | grep -oP 'inet \d+\.\d+\.\d+\.\d+' | awk '{print $2}' | grep -v '^127\.0\.0\.1')
    if [ -z "$ip_addresses" ]; then
        echo "Could not extract valid IP addresses. Please check the network configuration."
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
        echo "Could not map any IP addresses to a server. Please check the lbcli output."
        return 1
    fi

    # Get the server's state
    server_state=$(echo "$server_info" | grep "$server_name" | awk '{print $3}')

    if [ -n "$server_state" ]; then
        echo "Mapped server name: $server_name"
        echo "Current server state: $server_state"
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

    echo "Attempting to disable server $server_name..."
    run_remote_command "$username@$hostname" "$password" "sudo lbcli disable server --name=$server_name" > /dev/null 2>&1

    # Check server status after action
    local check_output=$(run_remote_command "$username@$hostname" "$password" "lbcli list servers | grep $server_name")
    local new_state=$(echo "$check_output" | awk '{print $3}')
    if [ "$new_state" == "Disabled" ]; then
        echo "Server $server_name is now disabled."
    else
        echo "Failed to disable server $server_name. Current state: $new_state."
    fi
}

# Function to enable the server
enable_server() {
    local hostname=$1
    local username=$2
    local password=$3
    local server_name=$4

    echo "Attempting to enable server $server_name..."
    run_remote_command "$username@$hostname" "$password" "sudo lbcli enable server --name=$server_name" > /dev/null 2>&1

    # Check server status after action
    local check_output=$(run_remote_command "$username@$hostname" "$password" "lbcli list servers | grep $server_name")
    local new_state=$(echo "$check_output" | awk '{print $3}')
    if [ "$new_state" == "Enabled" ]; then
        echo "Server $server_name is now enabled."
    else
        echo "Failed to enable server $server_name. Current state: $new_state."
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

    for service in "${services[@]}"; do
        echo "Disabling $service..."
        run_remote_command "$username@$hostname" "$password" "sudo systemctl disable $service"
        echo "Stopping $service..."
        run_remote_command "$username@$hostname" "$password" "sudo systemctl stop $service"
    done

    echo "All Lightbits services have been disabled and stopped."
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

    for service in "${services[@]}"; do
        echo "Enabling and starting $service..."
        if [ "$service" == "profile-generator" ]; then
            run_remote_command "$username@$hostname" "$password" "sudo systemctl enable --now $service" > /dev/null 2>&1
        else
            run_remote_command "$username@$hostname" "$password" "sudo systemctl enable --now $service"
            if [ $? -eq 0 ]; then
                echo "$service has been enabled and started successfully."
            else
                echo "Failed to enable and start $service. Please check the service manually."
            fi
        fi
    done

    echo "All Lightbits services have been enabled and started."
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

    local all_running=true

    for service in "${services[@]}"; do
        status=$(run_remote_command "$username@$hostname" "$password" "systemctl is-active $service")
        if [ "$status" != "active" ]; then
            all_running=false
            break
        fi
    done

    $all_running
}

# Pre-Maintenance function
pre_maintenance() {
    read -p "Enter the hostname: " hostname
    read -p "Enter the username (default: root): " username
    username=${username:-root}
    read -s -p "Enter the password: " password
    echo

    # Call to get_server_info
    if get_server_info "$hostname" "$username" "$password"; then
        # Now, check the server state
        if [[ "$server_state" == "Enabled" ]]; then
            read -p "Do you want to disable server $server_name? (y/n): " disable_choice
            if [[ $disable_choice =~ ^[Yy]$ ]]; then
                disable_server "$hostname" "$username" "$password" "$server_name"
            else
                echo "Server will remain enabled."
            fi
        elif [[ "$server_state" == "Disabled" ]]; then
            echo "Server $server_name is already disabled."
            read -p "Do you want to enable server $server_name? (y/n): " enable_choice
            if [[ $enable_choice =~ ^[Yy]$ ]]; then
                enable_server "$hostname" "$username" "$password" "$server_name"
            else
                echo "Server will remain disabled."
            fi
        fi

        # New section for disabling/stopping Lightbits services
        read -p "Do you want to disable and stop Lightbits services? (y/n): " lightbits_choice
        if [[ $lightbits_choice =~ ^[Yy]$ ]]; then
            disable_stop_lightbits_services "$hostname" "$username" "$password"
        else
            echo "Lightbits services will remain unchanged."
        fi
    fi
}

# Post-Maintenance function
post_maintenance() {
    read -p "Enter the hostname: " hostname
    read -p "Enter the username (default: root): " username
    username=${username:-root}
    read -s -p "Enter the password: " password
    echo

    # Verify connection
    if ! run_remote_command "$username@$hostname" "$password" "echo 'Connection successful'"; then
        echo "Failed to connect to the server. Please check your credentials and try again."
        return 1
    fi

    echo "Successfully connected to $hostname"

    # Check status of Lightbits services
    echo "Checking status of Lightbits services..."
    if check_lightbits_services "$hostname" "$username" "$password"; then
        echo "All Lightbits services are already running."
    else
        read -p "Lightbits services are not running. Do you want to enable and start Lightbits services? (y/n): " enable_services_choice
        if [[ $enable_services_choice =~ ^[Yy]$ ]]; then
            enable_start_lightbits_services "$hostname" "$username" "$password"
        else
            echo "Skipping enabling Lightbits services."
        fi
    fi

    # Section to enable the server
    read -p "Do you want to enable the server? (y/n): " enable_server_choice
    if [[ $enable_server_choice =~ ^[Yy]$ ]]; then
        echo "Attempting to enable the server..."
        server_info=$(run_remote_command "$username@$hostname" "$password" "sudo lbcli list servers")
        server_name=$(echo "$server_info" | awk 'NR==2 {print $1}')
        if [ -z "$server_name" ]; then
            echo "Failed to retrieve server name. Please check the server manually."
        else
            run_remote_command "$username@$hostname" "$password" "sudo lbcli enable server --name=$server_name"
            if [ $? -eq 0 ]; then
                echo "Server $server_name has been enabled successfully."
            else
                echo "Failed to enable server $server_name. Please check the server manually."
            fi
        fi
    else
        echo "Exiting without enabling the server."
    fi
}

# Main function
main() {
    while true; do
        echo "Select an option:"
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
