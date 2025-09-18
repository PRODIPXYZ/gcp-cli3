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
    echo -e "\n${CYAN}${BOLD}📧 Available Google Accounts${RESET}\n"
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

# ---------- Select Google Account ----------
select_google_account() {
    list_google_accounts || return 1
    read -p "Enter account number: " choice
    selected="${accounts_list[$choice]}"
    if [ -z "$selected" ]; then
        echo -e "${RED}Invalid choice!${RESET}"
        return 1
    fi
    echo -e "${GREEN}✔ Selected account: $selected${RESET}"
    gcloud config set account "$selected" > /dev/null 2>&1
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

# ---------- Change / Add Google Account ----------
change_google_account() {
    echo -e "${YELLOW}${BOLD}Login to a new Google Account...${RESET}"
    gcloud auth login
    echo -e "${GREEN}${BOLD}✔ Account added successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Auto Create Projects Menu ----------
auto_create_projects_menu() {
    echo -e "\n${CYAN}${BOLD}📁 Create Projects Menu${RESET}"
    echo -e "${YELLOW}1) Create Project in ONE Account${RESET}"
    echo -e "${YELLOW}2) Create Project in ALL Accounts${RESET}"
    read -p "Choose option: " subchoice
    case $subchoice in
        1) select_google_account && auto_create_projects ;;
        2) for acc in $(gcloud auth list --format="value(account)"); do
               gcloud config set account "$acc" > /dev/null 2>&1
               auto_create_projects
           done ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ;;
    esac
}

# ---------- Auto Create Projects (2 Only) ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating 2 Projects + Linking Billing...${RESET}"

    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}❌ No Billing Account Found.${RESET}"
        return
    fi

    for i in 1 2; do
        projid="auto-proj-$RANDOM"
        projname="auto-proj-$i"
        echo -e "${CYAN}➡️ Creating Project: $projid ($projname)${RESET}"
        gcloud projects create "$projid" --name="$projname" --quiet || continue
        gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet || continue
        gcloud services enable compute.googleapis.com --project="$projid" --quiet
        echo -e "${GREEN}✔ Project $projid ready.${RESET}"
    done

    read -p "Press Enter to continue..."
}

# ---------- Auto Create VM Menu ----------
auto_create_vms_menu() {
    echo -e "\n${CYAN}${BOLD}🚀 Create VM Menu${RESET}"
    echo -e "${YELLOW}1) Create VM in ONE Account${RESET}"
    echo -e "${YELLOW}2) Create VM in ALL Accounts${RESET}"
    read -p "Choose option: " subchoice
    case $subchoice in
        1) select_google_account && auto_create_vms ;;
        2) for acc in $(gcloud auth list --format="value(account)"); do
               gcloud config set account "$acc" > /dev/null 2>&1
               auto_create_vms
           done ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ;;
    esac
}

# ---------- Auto VM Create (6 total per account) ----------
auto_create_vms() {
    echo -e "${YELLOW}Enter your SSH Public Key (only key part):${RESET}"
    read pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    projects=$(gcloud projects list --format="value(projectId)" | head -n 3)
    if [ -z "$projects" ]; then
        echo -e "${RED}No projects found!${RESET}"
        return
    fi

    echo -e "${CYAN}${BOLD}Enter 6 VM Names:${RESET}"
    vmnames=()
    for i in {1..6}; do
        read -p "VM #$i: " name
        vmnames+=("$name")
    done

    count=0
    for proj in $projects; do
        gcloud config set project $proj > /dev/null 2>&1
        for j in {1..2}; do
            vmname="${vmnames[$count]}"
            echo -e "${GREEN}Creating VM $vmname in $proj...${RESET}"
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
    echo -e "${GREEN}✔ All VMs Created Successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Show All VMs (ALL Accounts, Box Style) ----------
show_all_vms() {
    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│%-31s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼───────────────────────────────┤${RESET}\n"

    i=1
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" > /dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            vms=$(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)")
            if [ -n "$vms" ]; then
                while read -r name ip; do
                    printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-16s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}\n" "$i" "$name" "$ip" "$proj" "$acc"
                    ((i++))
                done <<< "$vms"
            fi
        done
    done

    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┴───────────────────────────────┘${RESET}\n"
    read -p "Press Enter to continue..."
}

# ---------- Connect VM (ALL Accounts, Box Style, No Zone) ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key to use for VM connections:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
        echo -e "${GREEN}Termius key saved at $TERM_KEY_PATH${RESET}"
    fi

    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    vm_list=()
    index=1

    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│%-31s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼───────────────────────────────┤${RESET}\n"

    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" > /dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)")
            for vm in "${vms[@]}"; do
                name=$(echo $vm | awk '{print $1}')
                ip=$(echo $vm | awk '{print $2}')
                if [ -n "$name" ] && [ -n "$ip" ]; then
                    printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-16s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}\n" "$index" "$name" "$ip" "$proj" "$acc"
                    vm_list+=("$acc|$proj|$name|$ip")
                    ((index++))
                fi
            done
        done
    done

    if [ ${#vm_list[@]} -eq 0 ]; then
        echo -e "${RED}❌ No VMs found across accounts!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┴───────────────────────────────┘${RESET}\n"
    read -p "Enter VM number to connect: " choice

    selected="${vm_list[$((choice-1))]}"
    acc=$(echo "$selected" | cut -d'|' -f1)
    proj=$(echo "$selected" | cut -d'|' -f2)
    vmname=$(echo "$selected" | cut -d'|' -f3)
    ip=$(echo "$selected" | cut -d'|' -f4)

    echo -e "${GREEN}${BOLD}Connecting to $vmname ($ip) in project $proj [Account: $acc]...${RESET}"
    ssh -i "$TERM_KEY_PATH" "$vmname@$ip"
    read -p "Press Enter to continue..."
}

# ---------- Disconnect VM ----------
disconnect_vm() {
    if [ -f "$SSH_INFO_FILE" ]; then
        rm "$SSH_INFO_FILE"
        echo -e "${GREEN}VM disconnected and SSH info cleared.${RESET}"
    else
        echo -e "${YELLOW}No active VM session found.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Show Billing Accounts ----------
show_billing_accounts() {
    echo -e "${YELLOW}${BOLD}Available Billing Accounts:${RESET}"
    gcloud beta billing accounts list --format="table(displayName,accountId,ACCOUNT_ID,open)"
    read -p "Press Enter to continue..."
}

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|           GCP CLI MENU (ASISH AND PRODIP)         |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Add / Change Google Account (Multi-Login)   |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Create Project (One/All Accounts, 2 Only)   |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Create VM (One/All Accounts)                |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs Across Projects (All Accounts) |"
    echo -e "${YELLOW}${BOLD}| [6] 📜 Show All Projects (All Accounts)            |"
    echo -e "${YELLOW}${BOLD}| [7] 🔗 Connect VM (All Accounts, Box Style)        |"
    echo -e "${YELLOW}${BOLD}| [8] ❌ Disconnect VM                               |"
    echo -e "${YELLOW}${BOLD}| [9] 🗑️ Delete ONE VM                               |"
    echo -e "${YELLOW}${BOLD}| [10] 💣 Delete ALL VMs (ALL Projects)              |"
    echo -e "${YELLOW}${BOLD}| [11] 💳 Show Billing Accounts                      |"
    echo -e "${YELLOW}${BOLD}| [12] 🚪 Exit                                       |"
    echo -e "${YELLOW}${BOLD}| [13] 🔓 Logout Google Account                      |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-13]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects_menu ;;
        4) auto_create_vms_menu ;;
        5) show_all_vms ;;
        6) for acc in $(gcloud auth list --format="value(account)"); do
               gcloud config set account "$acc" > /dev/null 2>&1
               echo -e "${CYAN}${BOLD}Account: $acc${RESET}"
               gcloud projects list --format="table(projectId,name,createTime)"
           done ; read -p "Press Enter..." ;;
        7) connect_vm ;;
        8) disconnect_vm ;;
        9) gcloud projects list --format="table(projectId,name)" ; read -p "Enter PID: " projid ; gcloud compute instances list --project=$projid --format="table(name,zone,status)" ; read -p "Enter VM: " vmname ; zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)") ; gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet ;;
        10) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account "$acc" > /dev/null 2>&1 ; for proj in $(gcloud projects list --format="value(projectId)"); do mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)"); for vm in "${vms[@]}"; do zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)"); gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet; done; done; done ;;
        11) show_billing_accounts ;;
        12) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        13) logout_google_account ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter..." ;;
    esac
done
