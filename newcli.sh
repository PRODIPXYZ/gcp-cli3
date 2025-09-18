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

# ---------- Add/Login Google Account (Multi) ----------
add_google_account() {
    echo -e "${YELLOW}${BOLD}Logging into a new Google Account...${RESET}"
    email=$(gcloud auth login --brief --quiet 2>&1 | grep -oP "Logged in as \K\S+")
    if [ -z "$email" ]; then
        echo -e "${RED}❌ Failed to login!${RESET}"
    else
        safe_name=$(echo "$email" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')
        gcloud config configurations create "$safe_name" --no-activate &>/dev/null
        gcloud config configurations activate "$safe_name"
        gcloud auth login "$email"
        echo -e "${GREEN}Google Account $email saved as config $safe_name!${RESET}"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Remove/Logout Google Account ----------
remove_google_account() {
    echo -e "${YELLOW}${BOLD}Available Accounts:${RESET}"
    gcloud auth list
    read -p "Enter email to remove: " rem
    gcloud auth revoke "$rem"
    echo -e "${GREEN}Account $rem removed successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Auto Project + Billing (2 New Per Account) ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating 2 Projects + Linking Billing (per account)...${RESET}"

    for conf in $(gcloud config configurations list --format="value(name)"); do
        gcloud config configurations activate "$conf" &>/dev/null
        echo -e "\n${CYAN}${BOLD}➡️ Using Account Config: $conf${RESET}"

        billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
        [ -z "$billing_id" ] && billing_id=$(gcloud beta billing accounts list --format="value(accountId)" | head -n1)

        if [ -z "$billing_id" ]; then
            echo -e "${RED}❌ No billing account found for $conf! Skipping...${RESET}"
            continue
        fi

        for i in 1 2; do
            projid="auto-proj-$RANDOM"
            projname="auto-proj-$i"
            echo -e "${CYAN}Creating Project: $projid ($projname)${RESET}"

            if gcloud projects create "$projid" --name="$projname" --quiet; then
                gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet
                gcloud services enable compute.googleapis.com --project="$projid" --quiet
                echo -e "${GREEN}✅ Project $projid ready with billing & API enabled.${RESET}"
            else
                echo -e "${RED}❌ Failed to create project $projid${RESET}"
            fi
        done
    done
    read -p "Press Enter to continue..."
}

# ---------- Auto VM Create Menu ----------
auto_create_vms() {
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|           AUTO CREATE VM MENU (PRODIP)            |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] Create VMs for ONE Account                    |"
    echo -e "${YELLOW}${BOLD}| [2] Create VMs for ALL Accounts                   |"
    echo -e "${YELLOW}${BOLD}| [3] Back to Main Menu                             |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+${RESET}"
    echo
    read -p "Choose [1-3]: " subchoice

    case $subchoice in
        1) auto_create_vms_one ;;
        2) auto_create_vms_all ;;
        3) return ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; sleep 2 ;;
    esac
}

# ---------- Common VM Create Logic ----------
vm_create_logic() {
    echo -e "${YELLOW}${BOLD}Enter your SSH Public Key (without username:, only key part):${RESET}"
    read pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    echo -e "${CYAN}${BOLD}Enter 6 VM Names (project-wise 2 each)...${RESET}"
    vmnames=()
    for i in {1..6}; do
        read -p "Enter VM Name #$i: " name
        vmnames+=("$name")
    done

    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    projects=$(gcloud beta billing projects list --billing-account="$billing_id" --format="value(projectId)" | head -n 3)

    count=0
    for proj in $projects; do
        gcloud config set project $proj &>/dev/null
        gcloud services enable compute.googleapis.com --project="$proj" --quiet
        for j in {1..2}; do
            vmname="${vmnames[$count]}"
            echo -e "${GREEN}Creating VM $vmname in $proj...${RESET}"
            gcloud compute instances create "$vmname" \
                --zone=$zone \
                --machine-type=$mtype \
                --image-family=ubuntu-2404-lts-amd64 \
                --image-project=ubuntu-os-cloud \
                --boot-disk-size=${disksize}GB \
                --boot-disk-type=pd-balanced \
                --metadata=ssh-keys="ubuntu:${pubkey}" \
                --tags=http-server,https-server \
                --quiet
            ((count++))
        done
    done
}

# ---------- One Account ----------
auto_create_vms_one() {
    echo -e "${CYAN}${BOLD}Available Accounts:${RESET}\n"
    printf "${YELLOW}┌─────┬───────────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-35s${YELLOW}│${RESET}\n" "No" "CONFIG NAME"
    printf "${YELLOW}├─────┼───────────────────────────────────┤${RESET}\n"

    acc_list=()
    index=1
    for conf in $(gcloud config configurations list --format="value(name)"); do
        printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-35s${YELLOW}│${RESET}\n" "$index" "$conf"
        acc_list+=("$conf")
        ((index++))
    done
    printf "${YELLOW}└─────┴───────────────────────────────────┘${RESET}\n"

    read -p "Enter account number: " acc_no
    conf="${acc_list[$((acc_no-1))]}"
    gcloud config configurations activate "$conf" &>/dev/null

    echo -e "${GREEN}➡️ Selected Account Config: $conf${RESET}"
    vm_create_logic
    echo -e "${GREEN}${BOLD}✅ VMs Created for ONE Account!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- All Accounts ----------
auto_create_vms_all() {
    for conf in $(gcloud config configurations list --format="value(name)"); do
        gcloud config configurations activate "$conf" &>/dev/null
        echo -e "\n${CYAN}${BOLD}➡️ Creating VMs for Account Config: $conf${RESET}"
        vm_create_logic
    done
    echo -e "${GREEN}${BOLD}✅ All VMs Created Successfully Across Accounts!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Show All VMs (Box Style) ----------
show_all_vms() {
    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬──────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│%-14s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ZONE"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼──────────────┤${RESET}\n"

    i=1
    for conf in $(gcloud config configurations list --format="value(name)"); do
        gcloud config configurations activate "$conf" &>/dev/null
        for proj in $(gcloud projects list --format="value(projectId)"); do
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP,zone)")
            for vm in "${vms[@]}"; do
                name=$(echo $vm | awk '{print $1}')
                ip=$(echo $vm | awk '{print $2}')
                zone=$(echo $vm | awk '{print $3}')
                [ -n "$name" ] && [ -n "$ip" ] && printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-16s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}%-14s${YELLOW}│${RESET}\n" "$i" "$name" "$ip" "$proj" "$zone"
                ((i++))
            done
        done
    done
    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┴──────────────┘${RESET}\n"
    read -p "Press Enter to continue..."
}

# ---------- Connect VM ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
    fi

    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    vm_list=()
    index=1

    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬──────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│%-14s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ZONE"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼──────────────┤${RESET}\n"

    for conf in $(gcloud config configurations list --format="value(name)"); do
        gcloud config configurations activate "$conf" &>/dev/null
        for proj in $(gcloud projects list --format="value(projectId)"); do
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP,zone)")
            for vm in "${vms[@]}"; do
                name=$(echo $vm | awk '{print $1}')
                ip=$(echo $vm | awk '{print $2}')
                zone=$(echo $vm | awk '{print $3}')
                if [ -n "$name" ] && [ -n "$ip" ]; then
                    printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-16s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}%-14s${YELLOW}│${RESET}\n" "$index" "$name" "$ip" "$proj" "$zone"
                    vm_list+=("$proj|$name|$zone|$ip")
                    ((index++))
                fi
            done
        done
    done

    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┴──────────────┘${RESET}\n"
    read -p "Enter VM number to connect: " choice
    selected="${vm_list[$((choice-1))]}"
    proj=$(echo "$selected" | cut -d'|' -f1)
    vmname=$(echo "$selected" | cut -d'|' -f2)
    zone=$(echo "$selected" | cut -d'|' -f3)
    ip=$(echo "$selected" | cut -d'|' -f4)

    ssh -i "$TERM_KEY_PATH" "ubuntu@$ip"
    read -p "Press Enter to continue..."
}

# ---------- Delete One VM ----------
delete_one_vm() {
    gcloud projects list --format="table(projectId,name)"
    read -p "Enter Project ID: " projid
    gcloud compute instances list --project=$projid --format="table(name,zone,status)"
    read -p "Enter VM Name to delete: " vmname
    zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)")
    gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet
    echo -e "${GREEN}VM $vmname deleted successfully.${RESET}"
    read -p "Press Enter..."
}

# ---------- Delete All VMs ----------
delete_all_vms() {
    read -p "Are you sure to delete ALL VMs? (y/n): " ans
    [[ "$ans" != "y" ]] && return
    for proj in $(gcloud projects list --format="value(projectId)"); do
        mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)")
        for vm in "${vms[@]}"; do
            zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)")
            gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet
            echo -e "${GREEN}Deleted $vm from $proj${RESET}"
        done
    done
    read -p "Press Enter..."
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
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Auto Create VMs Menu                        |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs (All Accounts)                 |"
    echo -e "${YELLOW}${BOLD}| [6] 🔗 Connect VM (All Accounts)                   |"
    echo -e "${YELLOW}${BOLD}| [7] 🗑️ Delete ONE VM                               |"
    echo -e "${YELLOW}${BOLD}| [8] 💣 Delete ALL VMs                              |"
    echo -e "${YELLOW}${BOLD}| [9] ❌ Remove / Logout Google Account              |"
    echo -e "${YELLOW}${BOLD}| [10] 🚪 Exit                                       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose [1-10]: " choice

    case $choice in
        1) fresh_install ;;
        2) add_google_account ;;
        3) auto_create_projects ;;
        4) auto_create_vms ;;
        5) show_all_vms ;;
        6) connect_vm ;;
        7) delete_one_vm ;;
        8) delete_all_vms ;;
        9) remove_google_account ;;
        10) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter..." ;;
    esac
done
