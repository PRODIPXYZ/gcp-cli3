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

# ---------- Change Google Account ----------
change_google_account() {
    echo -e "${YELLOW}${BOLD}Logging into a new Google Account...${RESET}"
    gcloud auth login
    echo -e "${GREEN}${BOLD}Google Account changed successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Auto Project + Billing (3 Projects) ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating 3 Projects + Linking Billing...${RESET}"

    echo -e "${CYAN}${BOLD}Fetching Billing Accounts...${RESET}"
    gcloud beta billing accounts list

    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    if [ -z "$billing_id" ]; then
        billing_id=$(gcloud beta billing accounts list --format="value(accountId)" | head -n1)
    fi

    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}❌ No Billing Account Detected!${RESET}"
        read -p "Enter Billing Account ID manually: " billing_id
    fi

    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}❌ No billing ID provided. Cancelling project creation.${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    for i in 1 2 3; do
        projid="auto-proj-$RANDOM"
        projname="auto-proj-$i"
        echo -e "${CYAN}${BOLD}➡️ Creating Project: $projid ($projname)${RESET}"

        if ! gcloud projects create "$projid" --name="$projname" --quiet; then
            echo -e "${RED}❌ Failed to create project $projid${RESET}"
            continue
        fi

        echo -e "${GREEN}${BOLD}Linking Billing Account $billing_id...${RESET}"
        if ! gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet; then
            echo -e "${RED}❌ Failed to link billing for $projid${RESET}"
            continue
        fi

        echo -e "${YELLOW}Enabling Compute Engine API for $projid...${RESET}"
        gcloud services enable compute.googleapis.com --project="$projid" --quiet

        echo -e "${GREEN}${BOLD}✅ Project $projid ready with billing & API enabled.${RESET}"
        echo "--------------------------------------------------"
    done

    echo -e "${GREEN}${BOLD}✅ Finished creating 3 projects.${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Show Billing Accounts ----------
show_billing_accounts() {
    echo -e "${YELLOW}${BOLD}Available Billing Accounts:${RESET}"
    gcloud beta billing accounts list --format="table(displayName,accountId,ACCOUNT_ID,open)"
    read -p "Press Enter to continue..."
}

# ---------- Auto VM Create (Only Billing Linked Projects) ----------
auto_create_vms() {
    echo -e "${YELLOW}${BOLD}Enter your SSH Public Key (without username:, only key part):${RESET}"
    read pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    if [ -z "$billing_id" ]; then
        billing_id=$(gcloud beta billing accounts list --format="value(accountId)" | head -n1)
    fi

    projects=$(gcloud beta billing projects list --billing-account="$billing_id" --format="value(projectId)" | head -n 3)

    if [ -z "$projects" ]; then
        echo -e "${RED}${BOLD}No billing-linked projects found!${RESET}"
        return
    fi

    echo -e "${CYAN}${BOLD}Using Billing-Linked Projects:${RESET}"
    echo "$projects"

    echo -e "${CYAN}${BOLD}Enter 6 VM Names (these will also be SSH usernames)...${RESET}"
    vmnames=()
    for i in {1..6}; do
        read -p "Enter VM Name #$i: " name
        vmnames+=("$name")
    done

    count=0
    for proj in $projects; do
        gcloud config set project $proj > /dev/null 2>&1
        echo -e "${CYAN}${BOLD}Switched to Project: $proj${RESET}"

        echo -e "${YELLOW}Ensuring Compute Engine API enabled for $proj...${RESET}"
        gcloud services enable compute.googleapis.com --project="$proj" --quiet

        for j in {1..2}; do
            vmname="${vmnames[$count]}"
            echo -e "${GREEN}${BOLD}Creating VM $vmname in $proj...${RESET}"
            gcloud compute instances create $vmname \
                --zone=$zone \
                --machine-type=$mtype \
                --image-family=ubuntu-2404-lts-amd64 \
                --image-project=ubuntu-os-cloud \
                --boot-disk-size=${disksize}GB \
                --boot-disk-type=pd-balanced \
                --metadata ssh-keys="${vmname}:${pubkey}" \
                --tags=http-server,https-server \
                --quiet
            ((count++))
        done
    done

    echo -e "${GREEN}${BOLD}✅ All 6 VMs Created Successfully Across Billing-Linked Projects!${RESET}"
    echo
    show_all_vms
}

# ---------- Show All VMs (Premium Box Style) ----------
show_all_vms() {
    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    echo -e "${YELLOW}=============================================${RESET}"
    echo -e "   🌐 ${BOLD}Listing ALL VMs Across Projects${RESET}"
    echo -e "${YELLOW}=============================================${RESET}\n"

    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│${RESET}\n" "S.No" "USERNAME" "IP" "PROJECT"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┤${RESET}\n"

    i=1
    for proj in $(gcloud projects list --format="value(projectId)"); do
        vms=$(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)")
        if [ -n "$vms" ]; then
            while read -r name ip; do
                printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-16s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}\n" "$i" "$name" "$ip" "$proj"
                ((i++))
            done <<< "$vms"
        fi
    done

    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┘${RESET}\n"
    echo -e "${GREEN}✅ Finished listing all VMs${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Connect VM (Premium Box Style + Zone) ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key to use for VM connections:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
        echo -e "${GREEN}Termius key saved at $TERM_KEY_PATH${RESET}"
    fi

    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    echo -e "${YELLOW}=============================================${RESET}"
    echo -e "   🔗 ${BOLD}Connect to VM (Box Style)${RESET}"
    echo -e "${YELLOW}=============================================${RESET}\n"

    vm_list=()
    index=1

    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬──────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│%-14s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ZONE"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼──────────────┤${RESET}\n"

    for proj in $(gcloud projects list --format="value(projectId)"); do
        mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,zone,EXTERNAL_IP)")
        for vm in "${vms[@]}"; do
            name=$(echo $vm | awk '{print $1}')
            zone=$(echo $vm | awk '{print $2}')
            ip=$(echo $vm | awk '{print $3}')
            if [ -n "$name" ] && [ -n "$ip" ]; then
                printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-16s${YELLOW}│${RESET}%-22s${YELLOW}│${RESET}%-31s${YELLOW}│${RESET}%-14s${YELLOW}│${RESET}\n" "$index" "$name" "$ip" "$proj" "$zone"
                vm_list+=("$proj|$name|$zone|$ip")
                ((index++))
            fi
        done
    done

    if [ ${#vm_list[@]} -eq 0 ]; then
        echo -e "${RED}❌ No VMs found across projects!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┴──────────────┘${RESET}\n"
    echo -e "${GREEN}Total VMs Found: ${#vm_list[@]}${RESET}"

    read -p "Enter VM number to connect: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#vm_list[@]} ]; then
        echo -e "${RED}Invalid choice!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    selected="${vm_list[$((choice-1))]}"
    proj=$(echo "$selected" | cut -d'|' -f1)
    vmname=$(echo "$selected" | cut -d'|' -f2)
    zone=$(echo "$selected" | cut -d'|' -f3)
    ip=$(echo "$selected" | cut -d'|' -f4)

    echo -e "${GREEN}${BOLD}Connecting to $vmname ($ip) in project $proj [Zone: $zone]...${RESET}"
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

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|           GCP CLI MENU (ASISH AND PRODIP)         |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Change / Login Google Account               |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Auto Create 3 Projects + Auto Billing       |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Auto Create 6 VMs (2 per Project)           |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs Across Projects                |"
    echo -e "${YELLOW}${BOLD}| [6] 📜 Show All Projects                           |"
    echo -e "${YELLOW}${BOLD}| [7] 🔗 Connect VM (Box Style)                     |"
    echo -e "${YELLOW}${BOLD}| [8] ❌ Disconnect VM                               |"
    echo -e "${YELLOW}${BOLD}| [9] 🗑️ Delete ONE VM                               |"
    echo -e "${YELLOW}${BOLD}| [10] 💣 Delete ALL VMs (ALL Projects)              |"
    echo -e "${YELLOW}${BOLD}| [11] 🚪 Exit                                       |"
    echo -e "${YELLOW}${BOLD}| [12] 💳 Show Billing Accounts                      |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-12]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects ;;
        4) auto_create_vms ;;
        5) show_all_vms ;;
        6) gcloud projects list --format="table(projectId,name,createTime)" ; read -p "Press Enter..." ;;
        7) connect_vm ;;
        8) disconnect_vm ;;
        9) gcloud projects list --format="table(projectId,name)" ; read -p "Enter PID: " projid ; gcloud compute instances list --project=$projid --format="table(name,zone,status)" ; read -p "Enter VM: " vmname ; zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)") ; gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet ;;
        10) for proj in $(gcloud projects list --format="value(projectId)"); do mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)"); for vm in "${vms[@]}"; do zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)"); gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet; done; done ;;
        11) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        12) show_billing_accounts ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter..." ;;
    esac
done
