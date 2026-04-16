#!/bin/bash

# ================================================
# User Administration Script 
#
# Name format: "Last, First" (with comma and space)
# ================================================

# Configuration
LOG_FILE="/var/log/user_admin.log"
PIN_LOG_DIR="/var/secure"
PIN_LOG_FILE="${PIN_LOG_DIR}/user_pins.log"

# Create secure directory if it doesn't exist (only root/owner can access)
if [ ! -d "$PIN_LOG_DIR" ]; then
    mkdir -p "$PIN_LOG_DIR"
    chmod 700 "$PIN_LOG_DIR"
fi

# Tier system 
# junior   -> basic access
# senior   -> inherits junior + more
# management -> inherits senior + full admin capabilities
declare -A TIERS
TIERS["junior"]="junior"
TIERS["senior"]="junior senior"
TIERS["management"]="junior senior management"

# Function: Log actions (with timestamp)
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null
}

# Function: Generate random 4-digit PIN
generate_pin() {
    printf "%04d" $((RANDOM % 10000))
}

# Function: Convert "Last, First" to username (e.g., "Dave, Cassidy" -> "dcassidy")
name_to_username() {
    local name="$1"
    # Remove spaces after comma, lowercase, take first letter of first + last name
    echo "$name" | sed 's/ *, */,/g' | tr '[:upper:]' '[:lower:]' | awk -F, '{print substr($2,1,1) $1}'
}

# Function: Display help
show_help() {
    cat << EOF
Usage: $0 [OPTION] "Last, First"

Options:
  -h              Show this help message
  -a "Last, First" Add a new user (prompts for tier)
  -r "Last, First" Remove an existing user
  -e "Last, First" Edit an existing user's tier/privileges

Name must be in "Last, First" format (comma + space).

Tiers available:
  junior     - Basic access (group: junior)
  senior     - Team access (groups: junior, senior)
  management - Full administrative access (groups: junior, senior, management)

The script automatically creates required groups if they don't exist.
EOF
}

# Function: Check if name format is valid
validate_name() {
    if [[ ! "$1" =~ ^[A-Za-z]+,[[:space:]]*[A-Za-z]+$ ]]; then
        echo "Error: Name must be in format \"Last, First\" (e.g., \"Smith, John\")"
        return 1
    fi
    return 0
}

# Function: Ensure groups exist
ensure_groups() {
    for group in junior senior management; do
        if ! getent group "$group" > /dev/null; then
            groupadd "$group"
            log_action "Created group: $group"
            echo "Created group: $group"
        fi
    done
}

# Main script logic
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

OPTION="$1"
shift

case "$OPTION" in
    -h)
        show_help
        exit 0
        ;;

    -a)
        NAME="$1"
        if ! validate_name "$NAME"; then
            exit 1
        fi

        ensure_groups

        USERNAME=$(name_to_username "$NAME")

        if id "$USERNAME" &>/dev/null; then
            echo "Error: User $USERNAME already exists."
            exit 1
        fi

        # Prompt for tier
        echo "Available tiers: junior, senior, management"
        read -p "Enter tier for $NAME ($USERNAME): " TIER
        TIER=$(echo "$TIER" | tr '[:upper:]' '[:lower:]')

        if [[ -z "${TIERS[$TIER]}" ]]; then
            echo "Error: Invalid tier. Choose from: junior, senior, management"
            exit 1
        fi

        # Create user with home directory and bash shell
        if useradd -m -s /bin/bash "$USERNAME"; then
            log_action "Created user: $USERNAME ($NAME) with tier $TIER"
            echo "User $USERNAME created successfully."
        else
            echo "Error: Failed to create user."
            exit 1
        fi

        # Add user to appropriate groups
        for group in ${TIERS[$TIER]}; do
            usermod -aG "$group" "$USERNAME"
            log_action "Added $USERNAME to group: $group"
        done

        # Generate 4-digit PIN as initial password
        PIN=$(generate_pin)
        echo "$USERNAME:$PIN" | chpasswd

        # Log PIN securely (only owner can access)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] User: $USERNAME ($NAME) | Tier: $TIER | PIN: $PIN" >> "$PIN_LOG_FILE"
        chmod 600 "$PIN_LOG_FILE"

        echo "========================================"
        echo "User created: $USERNAME"
        echo "Initial PIN (password): $PIN"
        echo "This PIN has been logged securely in $PIN_LOG_FILE"
        echo "========================================"
        ;;

    -r)
        NAME="$1"
        if ! validate_name "$NAME"; then
            exit 1
        fi

        USERNAME=$(name_to_username "$NAME")

        if ! id "$USERNAME" &>/dev/null; then
            echo "Error: User $USERNAME does not exist."
            exit 1
        fi

        read -p "Are you sure you want to delete user $USERNAME ($NAME)? (y/n): " CONFIRM
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            echo "Deletion cancelled."
            exit 0
        fi

        if userdel -r "$USERNAME"; then
            log_action "Deleted user: $USERNAME ($NAME)"
            echo "User $USERNAME and home directory removed successfully."
        else
            echo "Error: Failed to delete user."
            exit 1
        fi
        ;;

    -e)
        NAME="$1"
        if ! validate_name "$NAME"; then
            exit 1
        fi

        USERNAME=$(name_to_username "$NAME")

        if ! id "$USERNAME" &>/dev/null; then
            echo "Error: User $USERNAME does not exist."
            exit 1
        fi

        echo "Current groups for $USERNAME:"
        groups "$USERNAME"

        ensure_groups

        echo "Available tiers: junior, senior, management"
        read -p "Enter new tier: " NEW_TIER
        NEW_TIER=$(echo "$NEW_TIER" | tr '[:upper:]' '[:lower:]')

        if [[ -z "${TIERS[$NEW_TIER]}" ]]; then
            echo "Error: Invalid tier."
            exit 1
        fi

        # Remove from all tier groups first
        for group in junior senior management; do
            gpasswd -d "$USERNAME" "$group" 2>/dev/null
        done

        # Add to new tier groups
        for group in ${TIERS[$NEW_TIER]}; do
            usermod -aG "$group" "$USERNAME"
        done

        log_action "Updated tier for $USERNAME ($NAME) to $NEW_TIER"
        echo "User $USERNAME updated to tier: $NEW_TIER"
        echo "New groups:"
        groups "$USERNAME"
        ;;

    *)
        echo "Error: Invalid option. Use -h for help."
        exit 1
        ;;
esac

exit 0
