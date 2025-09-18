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

# ---------- List Google Accounts ----------
list_google_accounts() {
    accounts=$(gcloud auth list --format="value(account)")
    if [ -z "$accounts" ]; then
        echo -e "${RED}❌ No Google accounts found. Please login first.${RESET}"
        return 1
    fi
    i=1
    printf "${YELLOW}┌─────┬──────────────────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-42s│${RESET}\n" "No" "Account Email"
    printf "${YELLOW}├─────┼──────────────────────────────────────────┤${RESET}\n"
    while read -r acc; do
        printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-42s${YELLOW}│${RESET}\n" "$i" "$acc"
        accounts_list[$i]="$acc"
        ((i++))
    done <<< "$accounts"
    printf "${YELLOW}└─────┴──────────────────────────────────────────┘${RESET}\n"
    return 0
}

# ---------- Logout Google Account ----------
logout_google_account() {
    list_google_accounts || return 1
    read -p "Enter account number to logout: " choice
    selected="${accounts_list[$choice]}"
    if [ -z "$selected" ]; then
        echo -e "${RED}Invalid choice!${RESET}"
        return 1
    fi
    gcloud auth revoke "$selected" --quiet
    echo -e "${GREEN}✔ Logged out from $selected${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Fresh Install ----------
fresh_install() {
    echo -e "${CYAN}${BOLD}Running Fresh Install + CLI Setup...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip python3 python3-pip docker.io
    sudo systemctl enable docker --now

    if ! command -v gcloud &> /dev/null; then
        curl https://sdk.cloud.google.com | bash
        exec -l $SHELL
    fi

    gcloud auth login
    echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Change / Add Google Account ----------
change_google_account() {
    gcloud auth login
    echo -e "${GREEN}${BOLD}✔ Account added successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Project Create (One Account) ----------
create_project_one_account() {
    list_google_accounts || return 1
    read -p "Choose account number: " choice
    acc="${accounts_list[$choice]}"
    if [ -z "$acc" ]; then
        echo -e "${RED}Invalid choice!${RESET}"
        return 1
    fi
    gcloud config set account "$acc" >/dev/null 2>&1
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)

    for i in 1 2; do
        projid="auto-proj-$RANDOM"
        gcloud projects create "$projid" --name="auto-proj-$i" --quiet || continue
        gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet || continue
        gcloud services enable compute.googleapis.com --project="$projid" --quiet
        echo -e "${GREEN}✔ Project $projid ready in $acc.${RESET}"
    done
    read -p "Press Enter to continue..."
}

# ---------- Project Create (All Accounts) ----------
create_project_all_accounts() {
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" >/dev/null 2>&1
        for i in 1 2; do
            projid="auto-proj-$RANDOM"
            gcloud projects create "$projid" --name="auto-proj-$i" --quiet || continue
            gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet || continue
            gcloud services enable compute.googleapis.com --project="$projid" --quiet
            echo -e "${GREEN}✔ Project $projid ready in $acc.${RESET}"
        done
    done
    read -p "Press Enter to continue..."
}

# ---------- VM Create (One Account) ----------
create_vm_one_account() {
    list_google_accounts || return 1
    read -p "Choose account number: " choice
    acc="${accounts_list[$choice]}"
    if [ -z "$acc" ]; then
        echo -e "${RED}Invalid choice!${RESET}"
        return 1
    fi
    gcloud config set account "$acc" >/dev/null 2>&1

    echo -e "${YELLOW}Enter your SSH Public Key (only key part):${RESET}"
    read pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    echo -e "${CYAN}${BOLD}Enter 6 VM Names:${RESET}"
    vmnames=()
    for i in {1..6}; do
        read -p "VM #$i: " name
        vmnames+=("$name")
    done

    count=0
    for proj in $(gcloud projects list --format="value(projectId)" | head -n3); do
        gcloud config set project $proj >/dev/null 2>&1
        for j in {1..2}; do
            vmname="${vmnames[$count]}"
            gcloud compute instances create $vmname \
                --zone=$zone --machine-type=$mtype \
                --image-family=ubuntu-2404-lts-amd64 \
                --image-project=ubuntu-os-cloud \
                --boot-disk-size=${disksize}GB \
                --boot-disk-type=pd-balanced \
                --metadata ssh-keys="${vmname}:${pubkey}" \
                --tags=http-server,https-server --quiet
            ((count++))
        done
    done
    echo -e "${GREEN}✔ All 6 VMs created in $acc.${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- VM Create (All Accounts) ----------
create_vm_all_accounts() {
    echo -e "${YELLOW}Enter your SSH Public Key (only key part):${RESET}"
    read pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" >/dev/null 2>&1
        echo -e "${CYAN}${BOLD}Account: $acc${RESET}"
        echo -e "${CYAN}${BOLD}Enter 6 VM Names for this account:${RESET}"
        vmnames=()
        for i in {1..6}; do
            read -p "VM #$i: " name
            vmnames+=("$name")
        done

        count=0
        for proj in $(gcloud projects list --format="value(projectId)" | head -n3); do
            gcloud config set project $proj >/dev/null 2>&1
            for j in {1..2}; do
                vmname="${vmnames[$count]}"
                gcloud compute instances create $vmname \
                    --zone=$zone --machine-type=$mtype \
                    --image-family=ubuntu-2404-lts-amd64 \
                    --image-project=ubuntu-os-cloud \
                    --boot-disk-size=${disksize}GB \
                    --boot-disk-type=pd-balanced \
                    --metadata ssh-keys="${vmname}:${pubkey}" \
                    --tags=http-server,https-server --quiet
                ((count++))
            done
        done
        echo -e "${GREEN}✔ All 6 VMs created in $acc.${RESET}"
    done
    read -p "Press Enter to continue..."
}

# ---------- আপনার আগের show_all_vms, connect_vm, add_extra_vms, create_2_vms_in_project 그대로 রাখবেন ----------

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|           GCP CLI MENU (ASISH AND PRODIP)         |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] Fresh Install + CLI Setup                     |"
    echo -e "${YELLOW}${BOLD}| [2] Add / Change Google Account                   |"
    echo -e "${YELLOW}${BOLD}| [3] Create Projects                               |"
    echo -e "${YELLOW}${BOLD}|      [1] One Account                              |"
    echo -e "${YELLOW}${BOLD}|      [2] All Accounts                             |"
    echo -e "${YELLOW}${BOLD}| [4] Create VMs                                    |"
    echo -e "${YELLOW}${BOLD}|      [1] One Account                              |"
    echo -e "${YELLOW}${BOLD}|      [2] All Accounts                             |"
    echo -e "${YELLOW}${BOLD}| [5] Show All VMs                                  |"
    echo -e "${YELLOW}${BOLD}| [6] Show All Projects                             |"
    echo -e "${YELLOW}${BOLD}| [7] Connect VM                                    |"
    echo -e "${YELLOW}${BOLD}| [8] Disconnect VM                                 |"
    echo -e "${YELLOW}${BOLD}| [9] Delete ONE VM                                 |"
    echo -e "${YELLOW}${BOLD}| [10] Delete ALL VMs                               |"
    echo -e "${YELLOW}${BOLD}| [11] Show Billing Accounts                        |"
    echo -e "${YELLOW}${BOLD}| [12] Exit                                         |"
    echo -e "${YELLOW}${BOLD}| [13] Logout Google Account                        |"
    echo -e "${YELLOW}${BOLD}| [14] Add Extra 2 VMs in Existing Project          |"
    echo -e "${YELLOW}${BOLD}| [15] Create 2 VMs in Any Project                  |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-15]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) echo "1) One Account"; echo "2) All Accounts"; read -p "Choose: " sub; [ "$sub" = "1" ] && create_project_one_account || create_project_all_accounts ;;
        4) echo "1) One Account"; echo "2) All Accounts"; read -p "Choose: " sub; [ "$sub" = "1" ] && create_vm_one_account || create_vm_all_accounts ;;
        5) show_all_vms ;;
        6) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account "$acc" >/dev/null 2>&1; echo "Account: $acc"; gcloud projects list --format="table(projectId,name,createTime)"; done; read -p "Press Enter..." ;;
        7) connect_vm ;;
        8) if [ -f "$SSH_INFO_FILE" ]; then rm "$SSH_INFO_FILE"; echo "VM disconnected."; else echo "No active VM."; fi; read -p "Press Enter..." ;;
        9) gcloud projects list --format="table(projectId,name)" ; read -p "Enter PID: " projid ; gcloud compute instances list --project=$projid --format="table(name,zone,status)" ; read -p "Enter VM: " vmname ; zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)") ; gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet ;;
        10) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account "$acc" >/dev/null 2>&1 ; for proj in $(gcloud projects list --format="value(projectId)"); do mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)" 2>/dev/null); for vm in "${vms[@]}"; do zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)" 2>/dev/null); gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet; done; done; done ;;
        11) gcloud beta billing accounts list --format="table(displayName,accountId,ACCOUNT_ID,open)" ; read -p "Press Enter..." ;;
        12) exit 0 ;;
        13) logout_google_account ;;
        14) add_extra_vms ;;
        15) create_2_vms_in_project ;;
        *) echo "Invalid choice"; read -p "Press Enter..." ;;
    esac
done
