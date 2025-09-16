#!/bin/bash

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
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

    if ! command -v gcloud &> /dev/null
    then
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

# ---------- Auto Project + Billing ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating 3 Projects + Linking Billing...${RESET}"
    billing_id=$(gcloud beta billing accounts list --format="value(accountId)" | head -n1)
    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}No Billing Account Found!${RESET}"
        return
    fi

    for i in {20..22}; do
        projid="prodip${i}-$(shuf -i 100-999 -n 1)"
        gcloud projects create "$projid" --name="prodip${i}" --quiet
        gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet
        echo -e "${GREEN}Project $projid created & billing linked.${RESET}"
    done
    read -p "Press Enter to continue..."
}

# ---------- Auto VM Create ----------
auto_create_vms() {
    echo -e "${YELLOW}${BOLD}Enter your SSH Public Key (username:ssh-rsa ...):${RESET}"
    read sshkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    vm_count=1
    for proj in $(gcloud projects list --format="value(projectId)" | grep "prodip2"); do
        gcloud config set project $proj > /dev/null 2>&1
        for j in {1..2}; do
            vmname="vm${vm_count}"
            echo -e "${GREEN}${BOLD}Creating $vmname in $proj...${RESET}"
            gcloud compute instances create $vmname \
                --zone=$zone \
                --machine-type=$mtype \
                --image-family=ubuntu-2404-lts-amd64 \
                --image-project=ubuntu-os-cloud \
                --boot-disk-size=${disksize}GB \
                --boot-disk-type=pd-balanced \
                --metadata ssh-keys="$sshkey" \
                --tags=http-server,https-server \
                --quiet
            ((vm_count++))
        done
    done
    echo -e "${GREEN}${BOLD}All 6 VMs Created Successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Show All VMs ----------
show_all_vms() {
    echo -e "${YELLOW}${BOLD}Showing All VMs Across Projects:${RESET}"
    for proj in $(gcloud projects list --format="value(projectId)" | grep "prodip2"); do
        echo -e "${CYAN}${BOLD}Project: $proj${RESET}"
        gcloud compute instances list --project=$proj --format="table(name,zone,status,INTERNAL_IP,EXTERNAL_IP)"
    done
    read -p "Press Enter to continue..."
}

# ---------- Delete One VM ----------
delete_one_vm() {
    echo -e "${YELLOW}${BOLD}Deleting a Single VM...${RESET}"
    gcloud projects list --format="table(projectId,name)"
    read -p "Enter Project ID: " projid
    gcloud compute instances list --project=$projid --format="table(name,zone,status)"
    read -p "Enter VM Name to delete: " vmname
    zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)")
    if [ -z "$zone" ]; then
        echo -e "${RED}VM not found!${RESET}"
    else
        gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet
        echo -e "${GREEN}VM $vmname deleted successfully from project $projid.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Auto Delete All VMs ----------
delete_all_vms() {
    echo -e "${RED}${BOLD}Deleting ALL VMs across projects (prodip20–22)...${RESET}"
    for proj in $(gcloud projects list --format="value(projectId)" | grep "prodip2"); do
        gcloud config set project $proj > /dev/null 2>&1
        mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)")
        for vm in "${vms[@]}"; do
            zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)")
            gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet
            echo -e "${GREEN}Deleted $vm from $proj${RESET}"
        done
    done
    read -p "Press Enter to continue..."
}

# ---------- Connect VM using Termius Key (UNCHANGED) ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key to use for VM connections:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
        echo -e "${GREEN}Termius key saved at $TERM_KEY_PATH${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Available VMs in current project:${RESET}"
    mapfile -t vms < <(gcloud compute instances list --format="value(name)")
    if [ ${#vms[@]} -eq 0 ]; then
        echo -e "${RED}No VMs found!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    for i in "${!vms[@]}"; do
        echo "$((i+1))) ${vms[$i]}"
    done

    read -p "Select VM to connect [number]: " vmnum
    vmindex=$((vmnum-1))
    if [[ -z "${vms[$vmindex]}" ]]; then
        echo -e "${RED}Invalid selection!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    vmname="${vms[$vmindex]}"
    zone=$(gcloud compute instances list --filter="name=$vmname" --format="value(zone)")
    ext_ip=$(gcloud compute instances describe $vmname --zone $zone --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    ssh_user=$(gcloud compute instances describe $vmname --zone $zone --format="get(metadata.ssh-keys)" | awk -F':' '{print $1}')

    echo "$vmname|$ssh_user|$ext_ip|$TERM_KEY_PATH" > "$SSH_INFO_FILE"

    echo -e "${GREEN}Connecting to $vmname using Termius private key...${RESET}"
    ssh -i "$TERM_KEY_PATH" "$ssh_user@$ext_ip"
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
    echo -e "${CYAN}${BOLD}|     GCP CLI BENGAL AIRDROP (MADE BY PRODIP)       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Change / Login Google Account               |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Auto Create Projects (3) + Billing Link     |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Auto Create 6 VMs                           |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs Across Projects                |"
    echo -e "${YELLOW}${BOLD}| [6] 🔗 Connect VM (Termius Key)                    |"
    echo -e "${YELLOW}${BOLD}| [7] ❌ Disconnect VM                               |"
    echo -e "${YELLOW}${BOLD}| [8] 🗑️ Delete ONE VM                               |"
    echo -e "${YELLOW}${BOLD}| [9] 💣 Auto Delete ALL VMs                         |"
    echo -e "${YELLOW}${BOLD}| [10] 🚪 Exit                                       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-10]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects ;;
        4) auto_create_vms ;;
        5) show_all_vms ;;
        6) connect_vm ;;   # unchanged
        7) disconnect_vm ;;
        8) delete_one_vm ;;
        9) delete_all_vms ;;
        10) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter to continue..." ;;
    esac
done
