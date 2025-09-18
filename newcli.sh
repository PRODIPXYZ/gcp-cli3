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

SSH_INFO_FILE="$HOME/.gcp_vm_info"
TERM_KEY_PATH="$HOME/.ssh/termius_vm_key"

# ---------- List Google Accounts ----------
list_google_accounts() {
    accounts=$(gcloud auth list --format="value(account)")
    if [ -z "$accounts" ]; then return 1; fi
    i=1
    echo -e "\n${CYAN}${BOLD}📧 Available Google Accounts${RESET}\n"
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
    list_google_accounts || { echo -e "${RED}❌ No accounts found${RESET}"; return; }
    read -p "Enter account number to logout: " choice
    selected="${accounts_list[$choice]}"
    if [ -n "$selected" ]; then
        gcloud auth revoke "$selected" --quiet
        echo -e "${GREEN}✔ Logged out from $selected${RESET}"
    else
        echo -e "${RED}Invalid choice!${RESET}"
    fi
    read -p "Press Enter..."
}

# ---------- Fresh Install ----------
fresh_install() {
    echo -e "${CYAN}${BOLD}Running Fresh Install...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip python3 python3-pip docker.io
    sudo systemctl enable docker --now
    if ! command -v gcloud &> /dev/null; then
        curl https://sdk.cloud.google.com | bash
        exec -l $SHELL
    fi
    gcloud auth login
    echo -e "${GREEN}✔ Setup complete${RESET}"
    read -p "Press Enter..."
}

# ---------- Create 2 Projects ----------
auto_create_projects_one() {
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    default_project=$(gcloud projects list --filter="lifecycleState:ACTIVE" --format="value(projectId)" | head -n1)
    billing_enabled=$(gcloud beta billing projects describe "$default_project" --format="value(billingEnabled)" 2>/dev/null)
    if [ "$billing_enabled" != "True" ]; then
        gcloud beta billing projects link "$default_project" --billing-account "$billing_id" --quiet
        gcloud services enable compute.googleapis.com --project="$default_project" --quiet
    fi
    for i in 1 2; do
        projid="auto-proj-$RANDOM"
        gcloud projects create "$projid" --name="auto-proj-$i" --quiet
        gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet
        gcloud services enable compute.googleapis.com --project="$projid" --quiet
        echo -e "${GREEN}✔ Project $projid created${RESET}"
    done
}
auto_create_projects_all() {
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" >/dev/null 2>&1
        auto_create_projects_one
    done
}

# ---------- Create 6 VMs ----------
auto_create_vms_one() {
    read -p "Enter your SSH Public Key: " pubkey
    zone="asia-southeast1-b"; mtype="n2d-custom-4-25600"; disksize="60"
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    default_project=$(gcloud projects list --filter="lifecycleState:ACTIVE" --format="value(projectId)" | head -n1)
    billing_enabled=$(gcloud beta billing projects describe "$default_project" --format="value(billingEnabled)" 2>/dev/null)
    if [ "$billing_enabled" != "True" ]; then
        gcloud beta billing projects link "$default_project" --billing-account "$billing_id" --quiet
        gcloud services enable compute.googleapis.com --project="$default_project" --quiet
    fi
    projects="$default_project
$(gcloud beta billing projects list --billing-account=$billing_id --format="value(projectId)" | head -n2)"
    echo -e "${CYAN}Enter 6 VM names:${RESET}"
    vmnames=(); for i in {1..6}; do read -p "VM #$i: " name; vmnames+=("$name"); done
    count=0
    for proj in $projects; do
        gcloud config set project $proj >/dev/null 2>&1
        for j in {1..2}; do
            gcloud compute instances create "${vmnames[$count]}" \
                --zone=$zone --machine-type=$mtype \
                --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
                --boot-disk-size=${disksize}GB --boot-disk-type=pd-balanced \
                --metadata ssh-keys="${vmnames[$count]}:${pubkey}" \
                --tags=http-server,https-server --quiet
            ((count++))
        done
    done
}
auto_create_vms_all() {
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" >/dev/null 2>&1
        auto_create_vms_one
    done
}

# ---------- Show All VMs ----------
show_all_vms() {
    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    printf "${YELLOW}┌─────┬──────────────┬──────────────────────┬───────────────────────────────┬──────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-14s│%-22s│%-31s│%-28s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
    printf "${YELLOW}├─────┼──────────────┼──────────────────────┼───────────────────────────────┼──────────────────────────────┤${RESET}\n"
    i=1
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" >/dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            vms=$(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)" 2>/dev/null)
            if [ -n "$vms" ]; then
                while read -r name ip; do
                    printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-14s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}%-28s${YELLOW}│${RESET}\n" "$i" "$name" "$ip" "$proj" "$acc"
                    ((i++))
                done <<< "$vms"
            fi
        done
    done
    printf "${YELLOW}└─────┴──────────────┴──────────────────────┴───────────────────────────────┴──────────────────────────────┘${RESET}\n"
    read -p "Press Enter..."
}

# ---------- Connect VM ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        read -p "Enter path to Termius private key: " keypath
        cp "$keypath" "$TERM_KEY_PATH"; chmod 600 "$TERM_KEY_PATH"
    fi
    echo -e "\n${CYAN}${BOLD}💻 Connect VM${RESET}\n"
    vm_list=(); index=1
    printf "${YELLOW}┌─────┬──────────────┬──────────────────────┬───────────────────────────────┬──────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-14s│%-22s│%-31s│%-28s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
    printf "${YELLOW}├─────┼──────────────┼──────────────────────┼───────────────────────────────┼──────────────────────────────┤${RESET}\n"
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" >/dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)")
            for vm in "${vms[@]}"; do
                name=$(echo $vm | awk '{print $1}'); ip=$(echo $vm | awk '{print $2}')
                printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-14s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}%-28s${YELLOW}│${RESET}\n" "$index" "$name" "$ip" "$proj" "$acc"
                vm_list+=("$acc|$proj|$name|$ip"); ((index++))
            done
        done
    done
    printf "${YELLOW}└─────┴──────────────┴──────────────────────┴───────────────────────────────┴──────────────────────────────┘${RESET}\n"
    read -p "Enter VM number: " choice
    selected="${vm_list[$((choice-1))]}"
    acc=$(echo "$selected" | cut -d'|' -f1)
    proj=$(echo "$selected" | cut -d'|' -f2)
    name=$(echo "$selected" | cut -d'|' -f3)
    ip=$(echo "$selected" | cut -d'|' -f4)
    gcloud config set account "$acc" >/dev/null 2>&1
    ssh -i "$TERM_KEY_PATH" "$name@$ip"
}

# ---------- Add Extra 2 VMs ----------
add_extra_vms() {
    echo -e "\n${CYAN}${BOLD}➕ Add Extra 2 VMs in Existing Project${RESET}\n"
    projects=(); index=1
    printf "${YELLOW}┌─────┬──────────────────────────────┬───────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-30s│%-15s│${RESET}\n" "No" "PROJECT" "VM Count"
    printf "${YELLOW}├─────┼──────────────────────────────┼───────────────┤${RESET}\n"
    for proj in $(gcloud projects list --format="value(projectId)"); do
        vms=$(gcloud compute instances list --project=$proj --format="value(name)" 2>/dev/null)
        if [ -n "$vms" ]; then
            vmcount=$(echo "$vms" | wc -l)
            printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-30s${YELLOW}│${RESET}%-15s${YELLOW}│${RESET}\n" "$index" "$proj" "$vmcount"
            projects+=("$proj"); ((index++))
        fi
    done
    printf "${YELLOW}└─────┴──────────────────────────────┴───────────────┘${RESET}\n"
    read -p "Choose project: " choice; proj="${projects[$((choice-1))]}"
    echo -e "${CYAN}Enter 2 Extra VM Names:${RESET}"; vmnames=()
    for i in {1..2}; do read -p "VM #$i: " name; vmnames+=("$name"); done
    read -p "Enter your SSH Public Key: " pubkey
    zone="asia-southeast1-b"; mtype="n2d-custom-4-25600"; disksize="60"
    for vmname in "${vmnames[@]}"; do
        gcloud compute instances create $vmname --zone=$zone --machine-type=$mtype \
            --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
            --boot-disk-size=${disksize}GB --boot-disk-type=pd-balanced \
            --metadata ssh-keys="${vmname}:${pubkey}" --tags=http-server,https-server --quiet
    done
    echo -e "${GREEN}✔ Extra 2 VMs created in $proj${RESET}"; read -p "Press Enter..."
}

# ---------- Create 2 VMs in Any Project ----------
create_2_vms_in_project() {
    echo -e "\n${CYAN}${BOLD}➕ Create 2 VMs in Any Project${RESET}\n"
    projects=(); index=1
    printf "${YELLOW}┌─────┬──────────────────────────────┬───────────────┬───────────────────────┬──────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-30s│%-15s│%-23s│%-28s│${RESET}\n" "No" "PROJECT" "VM Count" "Billing" "ACCOUNT"
    printf "${YELLOW}├─────┼──────────────────────────────┼───────────────┼───────────────────────┼──────────────────────────────┤${RESET}\n"
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" >/dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null)
            [ "$billing_enabled" == "True" ] && billing="Enabled" || billing="Disabled"
            vms=$(gcloud compute instances list --project=$proj --format="value(name)" 2>/dev/null)
            [ -n "$vms" ] && vmcount=$(echo "$vms" | wc -l) || vmcount=0
            printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-30s${YELLOW}│${RESET}%-15s${YELLOW}│${RESET}%-23s${YELLOW}│${RESET}%-28s${YELLOW}│${RESET}\n" "$index" "$proj" "$vmcount" "$billing" "$acc"
            projects+=("$acc|$proj|$billing"); ((index++))
        done
    done
    printf "${YELLOW}└─────┴──────────────────────────────┴───────────────┴───────────────────────┴──────────────────────────────┘${RESET}\n"
    read -p "Choose project number: " choice
    selected="${projects[$((choice-1))]}"; acc=$(echo "$selected" | cut -d'|' -f1)
    proj=$(echo "$selected" | cut -d'|' -f2); billing=$(echo "$selected" | cut -d'|' -f3)
    gcloud config set account "$acc" >/dev/null 2>&1
    if [ "$billing" = "Disabled" ]; then
        billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
        gcloud beta billing projects link "$proj" --billing-account "$billing_id" --quiet
        gcloud services enable compute.googleapis.com --project="$proj" --quiet
    fi
    echo -e "${CYAN}Enter 2 VM Names:${RESET}"; vmnames=()
    for i in {1..2}; do read -p "VM #$i: " name; vmnames+=("$name"); done
    read -p "Enter your SSH Public Key: " pubkey
    zone="asia-southeast1-b"; mtype="n2d-custom-4-25600"; disksize="60"
    for vmname in "${vmnames[@]}"; do
        gcloud compute instances create $vmname --zone=$zone --machine-type=$mtype \
            --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
            --boot-disk-size=${disksize}GB --boot-disk-type=pd-balanced \
            --metadata ssh-keys="${vmname}:${pubkey}" --tags=http-server,https-server --quiet
    done
    echo -e "${GREEN}✔ 2 VMs created in $proj ($acc)${RESET}"; read -p "Press Enter..."
}

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|           GCP CLI MENU (ASISH AND PRODIP)         |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Add / Change Google Account (Multi-Login)   |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Create 2 Projects (1=One Acc / 2=All Acc)   |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Create 6 VMs (1=One Acc / 2=All Acc)        |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs                                |"
    echo -e "${YELLOW}${BOLD}| [6] 📜 Show All Projects                           |"
    echo -e "${YELLOW}${BOLD}| [7] 🔗 Connect VM                                  |"
    echo -e "${YELLOW}${BOLD}| [8] ❌ Disconnect VM                               |"
    echo -e "${YELLOW}${BOLD}| [9] 🗑️ Delete ONE VM                               |"
    echo -e "${YELLOW}${BOLD}| [10] 💣 Delete ALL VMs (All Accounts)              |"
    echo -e "${YELLOW}${BOLD}| [11] 💳 Show Billing Accounts                      |"
    echo -e "${YELLOW}${BOLD}| [12] 🚪 Exit                                       |"
    echo -e "${YELLOW}${BOLD}| [13] 🔓 Logout Google Account                      |"
    echo -e "${YELLOW}${BOLD}| [14] ➕ Add Extra 2 VMs in Existing Project        |"
    echo -e "${YELLOW}${BOLD}| [15] ➕ Create 2 VMs in Any Project                |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+${RESET}"
    read -p "Choose: " choice
    case $choice in
        1) fresh_install ;;
        2) gcloud auth login ;;
        3) echo -e "1=One account, 2=All accounts"; read -p "Choose: " sub; [[ "$sub" == "2" ]] && auto_create_projects_all || auto_create_projects_one ;;
        4) echo -e "1=One account, 2=All accounts"; read -p "Choose: " sub; [[ "$sub" == "2" ]] && auto_create_vms_all || auto_create_vms_one ;;
        5) show_all_vms ;;
        6) gcloud projects list --format="table(projectId,name,createTime)" ; read -p "Press Enter..." ;;
        7) connect_vm ;;
        8) [ -f "$SSH_INFO_FILE" ] && rm "$SSH_INFO_FILE" && echo -e "${GREEN}VM disconnected.${RESET}" || echo -e "${YELLOW}No active VM.${RESET}"; read -p "Press Enter..." ;;
        9) gcloud projects list --format="table(projectId,name)" ; read -p "Enter PID: " pid ; gcloud compute instances list --project=$pid --format="table(name,zone,status)" ; read -p "Enter VM: " vm ; zone=$(gcloud compute instances list --project=$pid --filter="name=$vm" --format="value(zone)") ; gcloud compute instances delete $vm --project=$pid --zone=$zone --quiet ;;
        10) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account "$acc" >/dev/null 2>&1 ; for proj in $(gcloud projects list --format="value(projectId)"); do mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)"); for vm in "${vms[@]}"; do zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)") ; gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet; done; done; done ;;
        11) gcloud beta billing accounts list --format="table(displayName,accountId,ACCOUNT_ID,open)" ; read -p "Press Enter..." ;;
        12) exit 0 ;;
        13) logout_google_account ;;
        14) add_extra_vms ;;
        15) create_2_vms_in_project ;;
    esac
done
