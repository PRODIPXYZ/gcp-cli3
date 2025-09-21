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

# ---------- Auto Create Projects (with account selection) ----------
auto_create_projects() {
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|             CREATE PROJECTS - ACCOUNT SELECTION     |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 📁 Create Projects in ONE Account             |"
    echo -e "${YELLOW}${BOLD}| [2] 📁 Create Projects in ALL Logged-in Accounts  |"
    echo -e "${YELLOW}${BOLD}| [3] 🔙 Back                                       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-3]: " project_choice

    case $project_choice in
        1)
            list_google_accounts || return 1
            read -p "Enter account number to create projects: " acc_choice
            selected_acc="${accounts_list[$acc_choice]}"
            if [ -z "$selected_acc" ]; then
                echo -e "${RED}Invalid choice!${RESET}"
                read -p "Press Enter to continue..."
                return
            fi
            
            echo -e "${CYAN}Creating projects in account: ${BOLD}$selected_acc${RESET}"
            gcloud config set account "$selected_acc" --quiet

            billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
            if [ -z "$billing_id" ]; then
                echo -e "${RED}❌ No Billing Account Found for this account.${RESET}"
                read -p "Press Enter to continue..."
                return
            fi

            for i in 1 2 3; do
                projid="auto-proj-$RANDOM"
                projname="auto-proj-$i"
                echo -e "${CYAN}➡️ Creating Project: $projid ($projname)${RESET}"
                gcloud projects create "$projid" --name="$projname" --quiet || continue
                gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet || continue
                gcloud services enable compute.googleapis.com --project="$projid" --quiet
                echo -e "${GREEN}✔ Project $projid ready.${RESET}"
            done
            read -p "Press Enter to continue..."
            ;;
        2)
            echo -e "${CYAN}Creating projects in ALL logged-in accounts...${RESET}"
            for acc in $(gcloud auth list --format="value(account)"); do
                echo -e "\n${BOLD}🔄 Now working on account: $acc${RESET}"
                gcloud config set account "$acc" --quiet
                
                billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
                if [ -z "$billing_id" ]; then
                    echo -e "${YELLOW}⚠️ No Billing Account found for this account. Skipping.${RESET}"
                    continue
                fi

                for i in 1 2 3; do
                    projid="auto-proj-$RANDOM"
                    projname="auto-proj-$i"
                    echo -e "${CYAN}➡️ Creating Project: $projid ($projname)${RESET}"
                    gcloud projects create "$projid" --name="$projname" --quiet || continue
                    gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet || continue
                    gcloud services enable compute.googleapis.com --project="$projid" --quiet
                    echo -e "${GREEN}✔ Project $projid ready.${RESET}"
                done
            done
            read -p "Press Enter to continue..."
            ;;
        3)
            return
            ;;
        *)
            echo -e "${RED}Invalid choice!${RESET}"
            read -p "Press Enter to continue..."
            ;;
    esac
}

# ---------- Auto VM Create (with account selection) ----------
auto_create_vms() {
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|             CREATE VMs - ACCOUNT SELECTION        |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🚀 Create VMs in ONE Account                  |"
    echo -e "${YELLOW}${BOLD}| [2] 🚀 Create VMs in ALL Logged-in Accounts       |"
    echo -e "${YELLOW}${BOLD}| [3] 🔙 Back                                       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-3]: " vm_choice

    case $vm_choice in
        1)
            list_google_accounts || return 1
            read -p "Enter account number to create VMs: " acc_choice
            selected_acc="${accounts_list[$acc_choice]}"
            if [ -z "$selected_acc" ]; then
                echo -e "${RED}Invalid choice!${RESET}"
                read -p "Press Enter to continue..."
                return
            fi
            
            echo -e "${CYAN}Creating VMs in account: ${BOLD}$selected_acc${RESET}"
            gcloud config set account "$selected_acc" --quiet
            
            zone="asia-southeast1-b"
            mtype="n2d-custom-4-25600"
            disksize="60"
            read -p "Enter your SSH Public Key (only key part): " pubkey
            
            projects=$(gcloud beta billing projects list --format="value(projectId)")
            
            if [ -z "$projects" ]; then
                echo -e "${RED}❌ No billing-linked projects found in this account.${RESET}"
                read -p "Press Enter to continue..."
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
                if [ $count -ge 6 ]; then break; fi
                gcloud config set project $proj > /dev/null 2>&1
                for j in {1..2}; do
                    if [ $count -ge 6 ]; then break; fi
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
            ;;
        2)
            zone="asia-southeast1-b"
            mtype="n2d-custom-4-25600"
            disksize="60"
            read -p "Enter your SSH Public Key (only key part): " pubkey

            echo -e "${CYAN}${BOLD}Enter 6 VM Names:${RESET}"
            vmnames=()
            for i in {1..6}; do
                read -p "VM #$i: " name
                vmnames+=("$name")
            done

            count=0
            for acc in $(gcloud auth list --format="value(account)"); do
                echo -e "\n${BOLD}🔄 Now working on account: $acc${RESET}"
                gcloud config set account "$acc" --quiet
                
                projects=$(gcloud beta billing projects list --format="value(projectId)")
                
                if [ -z "$projects" ]; then
                    echo -e "${YELLOW}⚠️ No billing-linked projects found. Skipping this account.${RESET}"
                    continue
                fi

                for proj in $projects; do
                    if [ $count -ge 6 ]; then break; fi
                    gcloud config set project $proj > /dev/null 2>&1
                    for j in {1..2}; do
                        if [ $count -ge 6 ]; then break; fi
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
            done
            echo -e "${GREEN}✔ All 6 VMs Created Successfully!${RESET}"
            read -p "Press Enter to continue..."
            ;;
        3)
            return
            ;;
        *)
            echo -e "${RED}Invalid choice!${RESET}"
            read -p "Press Enter to continue..."
            ;;
    esac
}

# ---------- Add Extra 2 VMs in Existing Project ----------
add_extra_vms() {
    echo -e "\n${CYAN}${BOLD}➕ Add Extra 2 VMs in Existing Project${RESET}\n"

    vm_projects=()
    index=1

    printf "${YELLOW}┌─────┬──────────────────────────────┬───────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${CYAN}%-30s${YELLOW}│${MAGENTA}%-15s${YELLOW}│${RESET}\n" "No" "PROJECT" "VM Count"
    printf "${YELLOW}├─────┼──────────────────────────────┼───────────────┤${RESET}\n"

    for proj in $(gcloud projects list --format="value(projectId)"); do
        vms=$(gcloud compute instances list --project=$proj --format="value(name)" 2>/dev/null)
        if [ -n "$vms" ]; then
            vmcount=$(echo "$vms" | wc -l)
            printf "${YELLOW}│${RESET}%-5s│${CYAN}%-30s│${MAGENTA}%-15s│${RESET}\n" "$index" "$proj" "$vmcount"
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
            --project=$proj --zone=$zone --machine-type=$mtype \
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

# ---------- Create 2 VMs in Any Project ----------
create_2_vms_in_project() {
    echo -e "\n${CYAN}${BOLD}➕ Create 2 VMs in Any Project${RESET}\n"

    projects=()
    index=1

    printf "${YELLOW}┌─────┬──────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${CYAN}%-30s│${RESET}\n" "No" "PROJECT"
    printf "${YELLOW}├─────┼──────────────────────────────┤${RESET}\n"

    for proj in $(gcloud projects list --format="value(projectId)"); do
        billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null)
        if [ "$billing_enabled" = "True" ]; then
            printf "${YELLOW}│${RESET}%-5s│${CYAN}%-30s│${RESET}\n" "$index" "$proj"
            projects+=("$proj")
            ((index++))
        fi
    done

    printf "${YELLOW}└─────┴──────────────────────────────┘${RESET}\n"
    read -p "Choose project number: " choice
    proj="${projects[$((choice-1))]}"

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
            --project=$proj --zone=$zone --machine-type=$mtype \
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

# ---------- Create Single VM in a Project ----------
create_single_vm() {
    echo -e "\n${CYAN}${BOLD}➕ Create a Single VM in a Project${RESET}\n"

    # Show accounts and let the user select one
    list_google_accounts || return 1
    read -p "Enter account number to create VM in: " acc_choice
    selected_acc="${accounts_list[$acc_choice]}"
    if [ -z "$selected_acc" ]; then
        echo -e "${RED}Invalid account choice!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi
    gcloud config set account "$selected_acc" --quiet

    # Show projects for the selected account
    echo -e "\n${CYAN}${BOLD}📁 Projects for account: ${BOLD}$selected_acc${RESET}\n"
    projects=()
    index=1
    printf "${YELLOW}┌─────┬──────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${CYAN}%-30s│${RESET}\n" "No" "PROJECT"
    printf "${YELLOW}├─────┼──────────────────────────────┤${RESET}\n"
    for proj in $(gcloud projects list --format="value(projectId)"); do
        billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null)
        if [ "$billing_enabled" = "True" ]; then
            printf "${YELLOW}│${RESET}%-5s│${CYAN}%-30s│${RESET}\n" "$index" "$proj"
            projects+=("$proj")
            ((index++))
        fi
    done
    printf "${YELLOW}└─────┴──────────────────────────────┘${RESET}\n"

    if [ ${#projects[@]} -eq 0 ]; then
        echo -e "${RED}❌ No billing-enabled projects found for this account.${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    # Let the user select a project
    read -p "Choose project number to create the VM in: " proj_choice
    proj="${projects[$((proj_choice-1))]}"
    if [ -z "$proj" ]; then
        echo -e "${RED}Invalid project choice!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi
    gcloud config set project "$proj" --quiet

    # Get VM name and SSH key
    echo -e "${CYAN}${BOLD}Enter a single VM Name:${RESET}"
    read -p "VM Name: " vmname
    read -p "Enter your SSH Public Key (only key part): " pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    echo -e "${GREEN}Creating VM $vmname in project $proj...${RESET}"
    gcloud compute instances create $vmname \
        --project=$proj --zone=$zone --machine-type=$mtype \
        --image-family=ubuntu-2404-lts-amd64 \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size=${disksize}GB \
        --boot-disk-type=pd-balanced \
        --metadata ssh-keys="${vmname}:${pubkey}" \
        --tags=http-server,https-server --quiet

    echo -e "${GREEN}✔ VM '$vmname' created successfully in project '$proj'!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Show All VMs ----------
show_all_vms() {
    echo -e "\n${CYAN}${BOLD}💻 MADE BY PRODIP${RESET}\n"
    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│${BLUE}%-16s│${GREEN}%-22s│${MAGENTA}%-31s│${CYAN}%-31s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
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
                    printf "${YELLOW}│${RESET}%-5s│${BLUE}%-16s│${GREEN}%-22s│${MAGENTA}%-31s│${CYAN}%-31s│${RESET}\n" "$i" "$name" "$ip" "$proj" "$acc"
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
    printf "${YELLOW}│%-5s│${BLUE}%-16s│${GREEN}%-22s│${MAGENTA}%-31s│${CYAN}%-31s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
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
                    printf "${YELLOW}│${RESET}%-5s│${BLUE}%-16s│${GREEN}%-22s│${MAGENTA}%-31s│${CYAN}%-31s│${RESET}\n" "$index" "$name" "$ip" "$proj" "$acc"
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
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$TERM_KEY_PATH" "$vmname@$ip"
    read -p "Press Enter to continue..."
}

# ---------- Check Gensyn Node Status ----------
check_gensyn_node_status() {
    echo -e "\n${CYAN}${BOLD}🔍 Gensyn Node Status${RESET}\n"
    
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${RED}❌ Termius private key not found! Please connect to a VM first to save the key.${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    vm_list=()
    crashed_vms=()
    index=1

    printf "${YELLOW}┌─────┬────────────────┬───────────────────────────────┬───────────────────────────────┬───────────────────┐${RESET}\n"
    printf "${YELLOW}│${BOLD}%-5s│${YELLOW}%-16s│${CYAN}%-31s│${RESET}%-31s│${RESET}%-19s│${RESET}\n" "No" "VM Name" "Email ID" "Log Check" "Live Status"
    printf "${YELLOW}├─────┼────────────────┼───────────────────────────────┼───────────────────────────────┼───────────────────┤${RESET}\n"

    for acc in $(gcloud auth list --format="value(account)"); do
        gcloud config set account "$acc" > /dev/null 2>&1
        for proj in $(gcloud projects list --format="value(projectId)"); do
            billing_enabled=$(gcloud beta billing projects describe "$proj" --format="value(billingEnabled)" 2>/dev/null)
            if [ "$billing_enabled" != "True" ]; then continue; fi
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP,machineType)" 2>/dev/null)
            for vm in "${vms[@]}"; do
                name=$(echo $vm | awk '{print $1}')
                ip=$(echo $vm | awk '{print $2}')
                
                # --- NEW LOGIC: Check for "Map: 100%" in tmux session 'GEN' ---
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$TERM_KEY_PATH" "$name@$ip" 'tmux capture-pane -t "GEN" -p -S -10 | grep -q "Map: 100%"' >/dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    printf "${YELLOW}│${RESET}%-5s│${YELLOW}%-16s│${CYAN}%-31s│${GREEN}%-31s${YELLOW}│${GREEN}%-19s│${RESET}\n" "$index" "$name" "$acc" "Map: 100% Found" "LIVE"
                else
                    printf "${YELLOW}│${RESET}%-5s│${YELLOW}%-16s│${CYAN}%-31s│${RED}%-31s${YELLOW}│${RED}%-19s│${RESET}\n" "$index" "$name" "$acc" "Not Found" "OFFLINE"
                    crashed_vms+=("$acc|$proj|$name|$ip")
                fi
                vm_list+=("$acc|$proj|$name|$ip")
                ((index++))
            done
        done
    done
    printf "${YELLOW}└─────┴────────────────┴───────────────────────────────┴───────────────────────────────┴───────────────────┘${RESET}\n"

    if [ ${#crashed_vms[@]} -gt 0 ]; then
        echo -e "\n${RED}⚠️ Detected Crashed Nodes!${RESET}"
        
        printf "${YELLOW}┌─────┬────────────────┬───────────────────────────────┐${RESET}\n"
        printf "${YELLOW}│%-5s│${BLUE}%-16s│${MAGENTA}%-31s│${RESET}\n" "No" "VM NAME" "ACCOUNT"
        printf "${YELLOW}├─────┼────────────────┼───────────────────────────────┤${RESET}\n"

        for i in "${!crashed_vms[@]}"; do
            crashed_info="${crashed_vms[$i]}"
            crashed_acc=$(echo "$crashed_info" | cut -d'|' -f1)
            crashed_name=$(echo "$crashed_info" | cut -d'|' -f3)
            printf "${YELLOW}│${RESET}%-5s│${BLUE}%-16s│${MAGENTA}%-31s│${RESET}\n" "$((i+1))" "$crashed_name" "$crashed_acc"
            crashed_list_for_connect[$((i+1))]="${crashed_info}"
        done
        printf "${YELLOW}└─────┴────────────────┴───────────────────────────────┘${RESET}\n"

        read -p "Enter VM number to connect and restart the node: " crash_choice
        selected_crash_vm="${crashed_list_for_connect[$crash_choice]}"

        if [ -n "$selected_crash_vm" ]; then
            acc=$(echo "$selected_crash_vm" | cut -d'|' -f1)
            proj=$(echo "$selected_crash_vm" | cut -d'|' -f2)
            vmname=$(echo "$selected_crash_vm" | cut -d'|' -f3)
            ip=$(echo "$selected_crash_vm" | cut -d'|' -f4)
            
            echo -e "${GREEN}${BOLD}Connecting to $vmname ($ip) in project $proj [Account: $acc]...${RESET}"
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$TERM_KEY_PATH" "$vmname@$ip"
        else
            echo -e "${RED}Invalid choice!${RESET}"
        fi
    fi
    read -p "Press Enter to continue..."
}

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|             GCP CLI MENU (ASISH AND PRODIP)       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                  |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Add / Change Google Account (Multi-Login)  |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Create Projects (Account Select)           |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Create VMs (Account Select)                |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs                               |"
    echo -e "${YELLOW}${BOLD}| [6] 📜 Show All Projects                          |"
    echo -e "${YELLOW}${BOLD}| [7] 🔗 Connect VM                                 |"
    echo -e "${YELLOW}${BOLD}| [8] ❌ Disconnect VM (Remove saved info)          |"
    echo -e "${YELLOW}${BOLD}| [9] 🗑️ Delete ONE VM                              |"
    echo -e "${YELLOW}${BOLD}| [10] 💣 Delete ALL VMs (All Accounts)             |"
    echo -e "${YELLOW}${BOLD}| [11] 💳 Show Billing Accounts                     |"
    echo -e "${YELLOW}${BOLD}| [12] 🚪 Exit                                      |"
    echo -e "${YELLOW}${BOLD}| [13] 🔓 Logout Google Account                     |"
    echo -e "${YELLOW}${BOLD}| [14] ➕ Add Extra 2 VMs in Existing Project        |"
    echo -e "${YELLOW}${BOLD}| [15] ➕ Create 2 VMs in Any Project                |"
    echo -e "${YELLOW}${BOLD}| [16] 🟢 Check Gensyn Node Status                  |"
    echo -e "${YELLOW}${BOLD}| [17] 🎯 Create Single VM in a Project             |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-17]: " choice

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
        16) check_gensyn_node_status ;;
        17) create_single_vm ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter..." ;;
    esac
done
