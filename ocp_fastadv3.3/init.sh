#!/bin/bash
################################################################################
################################################################################
# This Script will be used to deploy the OSE_FastAdv and OSE_Demo blueprints
# This is a temporary method until we do this properly with Ansible playbooks.
# Steps in the scripts are:
## Step 0 - Define variables for deployment.
## Step 1 - Prepare environment and test that all hosts are up
## Step 2 - Install OpenShift
## Step 3 - Post-Configure OpenShift (Metrics, Logging)
## Step 4 - Demo content deployment
################################################################################
################################################################################


################################################################################
## Step 0 - Define variables for deployment.
################################################################################
#OPENTLC VARS
export LOGFILE="/root/.oselab.log"
export USER=$1
#export USER="shacharb-redhat.com"
export COURSE=$2;
#export COURSE="ocp_fastadv3.3"
export METRICS="FALSE"
export LOGGING="FALSE"


################################################################################
## Step 1 - Prepare environemnt and test that all hosts are up
################################################################################
echo "---- Step 1 - Prepare environemnt and test that all hosts are up"  2>&1 | tee -a $LOGFILE


echo "-- Updating /etc/motd"  2>&1 | tee -a $LOGFILE

cat << EOF > /etc/motd
###############################################################################
###############################################################################
###############################################################################
Environment Deployment In Progress : ${DATE}
DO NOT USE THIS ENVIRONMENT AT THIS POINT
DISCONNECT AND TRY AGAIN 35 MINUTES FROM THE DATE ABOVE
###############################################################################
###############################################################################
If you want, you can check out the status of the installer by using:
sudo tail -f ${LOGFILE}
###############################################################################

EOF

echo "ansible-playbook -i /root/.opentlc_deployer/${COURSE}/ansible/files/opentlc.hosts /root/.opentlc_deployer/${COURSE}/ansible/main.yml"   2>&1 | tee -a $LOGFILE

ansible-playbook -i /root/.opentlc_deployer/${COURSE}/ansible/files/opentlc.hosts /root/.opentlc_deployer/${COURSE}/ansible/main.yml   2>&1 | tee -a $LOGFILE


## WORKAROUND
sed -i '/registry/s/^/#/' /etc/exports


################################################################################
## Step 2 - install openshift
################################################################################
echo "---- Step 2 - install openshift"  2>&1 | tee -a $LOGFILE
export HOME="/root"
echo "ansible-playbook -i /etc/ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml"  2>&1 | tee -a $LOGFILE
ansible-playbook -i /etc/ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml   2>&1 | tee -a $LOGFILE

################################################################################
## Step 3 - Post-Configure OpenShift (Metrics, Logging)
################################################################################
## This will get a done with playbooks later
echo "---- Step 3 - Post-Configure OpenShift (Metrics, Logging)"  2>&1 | tee -a $LOGFILE
echo "-- Get the openshift_toolkit repo to deploy METRICS and LOGGING"  2>&1 | tee -a $LOGFILE

scp -r master1.example.com:/root/.kube /root/.kube  2>&1 | tee -a $LOGFILE

if [ $METRICS == "TRUE" ]
  then
    echo "Running Ansible playbook for Metrics, logs to ${LOGFILE}.metrics" | tee -a $LOGFILE
    oc project openshift-infra
    oc create -f - <<API
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: metrics-deployer
    secrets:
    - name: metrics-deployer
API
  oadm policy add-role-to-user edit system:serviceaccount:openshift-infra:metrics-deployer
  oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:openshift-infra:heapster
  oc secrets new metrics-deployer nothing=/dev/null
  oc new-app openshift/metrics-deployer-template -p HAWKULAR_METRICS_HOSTNAME=metrics.cloudapps-${GUID}.oslab.opentlc.com -p USE_PERSISTENT_STORAGE=false -p IMAGE_VERSION=3.3.0 -p IMAGE_PREFIX=registry.access.redhat.com/openshift3/
  oc project default

fi

echo "-- Check pods in the openshift-infra project"  2>&1 | tee -a $LOGFILE
oc get pods -n openshift-infra  -o wide  2>&1 | tee -a $LOGFILE

echo "-- set the current context to the default project"  2>&1 | tee -a $LOGFILE
oc project default  2>&1 | tee -a $LOGFILE

if [ $LOGGING == "TRUE" ]
 then
   ssh master1.example.com "oc apply -n openshift -f     /usr/share/openshift/examples/infrastructure-templates/enterprise/logging-deployer.yaml"

   oadm new-project logging --node-selector=""
   oc project logging
   oc new-app logging-deployer-account-template
   oadm policy add-cluster-role-to-user oauth-editor        system:serviceaccount:logging:logging-deployer
   oadm policy add-scc-to-user privileged      system:serviceaccount:logging:aggregated-logging-fluentd
   oadm policy add-cluster-role-to-user cluster-reader     system:serviceaccount:logging:aggregated-logging-fluentd
   oc new-app logging-deployer-template --param PUBLIC_MASTER_URL=https://master1-${GUID}.oslab.opentlc.com:8443 --param KIBANA_HOSTNAME=kibana.cloudapps-${GUID}.oslab.opentlc.com --param IMAGE_VERSION=3.3.0 --param IMAGE_PREFIX=registry.access.redhat.com/openshift3/        --param KIBANA_NODESELECTOR='region=infra' --param ES_NODESELECTOR='region=infra' --param MODE=install
   oc label nodes --all logging-infra-fluentd=true
   oc label node master1.example.com --overwrite logging-infra-fluentd=false
   oc project default

 fi




echo "-- Update /etc/motd"  2>&1 | tee -a $LOGFILE

cat << EOF > /etc/motd
###############################################################################
Environment Deployment Started      : ${DATE}
###############################################################################
###############################################################################
Environment Deployment Is Completed : `date`
###############################################################################
###############################################################################

EOF



################################################################################
## Step4 - Demo content deployment
################################################################################
echo "---- Step 4 - Demo content deployment"  2>&1 | tee -a $LOGFILE

if [ $DEMO == "TRUE" ]
  then
echo "-- Running /root/.opentlc.installer/Demo_Deployment_Script.sh"  2>&1 | tee -a $LOGFILE
chmod +x /root/.opentlc_deployer/${COURSE}/ansible/scripts/Demo_Deployment_Script.sh
/root/.opentlc_deployer/${COURSE}/ansible/scripts/Demo_Deployment_Script.sh 2>&1 | tee -a /root/.Demo.Deployment.log
echo "-- Finished running /root/.opentlc_deployer/${COURSE}/ansible/files/Demo_Deployment_Script.sh"  2>&1 | tee -a $LOGFILE
fi

fi
echo "-- Update /etc/motd"  2>&1 | tee -a $LOGFILE

cat << EOF >> /etc/motd
###############################################################################
Demo Materials Deployment Completed : `date`
###############################################################################
EOF

echo "-- Update /etc/motd on all nodes"  2>&1 | tee -a $LOGFILE
ansible all -l masters,nodes,etcd  -m copy -a "src=/etc/motd dest=/etc/motd"
