#!/bin/bash
# 
# Copyright 2019-2021 Shiyghan Navti. Email shiyghan@techequity.company
#
#################################################################################
#############           Explore Internal Load Balancing           ###############
#################################################################################

function ask_yes_or_no() {
    read -p "$1 ([y]yes to preview, [n]o to create, [d]del to delete): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        n|no)  echo "no" ;;
        d|del) echo "del" ;;
        *)     echo "yes" ;;
    esac
}

function ask_yes_or_no_proj() {
    read -p "$1 ([y]es to change, or any key to skip): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

clear
MODE=1
export TRAINING_ORG_ID=$(gcloud organizations list --format 'value(ID)' --filter="displayName:techequity.training" 2>/dev/null)
export ORG_ID=$(gcloud projects get-ancestors $GCP_PROJECT --format 'value(ID)' 2>/dev/null | tail -1 )
export GCP_PROJECT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)  

echo
echo
echo -e "                        👋  Welcome to Cloud Sandbox! 💻"
echo 
echo -e "              *** PLEASE WAIT WHILE LAB UTILITIES ARE INSTALLED ***"
sudo apt-get -qq install pv > /dev/null 2>&1
echo 
export SCRIPTPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p `pwd`/gcp-ce-ilb
export PROJDIR=`pwd`/gcp-ce-ilb
export SCRIPTNAME=gcp-ce-ilb.sh

if [ -f "$PROJDIR/.env" ]; then
    source $PROJDIR/.env
else
cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=europe-west1
export GCP_ZONE=europe-west1-b
EOF
source $PROJDIR/.env
fi

# Display menu options
while :
do
clear
cat<<EOF
===================================================================
Configure Internal HTTP Load Balancing and Identity Aware Proxy
-------------------------------------------------------------------
Please enter number to select your choice:
 (1) Enable APIs
 (2) Create network and subnets
 (3) Create firewall rules
 (4) Create template and managed instance group 
 (5) Validate access to the managed instance groups
 (6) Configure name port 
 (7) Configure basic health check and backend services
 (8) Add backend services to instance groups and configure scaling
 (9) Configure URL map, target http proxy and forwarding rules
(10) Test access via ILB
(11) Configure access via IAP
 (G) Launch user guide
 (Q) Quit
-----------------------------------------------------------------------------
EOF
echo "Steps performed${STEP}"
echo
echo "What additional step do you want to perform, e.g. enter 0 to select the execution mode?"
read
clear
case "${REPLY^^}" in

"0")
start=`date +%s`
source $PROJDIR/.env
echo
echo "Do you want to run script in preview mode?"
export ANSWER=$(ask_yes_or_no "Are you sure?")
cd $HOME
if [[ ! -z "$TRAINING_ORG_ID" ]]  &&  [[ $ORG_ID == "$TRAINING_ORG_ID" ]]; then
    export STEP="${STEP},0"
    MODE=1
    if [[ "yes" == $ANSWER ]]; then
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    else 
        if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
            echo 
            echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
            echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
        else
            while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                echo 
                echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                gcloud auth login  --brief --quiet
                export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                if [[ $ACCOUNT != "" ]]; then
                    echo
                    echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                    read GCP_PROJECT
                    gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                    sleep 3
                    export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                fi
            done
            gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
            sleep 2
            gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
            gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
            gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
            gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
        fi
        export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
        cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
EOF
        gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
        echo
        echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
        echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
        echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
        echo
        echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
        echo "*** $PROJDIR/.env ***" | pv -qL 100
        if [[ "no" == $ANSWER ]]; then
            MODE=2
            echo
            echo "*** Create mode is active ***" | pv -qL 100
        elif [[ "del" == $ANSWER ]]; then
            export STEP="${STEP},0"
            MODE=3
            echo
            echo "*** Resource delete mode is active ***" | pv -qL 100
        fi
    fi
else 
    if [[ "no" == $ANSWER ]] || [[ "del" == $ANSWER ]] ; then
        export STEP="${STEP},0"
        if [[ -f $SCRIPTPATH/.${SCRIPTNAME}.secret ]]; then
            echo
            unset password
            unset pass_var
            echo -n "Enter access code: " | pv -qL 100
            while IFS= read -p "$pass_var" -r -s -n 1 letter
            do
                if [[ $letter == $'\0' ]]
                then
                    break
                fi
                password=$password"$letter"
                pass_var="*"
            done
            while [[ -z "${password// }" ]]; do
                unset password
                unset pass_var
                echo
                echo -n "You must enter an access code to proceed: " | pv -qL 100
                while IFS= read -p "$pass_var" -r -s -n 1 letter
                do
                    if [[ $letter == $'\0' ]]
                    then
                        break
                    fi
                    password=$password"$letter"
                    pass_var="*"
                done
            done
            export PASSCODE=$(cat $SCRIPTPATH/.${SCRIPTNAME}.secret | openssl enc -aes-256-cbc -md sha512 -a -d -pbkdf2 -iter 100000 -salt -pass pass:$password 2> /dev/null)
            if [[ $PASSCODE == 'AccessVerified' ]]; then
                MODE=2
                echo && echo
                echo "*** Access code is valid ***" | pv -qL 100
                if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
                    echo 
                    echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
                    echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
                else
                    while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                        echo 
                        echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                        gcloud auth login  --brief --quiet
                        export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                        if [[ $ACCOUNT != "" ]]; then
                            echo
                            echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                            read GCP_PROJECT
                            gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                            sleep 3
                            export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                        fi
                    done
                    gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
                    sleep 2
                    gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
                    gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
                    gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
                    gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
                fi
                export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
                cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
EOF
                gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
                echo
                echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
                echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
                echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
                echo
                echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
                echo "*** $PROJDIR/.env ***" | pv -qL 100
                if [[ "no" == $ANSWER ]]; then
                    MODE=2
                    echo
                    echo "*** Create mode is active ***" | pv -qL 100
                elif [[ "del" == $ANSWER ]]; then
                    export STEP="${STEP},0"
                    MODE=3
                    echo
                    echo "*** Resource delete mode is active ***" | pv -qL 100
                fi
            else
                echo && echo
                echo "*** Access code is invalid ***" | pv -qL 100
                echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
                echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
                echo
                echo "*** Command preview mode is active ***" | pv -qL 100
            fi
        else
            echo
            echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
            echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
            echo
            echo "*** Command preview mode is active ***" | pv -qL 100
        fi
    else
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    fi
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"1")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},1i"
    echo
    echo "$ gcloud services enable compute.googleapis.com iap.googleapis.com # to enable compute APIs" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},1"
    echo
    echo "$ gcloud services enable compute.googleapis.com iap.googleapis.com # to enable compute APIs" | pv -qL 100
    gcloud services enable compute.googleapis.com iap.googleapis.com
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},1x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},1i"
    echo
    echo "1. Enable APIs" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"2")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},2i"
    echo
    echo "$ gcloud compute networks create ilb-net --subnet-mode custom # to create network" | pv -qL 100
    echo
    echo "$ gcloud compute networks subnets create ilb-subnet-a --purpose INTERNAL_HTTPS_LOAD_BALANCER --role ACTIVE --region \$GCP_REGION --network ilb-net --range 10.10.20.0/24 # to create subnet" | pv -qL 100
    echo
    echo "$ gcloud compute networks subnets create ilb-subnet-b --network ilb-net --region \$GCP_REGION --range 10.10.30.0/24 # to create subnet" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},2"
    echo
    echo "$ gcloud compute networks create ilb-net --subnet-mode custom # to create network" | pv -qL 100
    gcloud compute networks create ilb-net --subnet-mode custom
    echo
    echo "$ gcloud compute networks subnets create ilb-subnet-a --purpose INTERNAL_HTTPS_LOAD_BALANCER --role ACTIVE --region $GCP_REGION --network ilb-net --range 10.10.20.0/24 # to create subnet" | pv -qL 100
    gcloud compute networks subnets create ilb-subnet-a --purpose INTERNAL_HTTPS_LOAD_BALANCER --role ACTIVE --region $GCP_REGION --network ilb-net --range 10.10.20.0/24
    echo
    echo "$ gcloud compute networks subnets create ilb-subnet-b --network ilb-net --region $GCP_REGION --range 10.10.30.0/24 # to create subnet" | pv -qL 100
    gcloud compute networks subnets create ilb-subnet-b --network ilb-net --region $GCP_REGION --range 10.10.30.0/24
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},2x"
    echo
    echo "$ gcloud compute networks subnets delete ilb-subnet-b --region $GCP_REGION # to delete subnet" | pv -qL 100
    gcloud compute networks subnets delete ilb-subnet-b --region $GCP_REGION
    echo
    echo "$ gcloud compute networks subnets delete ilb-subnet-a --region $GCP_REGION # to delete subnet" | pv -qL 100
    gcloud compute networks subnets delete ilb-subnet-a --region $GCP_REGION
    echo
    echo "$ gcloud compute networks delete ilb-net # to delete network" | pv -qL 100
    gcloud compute networks delete ilb-net 
else
    export STEP="${STEP},2i"
    echo
    echo "1. Create network" | pv -qL 100
    echo "2. Create subnet" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"3")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},3i"
    echo
    echo "$ gcloud compute firewall-rules create ilb-allow-icmp --network ilb-net --source-ranges 0.0.0.0/0 --allow tcp:80 --target-tags lb-backend # to create HTTP firewall rule" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create ilb-allow-ssh-rdp --network ilb-net --source-ranges 0.0.0.0/0 --allow tcp:22,tcp:80,tcp:3389 --target-tags lb-backend # to create HTTP firewall rule" | pv -qL 100
    echo
    echo "$ gcloud compute firewall-rules create ilb-allow-health-check --network ilb-net --source-ranges 130.211.0.0/22,35.191.0.0/16 --allow tcp --target-tags lb-backend # to create HTTP firewall rule" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},3"
    echo
    echo "$ gcloud compute firewall-rules create ilb-allow-icmp --network ilb-net --source-ranges 0.0.0.0/0 --allow tcp:80 --target-tags lb-backend # to create HTTP firewall rule" | pv -qL 100
    gcloud compute firewall-rules create ilb-allow-icmp --network ilb-net --source-ranges 0.0.0.0/0 --allow tcp:80 --target-tags lb-backend
    echo
    echo "$ gcloud compute firewall-rules create ilb-allow-ssh-rdp --network ilb-net --source-ranges 0.0.0.0/0 --allow tcp:22,tcp:80,tcp:3389 --target-tags lb-backend # to create HTTP firewall rule" | pv -qL 100
    gcloud compute firewall-rules create ilb-allow-ssh-rdp --network ilb-net --source-ranges 0.0.0.0/0 --allow tcp:22,tcp:80,tcp:3389 --target-tags lb-backend
    echo
    echo "$ gcloud compute firewall-rules create ilb-allow-health-check --network ilb-net --source-ranges 130.211.0.0/22,35.191.0.0/16 --allow tcp --target-tags lb-backend # to create HTTP firewall rule" | pv -qL 100
    gcloud compute firewall-rules create ilb-allow-health-check --network ilb-net --source-ranges 130.211.0.0/22,35.191.0.0/16 --allow tcp --target-tags lb-backend
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},3x"
    echo
    echo "$ gcloud compute firewall-rules delete ilb-allow-icmp # to delete HTTP firewall rule" | pv -qL 100
    gcloud compute firewall-rules delete ilb-allow-icmp
    echo
    echo "$ gcloud compute firewall-rules delete ilb-allow-ssh-rdp # to delete HTTP firewall rule" | pv -qL 100
    gcloud compute firewall-rules delete ilb-allow-ssh-rdp
    echo
    echo "$ gcloud compute firewall-rules delete ilb-allow-health-check # to delete HTTP firewall rule" | pv -qL 100
    gcloud compute firewall-rules delete ilb-allow-health-check
else
    export STEP="${STEP},3i"
    echo
    echo "1. Create network" | pv -qL 100
    echo "2. Create subnet" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"4")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},4i"
    echo
    echo "$ gcloud compute instance-templates create ilb-instance-template-1 --region \$GCP_REGION --network ilb-net --subnet ilb-subnet-b --tags lb-backend --metadata startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh # to create instance template" | pv -qL 100
    echo
    echo "$ gcloud compute instance-templates create ilb-instance-template-2 --region \$GCP_REGION --network ilb-net --subnet ilb-subnet-b --tags lb-backend --metadata startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh # to create instance template" | pv -qL 100
    echo
    echo "$ gcloud beta compute instance-groups managed create ilb-instance-group-1 --template ilb-instance-template-1 --region \$GCP_REGION --size 1 # to create managed instance group # to create managed instance group" | pv -qL 100
    echo
    echo "$ gcloud beta compute instance-groups managed set-autoscaling ilb-instance-group-1 --region \$GCP_REGION --cool-down-period 45 --max-num-replicas 5 --min-num-replicas 1 --target-cpu-utilization 0.8 # to set autoscaling" | pv -qL 100 
    echo
    echo "$ gcloud beta compute instance-groups managed create ilb-instance-group-2 --template ilb-instance-template-2 --region \$GCP_REGION --size 1 # to create managed instance group # to create managed instance group" | pv -qL 100
    echo
    echo "$ gcloud beta compute instance-groups managed set-autoscaling ilb-instance-group-2 --region \$GCP_REGION --cool-down-period 45 --max-num-replicas 5 --min-num-replicas 1 --target-cpu-utilization 0.8 # to set autoscaling" | pv -qL 100 
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},4"
    echo
    echo "$ gcloud compute instance-templates create ilb-instance-template-1 --region $GCP_REGION --network ilb-net --subnet ilb-subnet-b --tags lb-backend --metadata startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh # to create instance template" | pv -qL 100
    gcloud compute instance-templates create ilb-instance-template-1 --region $GCP_REGION --network ilb-net --subnet ilb-subnet-b --tags lb-backend --metadata startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh # to create instance template
    echo
    echo "$ gcloud compute instance-templates create ilb-instance-template-2 --region $GCP_REGION --network ilb-net --subnet ilb-subnet-b --tags lb-backend --metadata startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh # to create instance template" | pv -qL 100
    gcloud compute instance-templates create ilb-instance-template-2 --region $GCP_REGION --network ilb-net --subnet ilb-subnet-b --tags lb-backend --metadata startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh
    echo
    echo "$ gcloud beta compute instance-groups managed create ilb-instance-group-1 --template ilb-instance-template-1 --region $GCP_REGION --size 1 # to create managed instance group" | pv -qL 100
    gcloud beta compute instance-groups managed create ilb-instance-group-1 --template ilb-instance-template-1 --region $GCP_REGION --size 1
    echo
    echo "$ gcloud beta compute instance-groups managed set-autoscaling ilb-instance-group-1 --region $GCP_REGION --cool-down-period 45 --max-num-replicas 5 --min-num-replicas 1 --target-cpu-utilization 0.8 # to set autoscaling" | pv -qL 100 
    gcloud beta compute instance-groups managed set-autoscaling ilb-instance-group-1 --region $GCP_REGION --cool-down-period 45 --max-num-replicas 5 --min-num-replicas 1 --target-cpu-utilization 0.8
    echo
    echo "$ gcloud beta compute instance-groups managed create ilb-instance-group-2 --template ilb-instance-template-2 --region $GCP_REGION --size 1 # to create managed instance group " | pv -qL 100
    gcloud beta compute instance-groups managed create ilb-instance-group-2 --template ilb-instance-template-2 --region $GCP_REGION --size 1
    echo
    echo "$ gcloud beta compute instance-groups managed set-autoscaling ilb-instance-group-2 --region $GCP_REGION --cool-down-period 45 --max-num-replicas 5 --min-num-replicas 1 --target-cpu-utilization 0.8 # to set autoscaling" | pv -qL 100 
    gcloud beta compute instance-groups managed set-autoscaling ilb-instance-group-2 --region $GCP_REGION --cool-down-period 45 --max-num-replicas 5 --min-num-replicas 1 --target-cpu-utilization 0.8
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},4x"
    echo
    echo "$ gcloud beta compute instance-groups managed delete ilb-instance-group-2 --region $GCP_REGION # to delete managed instance group" | pv -qL 100
    gcloud beta compute instance-groups managed delete ilb-instance-group-2 --region $GCP_REGION 
    echo
    echo "$ gcloud beta compute instance-groups managed delete ilb-instance-group-1 --region $GCP_REGION # to delete managed instance group" | pv -qL 100
    gcloud beta compute instance-groups managed delete ilb-instance-group-1 --region $GCP_REGION
    echo
    echo "$ gcloud compute instance-templates delete ilb-instance-template-2 # to delete instance template" | pv -qL 100
    gcloud compute instance-templates delete ilb-instance-template-2
    echo
    echo "$ gcloud compute instance-templates delete ilb-instance-template-1 # to delete instance template" | pv -qL 100
    gcloud compute instance-templates delete ilb-instance-template-1
else
    export STEP="${STEP},4i"
    echo
    echo "1. Create instance template" | pv -qL 100
    echo "2. Create managed instance group" | pv -qL 100
    echo "3. Set autoscaling" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"5")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},5i"
    echo
    echo "$ gcloud compute instances create ilb-utility-vm --zone \$GCP_ZONE --network-interface network=ilb-net,subnet=ilb-subnet-b,private-network-ip=10.10.30.50 --tags lb-backend --provisioning-model=SPOT # to create load testing instance" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},5"
    echo
    echo "$ gcloud compute instances create ilb-utility-vm --zone $GCP_ZONE --network-interface network=ilb-net,subnet=ilb-subnet-b,private-network-ip=10.10.30.50 --tags lb-backend --provisioning-model=SPOT # to create load testing instance" | pv -qL 100
    gcloud compute instances create ilb-utility-vm --zone $GCP_ZONE --network-interface network=ilb-net,subnet=ilb-subnet-b,private-network-ip=10.10.30.50 --tags lb-backend --provisioning-model=SPOT
    echo
    sleep 30
    export IPV4=$(gcloud compute instance-groups list-instances ilb-instance-group-1 --region $GCP_REGION --uri | xargs -I '{}' gcloud compute instances describe  '{}'  --flatten networkInterfaces[].accessConfigs[]  --format 'csv[no-heading](networkInterfaces.accessConfigs.natIP)') 
    echo "$ gcloud compute ssh --quiet --zone $GCP_ZONE ilb-utility-vm --command=\"curl http://$IPV4\" # to request endpoint" | pv -qL 100
    gcloud compute ssh --quiet --zone $GCP_ZONE ilb-utility-vm --command="curl http://$IPV4"
    echo
    export IPV4=$(gcloud compute instance-groups list-instances ilb-instance-group-2 --region $GCP_REGION --uri | xargs -I '{}' gcloud compute instances describe  '{}'  --flatten networkInterfaces[].accessConfigs[]  --format 'csv[no-heading](networkInterfaces.accessConfigs.natIP)')     
    echo "$ gcloud compute ssh --quiet --zone $GCP_ZONE ilb-utility-vm --command=\"curl http://$IPV4\" # to request endpoint" | pv -qL 100
    gcloud compute ssh --quiet --zone $GCP_ZONE ilb-utility-vm --command="curl http://$IPV4"
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},5x"
    echo
    echo "$ gcloud compute instances delete ilb-utility-vm --zone $GCP_ZONE # to delete load testing instance" | pv -qL 100
    gcloud compute instances delete ilb-utility-vm --zone $GCP_ZONE
else
    export STEP="${STEP},5i"
    echo
    echo "1. Create load testing instance" | pv -qL 100
    echo "2. Invoke endpoint" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"6")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},6i"
    echo
    echo "$ gcloud compute instance-groups managed set-named-ports ilb-instance-group-1 --named-ports http:80 --region \$GCP_REGION # to set port" | pv -qL 100
    echo
    echo "$ gcloud compute instance-groups managed set-named-ports ilb-instance-group-2 --named-ports http:80 --region \$GCP_REGION # to set port" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},6"
    echo
    echo "$ gcloud compute instance-groups managed set-named-ports ilb-instance-group-1 --named-ports http:80 --region $GCP_REGION # to set port" | pv -qL 100
    gcloud compute instance-groups managed set-named-ports ilb-instance-group-1 --named-ports http:80 --region $GCP_REGION
    echo
    echo "$ gcloud compute instance-groups managed set-named-ports ilb-instance-group-2 --named-ports http:80 --region $GCP_REGION # to set port" | pv -qL 100
    gcloud compute instance-groups managed set-named-ports ilb-instance-group-2 --named-ports http:80 --region $GCP_REGION
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},6x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},6i"
    echo
    echo "1. Set port" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"7")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},7i"
    echo
    echo "$ gcloud compute health-checks create http ilb-http-health-check --region \$GCP_REGION --use-serving-port # to create healthcheck" | pv -qL 100
    echo
    echo "$ gcloud compute backend-services create ilb-backend-service --load-balancing-scheme=INTERNAL_MANAGED --protocol HTTP --health-checks ilb-http-health-check --health-checks-region \$GCP_REGION --region \$GCP_REGION # to create backend service" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},7"
    echo
    echo "$ gcloud compute health-checks create http ilb-http-health-check --region $GCP_REGION --use-serving-port # to create healthcheck" | pv -qL 100
    gcloud compute health-checks create http ilb-http-health-check --region $GCP_REGION --use-serving-port
    echo
    echo "$ gcloud compute backend-services create ilb-backend-service --load-balancing-scheme=INTERNAL_MANAGED --protocol HTTP --health-checks ilb-http-health-check --health-checks-region $GCP_REGION --region $GCP_REGION # to create backend service" | pv -qL 100
    gcloud compute backend-services create ilb-backend-service --load-balancing-scheme=INTERNAL_MANAGED --protocol HTTP --health-checks ilb-http-health-check --health-checks-region $GCP_REGION --region $GCP_REGION
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},7x"
    echo
    echo "$ gcloud compute backend-services delete ilb-backend-service --region $GCP_REGION # to delete backend service" | pv -qL 100
    gcloud compute backend-services delete ilb-backend-service --region $GCP_REGION
else
    export STEP="${STEP},7i"
    echo
    echo "1. Create healthcheck" | pv -qL 100
    echo "2. Create backend service" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"8")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},8i"
    echo
    echo "$ gcloud compute backend-services add-backend ilb-backend-service --balancing-mode RATE --max-rate-per-instance 50 --capacity-scaler 1.0 --instance-group ilb-instance-group-1 --instance-group-region \$GCP_REGION --region \$GCP_REGION # to create backend services" | pv -qL 100
    echo
    echo "$ gcloud compute backend-services add-backend ilb-backend-service --balancing-mode RATE --max-rate-per-instance 50 --capacity-scaler 1.0 --instance-group ilb-instance-group-2 --instance-group-region \$GCP_REGION --region \$GCP_REGION # to create backend services" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},8"
    echo
    echo "$ gcloud compute backend-services add-backend ilb-backend-service --balancing-mode RATE --max-rate-per-instance 50 --capacity-scaler 1.0 --instance-group ilb-instance-group-1 --instance-group-region $GCP_REGION --region $GCP_REGION # to create backend services" | pv -qL 100
    gcloud compute backend-services add-backend ilb-backend-service --balancing-mode RATE --max-rate-per-instance 50 --capacity-scaler 1.0 --instance-group ilb-instance-group-1 --instance-group-region $GCP_REGION --region $GCP_REGION
    echo
    echo "$ gcloud compute backend-services add-backend ilb-backend-service --balancing-mode RATE --max-rate-per-instance 50 --capacity-scaler 1.0 --instance-group ilb-instance-group-2 --instance-group-region $GCP_REGION --region $GCP_REGION # to create backend services" | pv -qL 100
    gcloud compute backend-services add-backend ilb-backend-service --balancing-mode RATE --max-rate-per-instance 50 --capacity-scaler 1.0 --instance-group ilb-instance-group-2 --instance-group-region $GCP_REGION --region $GCP_REGION
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},8x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},7i"
    echo
    echo "1. Create backend services" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"9")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},9i"
    echo
    echo "$ gcloud compute url-maps create ilb-url-map --default-service ilb-backend-service --region \$GCP_REGION # to create URL maps" | pv -qL 100
    echo
    echo "$ gcloud compute url-maps add-path-matcher ilb-url-map --path-matcher-name ilb-url-map-path --region \$GCP_REGION --default-service ilb-backend-service --path-rules=\"/=ilb-backend-service\" # to add a path matcher to URL map" | pv -qL 100
    echo
    echo "$ gcloud compute target-http-proxies create ilb-target-http-proxy --url-map ilb-url-map --url-map-region \$GCP_REGION --region \$GCP_REGION # to create a target HTTP proxy to route requests to URL map" | pv -qL 100
    echo
    echo "$ gcloud compute forwarding-rules create ilb-forwarding-rule --load-balancing-scheme=INTERNAL_MANAGED --address 10.10.30.10 --target-http-proxy ilb-target-http-proxy --ports 80 --region \$GCP_REGION --subnet ilb-subnet-b --target-http-proxy-region \$GCP_REGION # to create IPV4 global forwarding rule" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},9"
    echo
    echo "$ gcloud compute url-maps create ilb-url-map --default-service ilb-backend-service --region $GCP_REGION # to create URL maps" | pv -qL 100
    gcloud compute url-maps create ilb-url-map --default-service ilb-backend-service --region $GCP_REGION
    echo
    echo "$ gcloud compute url-maps add-path-matcher ilb-url-map --path-matcher-name ilb-url-map-path --region $GCP_REGION --default-service ilb-backend-service --path-rules=\"/=ilb-backend-service\" # to add a path matcher to URL map" | pv -qL 100
    gcloud compute url-maps add-path-matcher ilb-url-map --path-matcher-name ilb-url-map-path --region $GCP_REGION --default-service ilb-backend-service --path-rules="/=ilb-backend-service"
    echo
    echo "$ gcloud compute target-http-proxies create ilb-target-http-proxy --url-map ilb-url-map --url-map-region $GCP_REGION --region $GCP_REGION # to create a target HTTP proxy to route requests to URL map" | pv -qL 100
    gcloud compute target-http-proxies create ilb-target-http-proxy --url-map ilb-url-map --url-map-region $GCP_REGION --region $GCP_REGION 
    echo
    echo "$ gcloud compute forwarding-rules create ilb-forwarding-rule --load-balancing-scheme=INTERNAL_MANAGED --address 10.10.30.10 --target-http-proxy ilb-target-http-proxy --ports 80 --region $GCP_REGION --subnet ilb-subnet-b --target-http-proxy-region $GCP_REGION # to create IPV4 global forwarding rule" | pv -qL 100
    gcloud compute forwarding-rules create ilb-forwarding-rule --load-balancing-scheme=INTERNAL_MANAGED --address 10.10.30.10 --target-http-proxy ilb-target-http-proxy --ports 80 --region $GCP_REGION --subnet ilb-subnet-b --target-http-proxy-region $GCP_REGION
    sleep 60
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},9x"
    echo
    echo "$ gcloud compute forwarding-rules delete ilb-forwarding-rule --region $GCP_REGION # to delete IPV4 global forwarding rule" | pv -qL 100
    gcloud compute forwarding-rules delete ilb-forwarding-rule --region $GCP_REGION 
    echo
    echo "$ gcloud compute target-http-proxies delete ilb-target-http-proxy --region $GCP_REGION # to delete a target HTTP proxy to route requests to URL map" | pv -qL 100
    gcloud compute target-http-proxies delete ilb-target-http-proxy --region $GCP_REGION 
    echo
    echo "$ gcloud compute url-maps delete ilb-url-map --region $GCP_REGION # to delete URL maps" | pv -qL 100
    gcloud compute url-maps delete ilb-url-map --region $GCP_REGION
else
    export STEP="${STEP},9i"
    echo
    echo "1. Create URL maps" | pv -qL 100
    echo "2. Add a path matcher to URL map" | pv -qL 100
    echo "3. Create target HTTP proxy to route requests to URL map" | pv -qL 100
    echo "4. Create IPV4 global forwarding rule" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"10")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},10i"
    echo
    echo "$ gcloud compute ssh --quiet --zone \$GCP_ZONE ilb-utility-vm --command=\"curl http://10.10.30.10\" # to request endpoint" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},10"
    echo
    echo "$ gcloud compute ssh --quiet --zone $GCP_ZONE ilb-utility-vm --command=\"curl http://10.10.30.10\" # to request endpoint" | pv -qL 100
    gcloud compute ssh --quiet --zone $GCP_ZONE ilb-utility-vm --command="curl http://10.10.30.10"
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},10x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},10i"
    echo
    echo "1. Request endpoint" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"11")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},11i"
    echo
    echo "$ gcloud compute firewall-rules create allow-ssh-ingress-from-iap --direction=INGRESS --action=allow --rules=tcp:22 --source-ranges=35.235.240.0/20 --quiet # to allow SSH access" | pv -qL 100
    echo
    echo "$ gcloud alpha iap oauth-brands create --application_title=ilb-net --support_email=\$(gcloud config get-value core/account) # to create brand" | pv -qL 100
    echo
    echo "$ gcloud alpha iap oauth-clients create \$BRAND_ID --display_name=ilb-net # to create a brand" | pv -qL 100
    echo
    echo "$ gcloud projects add-iam-policy-binding \$GCP_PROJECT --member=user:\$USER_EMAIL --role=roles/iap.tunnelResourceAccessor # to add a user to the access policy for IAP" | pv -qL 100
    echo
    echo "$ gcloud compute ssh ilb-utility-vm --tunnel-through-iap --zone \$GCP_ZONE # to connect to instance" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},11"
    echo
    echo "$ gcloud compute firewall-rules create allow-ssh-ingress-from-iap --direction=INGRESS --action=allow --rules=tcp:22 --source-ranges=35.235.240.0/20 --quiet # to allow SSH access" | pv -qL 100
    gcloud compute firewall-rules create allow-ssh-ingress-from-iap --direction=INGRESS --action=allow --rules=tcp:22 --source-ranges=35.235.240.0/20 --quiet
    export BRAND_NAME=$(gcloud alpha iap oauth-brands list --format="value(name)") > /dev/null 2>&1
    if [ -z "$BRAND_NAME" ]
    then
        echo
        echo "$ gcloud alpha iap oauth-brands create --application_title=ilb-net --support_email=$(gcloud config get-value core/account) # to create brand" | pv -qL 100
        gcloud alpha iap oauth-brands create --application_title=ilb-net --support_email=$(gcloud config get-value core/account)
        sleep 10
        export BRAND_ID=$(gcloud alpha iap oauth-brands list --format="value(name)") > /dev/null 2>&1 # to set brand ID
    else
        export BRAND_ID=$(gcloud alpha iap oauth-brands list --format="value(name)") > /dev/null 2>&1 # to set brand ID
    fi
    export CLIENT_LIST=$(gcloud alpha iap oauth-clients list $BRAND_ID) > /dev/null 2>&1

    if [ -z "$CLIENT_LIST" ]
    then
        echo
        echo "$ gcloud alpha iap oauth-clients create $BRAND_ID --display_name=ilb-net # to create a brand" | pv -qL 100
        gcloud alpha iap oauth-clients create $BRAND_ID --display_name=ilb-net
        sleep 10
        export CLIENT_ID=$(gcloud alpha iap oauth-clients list $BRAND_ID --format="value(name)" | awk -F/ '{print $NF}') # to set client ID
        export CLIENT_SECRET=$(gcloud alpha iap oauth-clients list $BRAND_ID --format="value(secret)") # to set secret
    else
        export CLIENT_ID=$(gcloud alpha iap oauth-clients list $BRAND_ID --format="value(name)" | awk -F/ '{print $NF}') # to set client ID
        export CLIENT_SECRET=$(gcloud alpha iap oauth-clients list $BRAND_ID --format="value(secret)") # to set secret
    fi
    echo
    echo "$ gcloud projects add-iam-policy-binding $GCP_PROJECT --member=user:\$(gcloud config get-value core/account) --role=roles/iap.tunnelResourceAccessor # to add a user to the access policy for IAP"
    gcloud projects add-iam-policy-binding $GCP_PROJECT --member=user:$(gcloud config get-value core/account) --role=roles/iap.tunnelResourceAccessor
    echo
    echo "*** TYPE COMMAND \"exit\" TO EXIT ilb-utility-vm VIRTUAL MACHINE SHELL AND RETURN TO PROMPT ***"
    echo
    echo "$ gcloud compute ssh ilb-utility-vm --tunnel-through-iap --zone $GCP_ZONE # to connect to instance"
    gcloud compute ssh ilb-utility-vm --tunnel-through-iap --zone $GCP_ZONE
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},11x"
    echo
    echo "$ gcloud projects remove-iam-policy-binding $GCP_PROJECT --member=user:\$(gcloud config get-value core/account) --role=roles/iap.tunnelResourceAccessor # to revoke policy for IAP" | pv -qL 100
    gcloud projects remove-iam-policy-binding $GCP_PROJECT --member=user:$(gcloud config get-value core/account) --role=roles/iap.tunnelResourceAccessor
    echo
    echo "$ gcloud compute firewall-rules delete allow-ssh-ingress-from-iap # to delete firewall rule" | pv -qL 100
    gcloud compute firewall-rules delete allow-ssh-ingress-from-iap 
else
    export STEP="${STEP},11i"
    echo
    echo "1. Create firewall to allow SSH access" | pv -qL 100
    echo "2. Create oauth brand" | pv -qL 100
    echo "3. Configure client ID and secret" | pv -qL 100
    echo "4. Add user to IAP access policy" | pv -qL 100
    echo "5. Connect to instance via IAP" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"R")
echo
echo "
  __                      __                              __                               
 /|            /         /              / /              /                 | /             
( |  ___  ___ (___      (___  ___        (___           (___  ___  ___  ___|(___  ___      
  | |___)|    |   )     |    |   )|   )| |    \   )         )|   )|   )|   )|   )|   )(_/_ 
  | |__  |__  |  /      |__  |__/||__/ | |__   \_/       __/ |__/||  / |__/ |__/ |__/  / / 
                                 |              /                                          
"
echo "
We are a group of information technology professionals committed to driving cloud 
adoption. We create cloud skills development assets during our client consulting 
engagements, and use these assets to build cloud skills independently or in partnership 
with training organizations.
 
You can access more resources from our iOS and Android mobile applications.

iOS App: https://apps.apple.com/us/app/tech-equity/id1627029775
Android App: https://play.google.com/store/apps/details?id=com.techequity.app

Email:support@techequity.cloud 
Web: https://techequity.cloud

Ⓒ Tech Equity 2022" | pv -qL 100
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"G")
cloudshell launch-tutorial $SCRIPTPATH/.tutorial.md
;;

"Q")
echo
exit
;;
"q")
echo
exit
;;
* )
echo
echo "Option not available"
;;
esac
sleep 1
done
