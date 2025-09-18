#!/bin/bash

# ---------- Colors ----------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"
MAGENTA="\e[35m"; BLUE="\e[34m"; BOLD='\033[1m'; RESET="\e[0m"

# ---------- Files ----------
SSH_INFO_FILE="$HOME/.gcp_vm_info"
TERM_KEY_PATH="$HOME/.ssh/termius_vm_key"

# ---------- List Google Accounts ----------
list_google_accounts() {
    echo -e "\n${CYAN}${BOLD}📧 Available Google Accounts${RESET}\n"
    accounts=$(gcloud auth list --format="value(account)")
    if [ -z "$accounts" ]; then echo -e "${RED}❌ No accounts found.${RESET}"; return 1; fi
    i=1
    printf "${YELLOW}┌─────┬──────────────────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-42s│${RESET}\n" "No" "Account Email"
    printf "${YELLOW}├─────┼──────────────────────────────────────────┤${RESET}\n"
    while read -r acc; do
        printf "${YELLOW}│${RESET}%-5s${YELLOW}│${RESET}%-42s${YELLOW}│${RESET}\n" "$i" "$acc"
        accounts_list[$i]="$acc"; ((i++))
    done <<< "$accounts"
    printf "${YELLOW}└─────┴──────────────────────────────────────────┘${RESET}\n"
}

# ---------- Select / Logout ----------
select_google_account() { list_google_accounts || return 1; read -p "Enter account no: " c; gcloud config set account "${accounts_list[$c]}" >/dev/null 2>&1; }
logout_google_account() { list_google_accounts || return 1; read -p "Logout which no: " c; gcloud auth revoke "${accounts_list[$c]}" --quiet; read -p "Press Enter..."; }

# ---------- Fresh Install ----------
fresh_install() {
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip python3 python3-pip docker.io
    sudo systemctl enable docker --now
    command -v gcloud >/dev/null || curl https://sdk.cloud.google.com | bash
    gcloud auth login
}

# ---------- Add Account ----------
change_google_account() { gcloud auth login; }

# ---------- Create Projects ----------
auto_create_projects() {
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    for i in 1 2; do
        projid="auto-proj-$RANDOM"; projname="auto-proj-$i"
        gcloud projects create "$projid" --name="$projname" --quiet || continue
        gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet || continue
        gcloud services enable compute.googleapis.com --project="$projid" --quiet
    done
}
auto_create_projects_menu() { echo "1) One account  2) All accounts"; read c;
    case $c in
        1) select_google_account && auto_create_projects ;;
        2) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account $acc; auto_create_projects; done ;;
    esac
}

# ---------- Create VMs ----------
auto_create_vms() {
    read -p "Enter SSH Public Key: " pubkey
    zone="asia-southeast1-b"; mtype="n2d-custom-4-25600"; disksize="60"
    default_project=$(gcloud projects list --format="value(projectId)" | head -n1)
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    billing_projects=$(gcloud beta billing projects list --billing-account=$billing_id --format="value(projectId)" | head -n2)
    projects="$default_project $billing_projects"
    echo "Enter 6 VM Names:"; vmnames=(); for i in {1..6}; do read -p "VM #$i: " n; vmnames+=("$n"); done
    count=0
    for proj in $projects; do gcloud config set project $proj >/dev/null 2>&1
        for j in {1..2}; do vm=${vmnames[$count]}
            gcloud compute instances create $vm --zone=$zone --machine-type=$mtype \
              --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
              --boot-disk-size=${disksize}GB --boot-disk-type=pd-balanced \
              --metadata ssh-keys="${vm}:${pubkey}" --tags=http-server,https-server --quiet
            ((count++))
        done
    done
}
auto_create_vms_menu() { echo "1) One account  2) All accounts"; read c;
    case $c in
        1) select_google_account && auto_create_vms ;;
        2) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account $acc; auto_create_vms; done ;;
    esac
}

# ---------- Show All VMs (Filtered) ----------
show_all_vms() {
    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-16s│%-22s│%-31s│%-31s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼───────────────────────────────┤${RESET}\n"
    i=1
    for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account $acc >/dev/null
        for proj in $(gcloud projects list --format="value(projectId)"); do
            vms=$(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)" 2>/dev/null)
            [ -z "$vms" ] && continue
            while read -r n ip; do
                printf "│%-5s│%-16s│%-22s│%-31s│%-31s│\n" "$i" "$n" "$ip" "$proj" "$acc"; ((i++))
            done <<< "$vms"
        done
    done
    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┴───────────────────────────────┘${RESET}\n"
    read -p "Press Enter..."
}

# ---------- Connect VM (Filtered) ----------
connect_vm() {
    [ ! -f "$TERM_KEY_PATH" ] && read -p "Enter Termius key path: " k && cp "$k" "$TERM_KEY_PATH" && chmod 600 "$TERM_KEY_PATH"
    vm_list=(); index=1
    printf "${YELLOW}┌─────┬────────────────┬──────────────────────┬───────────────────────────────┬───────────────────────────────┐${RESET}\n"
    printf "${YELLOW}│%-5s│%-16s│%-22s│%-31s│%-31s│${RESET}\n" "No" "USERNAME" "IP" "PROJECT" "ACCOUNT"
    printf "${YELLOW}├─────┼────────────────┼──────────────────────┼───────────────────────────────┼───────────────────────────────┤${RESET}\n"
    for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account $acc >/dev/null
        for proj in $(gcloud projects list --format="value(projectId)"); do
            mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)" 2>/dev/null)
            for vm in "${vms[@]}"; do [ -z "$vm" ] && continue
                name=$(echo $vm | awk '{print $1}'); ip=$(echo $vm | awk '{print $2}')
                printf "│%-5s│%-16s│%-22s│%-31s│%-31s│\n" "$index" "$name" "$ip" "$proj" "$acc"
                vm_list+=("$acc|$proj|$name|$ip"); ((index++))
            done
        done
    done
    printf "${YELLOW}└─────┴────────────────┴──────────────────────┴───────────────────────────────┴───────────────────────────────┘${RESET}\n"
    read -p "Enter VM no: " c
    sel="${vm_list[$((c-1))]}"; acc=$(echo $sel|cut -d'|' -f1); proj=$(echo $sel|cut -d'|' -f2); name=$(echo $sel|cut -d'|' -f3); ip=$(echo $sel|cut -d'|' -f4)
    ssh -i "$TERM_KEY_PATH" "$name@$ip"
}

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------- GCP CLI MENU ----------------+${RESET}"
    echo -e "${YELLOW}[1] Fresh Install"
    echo -e "[2] Add/Change Google Account"
    echo -e "[3] Create Project (One/All, 2 only)"
    echo -e "[4] Create VM (One/All, 6 total)"
    echo -e "[5] Show All VMs (Filtered)"
    echo -e "[6] Show All Projects (All Accounts)"
    echo -e "[7] Connect VM (Filtered)"
    echo -e "[8] Logout Google Account"
    echo -e "[9] Exit${RESET}"
    read -p "Choose: " ch
    case $ch in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects_menu ;;
        4) auto_create_vms_menu ;;
        5) show_all_vms ;;
        6) for acc in $(gcloud auth list --format="value(account)"); do gcloud config set account $acc >/dev/null; echo "Account: $acc"; gcloud projects list --format="table(projectId,name,createTime)"; done; read -p "Enter...";;
        7) connect_vm ;;
        8) logout_google_account ;;
        9) exit 0 ;;
    esac
done
