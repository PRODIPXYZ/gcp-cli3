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

# ---------- Auto Create Projects (Default + 2 new) ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating 2 Projects + Linking Billing...${RESET}"
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    if [ -z "$billing_id" ]; then
        echo -e "${RED}❌ No Billing Account Found.${RESET}"
        return
    fi

    # Link billing to default project if not already
    default_project=$(gcloud projects list --filter="lifecycleState:ACTIVE" --format="value(projectId)" | head -n1)
    if [ -n "$default_project" ]; then
        billing_enabled=$(gcloud beta billing projects describe "$default_project" --format="value(billingEnabled)" 2>/dev/null)
        if [ "$billing_enabled" != "True" ]; then
            echo -e "${CYAN}Linking billing to default project: $default_project${RESET}"
            gcloud beta billing projects link "$default_project" --billing-account "$billing_id" --quiet
            gcloud services enable compute.googleapis.com --project="$default_project" --quiet
        fi
    fi

    # Create 2 new projects
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

# ---------- Auto VM Create (Always 6 VMs) ----------
auto_create_vms() {
    echo -e "${YELLOW}Enter your SSH Public Key (only key part):${RESET}"
    read pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)

    # Default project detect & auto billing link if needed
    default_project=$(gcloud projects list --filter="lifecycleState:ACTIVE" --format="value(projectId)" | head -n1)
    if [ -n "$default_project" ]; then
        billing_enabled=$(gcloud beta billing projects describe "$default_project" --format="value(billingEnabled)" 2>/dev/null)
        if [ "$billing_enabled" != "True" ]; then
            echo -e "${CYAN}Auto linking billing to default project: $default_project${RESET}"
            gcloud beta billing projects link "$default_project" --billing-account "$billing_id" --quiet
            gcloud services enable compute.googleapis.com --project="$default_project" --quiet
        fi
    fi

    # Final 3 projects = default + 2 billing linked
    projects="$default_project
$(gcloud beta billing projects list --billing-account=$billing_id --format="value(projectId)" | head -n2)"

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
    echo -e "${GREEN}✔ All 6 VMs Created Successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Add Extra 2 VMs in Existing Project ----------
add_extra_vms() {
    echo -e "\n${CYAN}${BOLD}➕ Add Extra 2 VMs in Existing Project${RESET}\n"

    vm_projects=()
    index=1

    printf "${YELLOW}┌─────┬──────────────────────────────┬───────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-30s│%-15s│${RESET}\n" "No" "PROJECT" "VM Count"
    printf "${YELLOW}├─────┼──────────────────────────────┼───────────────┤${RESET}\n"

    for proj in $(gcloud projects list --format="value(projectId)"); do
        vms=$(gcloud compute instances list --project=$proj --format="value(name)" 2>/dev/null)
        if [ -n "$vms" ]; then
            vmcount=$(echo "$vms" | wc -l)
            printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-30s${YELLOW}│${RESET}%-15s${YELLOW}│${RESET}\n" "$index" "$proj" "$vmcount"
            vm_projects+=("$proj")
            ((index++))
        fi
    done

    if [ ${#vm_projects[@]} -eq 0 ]; then
        echo -e "${RED}❌ No projects with existing VMs found.${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    printf "${YELLOW}└─────┴──────────────────────────────┴───────────────┘${RESET}\n"
    read -p "Choose project number: " choice
    proj="${vm_projects[$((choice-1))]}"

    echo -e "${CYAN}${BOLD}Enter 2 Extra VM Names:${RESET}"
    vmnames=()
    for i in {1..2}; do
        read -p "VM #$i: " name
        vmnames+=("$name")
    done

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"
    read -p "Enter your SSH Public Key (only key part): " pubkey

    for vmname in "${vmnames[@]}"; do
        gcloud compute instances create $vmname \
            --zone=$zone --machine-type=$mtype \
            --image-family=ubuntu-2404-lts-amd64 \
            --image-project=ubuntu-os-cloud \
            --boot-disk-size=${disksize}GB \
            --boot-disk-type=pd-balanced \
            --metadata ssh-keys="${vmname}:${pubkey}" \
            --tags=http-server,https-server --quiet
    done

    echo -e "${GREEN}✔ Extra 2 VMs created successfully in $proj!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Create 2 VMs in Any Project (Updated Smart Logic) ----------
create_2_vms_in_project() {
    echo -e "\n${CYAN}${BOLD}➕ Create 2 VMs in Any Project${RESET}\n"

    projects=()
    index=1

    printf "${YELLOW}┌─────┬──────────────────────────────┬───────────────┬───────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-30s│%-15s│%-23s│${RESET}\n" "No" "PROJECT" "VM Count" "Billing Status"
    printf "${YELLOW}├─────┼──────────────────────────────┼───────────────┼───────────────────────┤${RESET}\n"

    for proj in $(gcloud projects list --format="value(projectId)"); do
        billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null)
        if [ "$billing_enabled" = "True" ]; then
            billing_status="Enabled"
        else
            billing_status="Disabled"
        fi

        vms=$(gcloud compute instances list --project=$proj --format="value(name)" 2>/dev/null)
        if [ -n "$vms" ]; then
            vmcount=$(echo "$vms" | wc -l)
        else
            vmcount=0
        fi

        printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-30s${YELLOW}│${RESET}%-15s${YELLOW}│${RESET}%-23s${YELLOW}│${RESET}\n" "$index" "$proj" "$vmcount" "$billing_status"
        projects+=("$proj|$billing_status")
        ((index++))
    done

    if [ ${#projects[@]} -eq 0 ]; then
        echo -e "${RED}❌ No projects found.${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    printf "${YELLOW}└─────┴──────────────────────────────┴───────────────┴───────────────────────┘${RESET}\n"
    read -p "Choose project number: " choice
    selected="${projects[$((choice-1))]}"

    proj=$(echo "$selected" | cut -d'|' -f1)
    billing_status=$(echo "$selected" | cut -d'|' -f2)

    if [ "$billing_status" = "Disabled" ]; then
        billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
        echo -e "${CYAN}Linking billing for $proj...${RESET}"
        gcloud beta billing projects link "$proj" --billing-account "$billing_id" --quiet
        gcloud services enable compute.googleapis.com --project="$proj" --quiet
    fi

    echo -e "${CYAN}${BOLD}Enter 2 VM Names:${RESET}"
    vmnames=()
    for i in {1..2}; do
        read -p "VM #$i: " name
        vmnames+=("$name")
    done

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"
    read -p "Enter your SSH Public Key (only key part): " pubkey

    for vmname in "${vmnames[@]}"; do
        gcloud compute instances create $vmname \
            --zone=$zone --machine-type=$mtype \
            --image-family=ubuntu-2404-lts-amd64 \
            --image-project=ubuntu-os-cloud \
            --boot-disk-size=${disksize}GB \
            --boot-disk-type=pd-balanced \
            --metadata ssh-keys="${vmname}:${pubkey}" \
            --tags=http-server,https-server --quiet
    done

    echo -e "${GREEN}✔ 2 VMs created successfully in $proj!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Show All VMs ----------
show_all_vms() {
    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s${YELLOW}│${GREEN}%-22s${YELLOW}│${MAGENTA}%-31s${YELLOW}│%-31s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼───────────────────────────────┤${RESET}\n"

    i=1
    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" > /dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null)
            if [ "$billing_enabled" != "True" ]; then continue; fi
            vms=$(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)" 2>/dev/null)
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

# ---------- Connect VM ----------
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
            billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null)
            if [ "$billing_enabled" != "True" ]; then continue; fi
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)" 2>/dev/null)
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

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|           GCP CLI MENU (ASISH AND PRODIP)         |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Add / Change Google Account (Multi-Login)   |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Create 2 Projects (Billing Linked)          |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Create 6 VMs (Default+2 Projects)           |"
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
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-15]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects ;;
        4) auto_create_vms ;;
        5) show_all_vms ;;
        6) for acc in $(gcloud auth list --format="value(account)"); do
               gcloud config set account "$acc" > /dev/null 2>&1
               echo -e "${CYAN}${BOLD}Account: $acc${RESET}"
               gcloud projects list --format="table(projectId,name,createTime)"
           done ; read -p "Press Enter..." ;;
        7) connect_vm ;;
        8) if [ -f "$SSH_INFO_FILE" ]; then rm "$SSH_INFO_FILE"; echo -e "${GREEN}VM disconnected.${RESET}"; else echo -e "${YELLOW}No active VM.${RESET}"; fi; read -p "Press Enter..." ;;
        9) gcloud projects list --format="table(projectId,name)" ; read -p "Enter PID: " projid ; gcloud compute instances list --project=$projid --format="table(name,zone,status)" ; read -p "Enter VM: " vmname ; zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)") ; gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet ;;
        10) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account "$acc" > /dev/null 2>&1 ; for proj in $(gcloud projects list --format="value(projectId)"); do billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null); if [ "$billing_enabled" != "True" ]; then continue; fi; mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)" 2>/dev/null); for vm in "${vms[@]}"; do zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)" 2>/dev/null); gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet; done; done; done ;;
        11) gcloud beta billing accounts list --format="table(displayName,accountId,ACCOUNT_ID,open)" ; read -p "Press Enter..." ;;
        12) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        13) logout_google_account ;;
        14) add_extra_vms ;;
        15) create_2_vms_in_project ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter..." ;;
    esac
done
