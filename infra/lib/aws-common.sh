#!/bin/bash

# ============================================================================
# AWS Infrastructure Common Functions
# ============================================================================
# Shared utilities for AWS infrastructure setup and cleanup scripts.
# Source this file from your scripts: source "$(dirname "$0")/lib/aws-common.sh"
# ============================================================================

# Default config file path (can be overridden before sourcing)
CONFIG_FILE="${CONFIG_FILE:-infra/awsConfig.json}"

# ===== UTILITIES =====

# Print functions with consistent formatting
print_header() {
    echo "========================================="
    echo "   $1"
    echo "========================================="
}

print_step() {
    echo "SETUP: $1"
}

print_cleanup() {
    echo "CLEANUP: $1"
}

print_success() {
    echo "✅ $1"
}

print_warning() {
    echo "⚠️  $1"
}

print_error() {
    echo "❌ $1"
}

print_waiting() {
    echo "⏳ $1"
}

print_info() {
    echo "ℹ️  $1"
}

# ===== CONFIG MANAGEMENT =====

# Check that config file exists
validate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found at $CONFIG_FILE"
        exit 1
    fi
}

# Read a value from the config file
# Usage: read_config ".project" or read_config ".resources.vpc_id"
read_config() {
    jq -r "$1" "$CONFIG_FILE"
}

# Update a value in the resources section of config
# Usage: update_config "vpc_id" "vpc-12345"
update_config() {
    local key="$1"
    local value="$2"
    local tmp=$(mktemp)
    jq --arg val "$value" ".resources.$key = \$val" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

# Clear a value in resources (set to empty string)
# Usage: clear_config "vpc_id"
clear_config() {
    update_config "$1" ""
}

# ===== DEPENDENCY CHECKS =====

# Check if required tools are installed
check_dependencies() {
    local missing=()
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing[*]}"
        echo "Please install them before running this script."
        exit 1
    fi
}

# ===== AWS HELPERS =====

# Check if a resource ID is valid (not empty or null)
# Usage: if is_valid_id "$VPC_ID"; then ...
is_valid_id() {
    local id="$1"
    [ -n "$id" ] && [ "$id" != "null" ] && [ "$id" != "None" ]
}

# Wait for a resource with a spinner
# Usage: wait_with_message "Waiting for NAT Gateway..." aws ec2 wait nat-gateway-available ...
wait_with_message() {
    local message="$1"
    shift
    print_waiting "$message"
    "$@"
}

# Tag a resource with Name tag
# Usage: tag_resource "$RESOURCE_ID" "my-resource-name" "$REGION"
tag_resource() {
    local resource_id="$1"
    local name="$2"
    local region="$3"
    aws ec2 create-tags --resources "$resource_id" --tags Key=Name,Value="$name" --region "$region"
}

# Safely delete a security group (ignore if already deleted)
# Usage: safe_delete_sg "$SG_ID" "$REGION"
safe_delete_sg() {
    local sg_id="$1"
    local region="$2"
    aws ec2 delete-security-group --group-id "$sg_id" --region "$region" > /dev/null 2>&1 || true
}

# ===== LOAD COMMON VARIABLES =====

# Load project variables from config
load_project_vars() {
    validate_config
    
    PROJECT=$(read_config ".project")
    REGION=$(read_config ".region")
    
    export PROJECT REGION
}

# Load all resource IDs from config
load_resource_vars() {
    VPC_ID=$(read_config ".resources.vpc_id")
    PUB_SUBNET_ID=$(read_config ".resources.public_subnet_id")
    PRI_SUBNET_ID=$(read_config ".resources.private_subnet_id")
    IGW_ID=$(read_config ".resources.internet_gateway_id")
    NAT_GW_ID=$(read_config ".resources.nat_gateway_id")
    NAT_EIP_ID=$(read_config ".resources.nat_eip_id")
    PROXY_SG_ID=$(read_config ".resources.proxy_sg_id")
    MC_SG_ID=$(read_config ".resources.mc_sg_id")
    ALLOCATION_ID=$(read_config ".resources.proxy_allocation_id")
    PROXY_INSTANCE_ID=$(read_config ".resources.proxy_instance_id")
    MC_INSTANCE_ID=$(read_config ".resources.mc_instance_id")
    
    export VPC_ID PUB_SUBNET_ID PRI_SUBNET_ID IGW_ID NAT_GW_ID NAT_EIP_ID
    export PROXY_SG_ID MC_SG_ID ALLOCATION_ID PROXY_INSTANCE_ID MC_INSTANCE_ID
}

# Load infrastructure settings from config
load_infra_settings() {
    AMI_ID=$(read_config ".ami_id")
    INSTANCE_TYPE_PROXY=$(read_config ".instance_type_proxy")
    INSTANCE_TYPE_MC=$(read_config ".instance_type_mc")
    KEY_NAME=$(read_config ".key_name")
    PROXY_STORAGE=$(read_config ".storage.proxy_size_gb")
    MC_STORAGE=$(read_config ".storage.mc_size_gb")
    VOL_TYPE=$(read_config ".storage.volume_type")
    
    export AMI_ID INSTANCE_TYPE_PROXY INSTANCE_TYPE_MC KEY_NAME
    export PROXY_STORAGE MC_STORAGE VOL_TYPE
}
