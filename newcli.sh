#!/bin/bash

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
MAGENTA="\e[35m"
BLUE="\e[34m"
BOLD='\033[1m'
RESET="\e[0m"

# ---------- Files ----------
SSH_INFO_FILE="$HOME/.gcp_vm_info"
TERM_KEY_PATH="$HOME/.ssh/termius_vm_key"
ACCOUNTS_FILE="$HOME/.gcp_accounts"

# ---------- Fresh Install ----------
fresh_install() {
    echo -e "${CYAN}${BOLD}Running Fresh Install + CLI Setup...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip python3 python3-pip docker.io
    sudo systemctl enable docker --now

    if ! command -v gcloud &> /dev/null; then
        echo -e "${YELLOW}${BOLD}Gcloud CLI not found. Installing...${RESET}"
        curl https://sdk.cloud.google.com | bash
        exec -l $SHELL
    else
        echo -e "${GREEN}${BOLD}Gcloud CLI already installed.${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Now login to your Google Account:${RESET}"
    gcloud auth login
    echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Change Google Account (Multi-Login) ----------
change_google_account() {
    echo -e "${YELLOW}${BOLD}Logging into a new Google Account...${RESET}"
    gcloud auth login --brief
    email=$(gcloud config list account --format "value(core.account)")
    configname="acc-${email//[^a-zA-Z0-9]/_}"
    gcloud config configurations create "$configname" --activate --quiet 2>/dev/null || gcloud config configurations activate "$configname" --quiet
    echo "$configname" >> "$ACCOUNTS_FILE"
    echo -e "${GREEN}${BOLD}Google Account $email saved as config $configname!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Auto Project + Billing (2 Projects) ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating 2 Projects + Linking Billing...${RESET}"

    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    if [ -z "$billing_id" ]; then
        billing_id=$(gcloud beta billing accounts list --format="value(accountId)" | head -n1)
    fi

    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}❌ No Billing Account Detected!${RESET}"
        read -p "Enter Billing Account ID manually: " billing_id
    fi
    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}❌ No billing ID provided. Cancelling.${RESET}"
        read -p "Press Enter..."
        return
    fi

    for i in 1 2; do
        projid="auto-proj-$RANDOM"
        projname="auto-proj-$i"
        echo -e "${CYAN}${BOLD}➡️ Creating Project: $projid ($projname)${RESET}"

        if ! gcloud projects create "$projid" --name="$projname" --quiet; then
            echo -e "${RED}❌ Failed to create project $projid${RESET}"
            continue
        fi

        echo -e "${GREEN}${BOLD}Linking Billing Account...${RESET}"
        gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet

        echo -e "${YELLOW}Enabling Compute Engine API...${RESET}"
        gcloud services enable compute.googleapis.com --project="$projid" --quiet

        echo -e "${GREEN}${BOLD}✅ Project $projid ready.${RESET}"
    done

    echo -e "${GREEN}${BOLD}✅ Finished creating 2 projects.${RESET}"
    read -p "Press Enter..."
}

# ---------- Show All VMs (All Accounts) ----------
show_all_vms() {
    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│${RESET}\n" "No" "USERNAME" "IP" "PROJECT"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┤${RESET}\n"

    i=1
    while read -r conf; do
        [ -z "$conf" ] && continue
        gcloud config configurations activate "$conf" --quiet >/dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            vms=$(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)")
            if [ -n "$vms" ]; then
                while read -r name ip; do
                    printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-16s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}\n" "$i" "$name" "$ip" "$proj"
                    ((i++))
                done <<< "$vms"
            fi
        done
    done < "$ACCOUNTS_FILE"

    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┘${RESET}\n"
    echo -e "${GREEN}✅ Finished listing all VMs${RESET}"
    read -p "Press Enter..."
}

# ---------- Connect VM (All Accounts) ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
    fi

    vm_list=()
    index=1
    while read -r conf; do
        [ -z "$conf" ] && continue
        gcloud config configurations activate "$conf" --quiet >/dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,zone,EXTERNAL_IP)")
            for vm in "${vms[@]}"; do
                name=$(echo $vm | awk '{print $1}')
                zone=$(echo $vm | awk '{print $2}')
                ip=$(echo $vm | awk '{print $3}')
                if [ -n "$name" ] && [ -n "$ip" ]; then
                    echo -e "[${index}] $name | $ip | $proj | $zone"
                    vm_list+=("$conf|$proj|$name|$zone|$ip")
                    ((index++))
                fi
            done
        done
    done < "$ACCOUNTS_FILE"

    if [ ${#vm_list[@]} -eq 0 ]; then
        echo -e "${RED}❌ No VMs found!${RESET}"
        read -p "Press Enter..."
        return
    fi

    read -p "Enter VM number: " choice
    selected="${vm_list[$((choice-1))]}"
    conf=$(echo "$selected" | cut -d'|' -f1)
    proj=$(echo "$selected" | cut -d'|' -f2)
    vmname=$(echo "$selected" | cut -d'|' -f3)
    zone=$(echo "$selected" | cut -d'|' -f4)
    ip=$(echo "$selected" | cut -d'|' -f5)

    gcloud config configurations activate "$conf" --quiet >/dev/null 2>&1
    echo -e "${GREEN}${BOLD}Connecting to $vmname@$ip in $proj [$zone]...${RESET}"
    ssh -i "$TERM_KEY_PATH" "$vmname@$ip"
}

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|           GCP CLI MENU (ASISH AND PRODIP)         |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Add / Login Google Account (Multi)          |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Auto Create 2 Projects + Auto Billing       |"
    echo -e "${YELLOW}${BOLD}| [4] 🌍 Show All VMs (All Accounts)                 |"
    echo -e "${YELLOW}${BOLD}| [5] 🔗 Connect VM (All Accounts)                   |"
    echo -e "${YELLOW}${BOLD}| [6] 🚪 Exit                                       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose [1-6]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects ;;
        4) show_all_vms ;;
        5) connect_vm ;;
        6) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter..." ;;
    esac
done
