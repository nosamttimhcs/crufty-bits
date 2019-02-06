#!/bin/bash

#############################################################
# When building the host, make sure to set:
#  * Static IP and gateway
#  * Nameserver IP that you want to use as your forwarder
#  * FQDN hostname
#############################################################

# At which stage should the install script start?
# This allows for incremental development of the script, without having to comment out huge sections
STAGE="$1"
if [ -z "$STAGE" ]; then
   echo "Please supply a stage as an argument to the script"
   exit
fi

# Variables for tailoring this script to a specific network

PRIMARY_INTERFACE=$(ip route list | grep default | awk '{print $5}')
IP=$(ip addr show dev $PRIMARY_INTERFACE | grep 'inet ' | awk '{print $2}' | awk -F'/' '{print $1}')
HOSTNAME=$(hostname --short)
FQDN=$(hostname --fqdn)
DOMAIN=$(hostname --domain)
DEFAULT_GW=$(ip route list | grep default | awk '{print $3}')
REVERSE_ZONE=$(echo $IP | awk -F. '{print $3"." $2"." $1".in-addr.arpa"}')
FORWARDERS=$(grep nameserver /etc/resolv.conf | awk '{print $2}')
ANSWER_FILE='/etc/foreman-installer/scenarios.d/katello-answers.yaml'
TODAY=$(date +%Y-%m-%d)

source local.conf

function install_katello {
   # Install a few admin tools that I like to have around
   yum install -y vim net-tools bind-utils mtr mlocate

   # Disable the firewall for now (just during testing)
   systemctl stop firewalld
   systemctl disable firewalld

   # Add IP and hostname to /etc/hosts
   echo "$IP   $FQDN   $HOSTNAME" >> /etc/hosts

   # Configure katello, foreman, puppet and EPEL repos
   yum -y install https://fedorapeople.org/groups/katello/releases/yum/3.10/katello/el7/x86_64/katello-repos-latest.rpm
   yum -y install http://yum.theforeman.org/releases/1.20/el7/x86_64/foreman-release.rpm
   yum -y install https://yum.puppetlabs.com/puppet5/puppet5-release-el-7.noarch.rpm
   yum -y install http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

   # Install a couple required prerequisite packages
   yum -y install foreman-release-scl python2-django

   # Install packages needed for later in this script
   yum install -y jq

   # Update all the packages!
   yum -y update

   # Install katello
   yum -y install katello
}

function foreman-install_first_run {
   # Replace default answer file with mine
   mv /etc/foreman-installer/scenarios.d/katello-answers.yaml /etc/foreman-installer/scenarios.d/katello-answers.yaml.orig
   cat << EOF > $ANSWER_FILE
# Format:
# <classname>: false - don't include this class
# <classname>: true - include and use the defaults
# <classname>:
#   <param>: <value> - include and override the default(s)
#
# See params.pp in each class for what options are available

---
certs:
  generate: true
  deploy: true
  group: foreman
katello:
  package_names:
  - katello
  - tfm-rubygem-katello
foreman:
  organizations_enabled: true
  locations_enabled: true
  initial_organization: Default Organization
  initial_location: Default Location
  custom_repo: true
  configure_epel_repo: false
  configure_scl_repo: false
  max_keepalive_requests: 10000
  ssl: true
  server_ssl_cert: /etc/pki/katello/certs/katello-apache.crt
  server_ssl_key: /etc/pki/katello/private/katello-apache.key
  server_ssl_ca: /etc/pki/katello/certs/katello-default-ca.crt
  server_ssl_chain: /etc/pki/katello/certs/katello-server-ca.crt
  server_ssl_crl: ''
  client_ssl_cert: /etc/foreman/client_cert.pem
  client_ssl_key: /etc/foreman/client_key.pem
  client_ssl_ca: /etc/foreman/proxy_ca.pem
  websockets_encrypt: true
  websockets_ssl_key: /etc/pki/katello/private/katello-apache.key
  websockets_ssl_cert: /etc/pki/katello/certs/katello-apache.crt
  passenger_ruby: /usr/bin/tfm-ruby
  passenger_ruby_package: tfm-rubygem-passenger-native
  keepalive: true
foreman_proxy_content:
  pulp_master: true
  qpid_router_broker_addr: localhost
puppet:
  server: true
  server_environments_owner: apache
  server_foreman_ssl_ca: /etc/pki/katello/puppet/puppet_client_ca.crt
  server_foreman_ssl_cert: /etc/pki/katello/puppet/puppet_client.crt
  server_foreman_ssl_key: /etc/pki/katello/puppet/puppet_client.key
foreman_proxy:
  custom_repo: true
  http: true
  ssl_port: '9090'
  templates: true
  ssl_ca: /etc/foreman-proxy/ssl_ca.pem
  ssl_cert: /etc/foreman-proxy/ssl_cert.pem
  ssl_key: /etc/foreman-proxy/ssl_key.pem
  foreman_ssl_ca: /etc/foreman-proxy/foreman_ssl_ca.pem
  foreman_ssl_cert: /etc/foreman-proxy/foreman_ssl_cert.pem
  foreman_ssl_key: /etc/foreman-proxy/foreman_ssl_key.pem
  use_autosignfile: true
  manage_puppet_group: false
foreman_proxy::plugin::pulp:
  enabled: true
  pulpnode_enabled: false
foreman::plugin::ansible: false
foreman::plugin::bootdisk: false
foreman::plugin::chef: false
foreman::plugin::default_hostgroup: false
foreman::plugin::dhcp_browser: true
foreman::plugin::discovery: true
foreman::plugin::docker: true
foreman::plugin::hooks: true
foreman::plugin::openscap: true
foreman::plugin::puppetdb: false
foreman::plugin::remote_execution: true
foreman::plugin::setup: false
foreman::plugin::tasks: true
foreman::plugin::templates: false
foreman_proxy::plugin::ansible: false
foreman_proxy::plugin::chef: false
foreman_proxy::plugin::dhcp::infoblox: false
foreman_proxy::plugin::dns::infoblox: false
foreman_proxy::plugin::dynflow: true
foreman_proxy::plugin::openscap: true
foreman_proxy::plugin::remote_execution::ssh: true
foreman_proxy::plugin::discovery: true
foreman::compute::ec2: false
foreman::compute::gce: false
foreman::compute::libvirt: true
foreman::compute::openstack: false
foreman::compute::ovirt: false
foreman::compute::rackspace: false
foreman::compute::vmware: false
foreman::cli: true
foreman::cli::openscap: true
foreman::cli::discovery: true
foreman::cli::tasks: true
foreman::cli::templates: false
foreman::cli::remote_execution: true
EOF

   # Update the default Org and Location
   sed -i -e "s/Default Organization/$DEFAULT_ORG/" -e "s/Default Location/$DEFAULT_LOC/" $ANSWER_FILE

   # First run of the foreman-installer using our answer file
   foreman-installer --scenario katello |& tee -a /root/foreman-installer-first_run.log

### Rather than modify the answer file, I just discovered that individual plugins can be enabled
### by passing options to the installer - https://theforeman.org/manuals/1.20/index.html#3.2.2InstallerOptions
### For example, the following command would install Foreman, Katello and the discovery plugin
###   foreman-installer --scenario katello \
###   --enable-foreman-plugin-discovery \
###   --enable-foreman-cli-discovery \
###   --enable-foreman-proxy-plugin-discovery
### I should incorporate this into a new version of this script
}

function foreman-install_second_run {
   # Grab the oauth credentials that were generated from the first run
   OAUTH_KEY=$(grep oauth_consumer_key /etc/foreman/settings.yaml | awk '{print $2}')
   OAUTH_SECRET=$(grep oauth_consumer_secret /etc/foreman/settings.yaml | awk '{print $2}')

   # Re-run foreman-installer to setup DNS, DHCP and TFTP
   foreman-installer --scenario katello \
   --enable-foreman-proxy \
   --foreman-proxy-tftp=true \
   --foreman-proxy-tftp-servername=$IP \
   --foreman-proxy-dhcp=true \
   --foreman-proxy-dhcp-interface=$PRIMARY_INTERFACE \
   --foreman-proxy-dhcp-gateway=$DEFAULT_GW \
   --foreman-proxy-dhcp-nameservers="$IP" \
   --foreman-proxy-dns=true \
   --foreman-proxy-dns-interface=$PRIMARY_INTERFACE \
   --foreman-proxy-dns-zone=$DOMAIN \
   --foreman-proxy-dns-reverse=$REVERSE_ZONE \
   --foreman-proxy-dns-forwarders=$FORWARDERS \
   --foreman-proxy-foreman-base-url=https://$FQDN \
   --foreman-proxy-oauth-consumer-key=$OAUTH_KEY \
   --foreman-proxy-oauth-consumer-secret=$OAUTH_SECRET \
    |& tee -a /root/foreman-installer-second_run.log

   # Now that a local DNS server has been setup, change the nameserver in /etc/resolv.conf
   sed -i "s/$FORWARDERS/127.0.0.1/" /etc/resolv.conf
}

function initial_full_backup {
   ##########################################
   # Backup the initial state of the system #
   ##########################################

   # Create backup directory and set correct permissions
   BACKUP_DIR_FULL='/tmp/backups/full'
   BACKUP_DIR_INCREMENTAL='/tmp/backups/incremental'
   mkdir -p $BACKUP_DIR_FULL
   mkdir -p $BACKUP_DIR_INCREMENTAL
   chmod 775 $BACKUP_DIR_FULL
   chmod 775 $BACKUP_DIR_INCREMENTAL
   chown foreman:postgres $BACKUP_DIR_FULL
   chown foreman:postgres $BACKUP_DIR_INCREMENTAL

   # Backup Foreman and Katello
   foreman-maintain backup offline --preserve-directory --features all --include-db-dumps -y /tmp/backups/full
}

function incremental_backup {
   # Incremental backup of Foreman and Katello
   foreman-maintain backup offline --preserve-directory --features all --include-db-dumps -y --incremental /tmp/backups/full /tmp/backups/incremental
}

function archival_backup {
   # Incremental backup of Foreman and Katello
   foreman-maintain backup offline --features all --include-db-dumps -y /tmp/backups/archive
}

function create_products {
   #############################################
   # Set some defaults for Foreman and Katello #
   #############################################

   # Set default Organizatino and Location
   hammer defaults add --param-name organization --param-value "$DEFAULT_ORG"
   hammer defaults add --param-name location --param-value "$DEFAULT_LOC"


   ##############################
   ## Setup Products in Katello #
   ##############################

   # Create temp import dir for gpg keys
   GPG_IMPORT_DIR='/tmp/gpg_keys'
   mkdir -p $GPG_IMPORT_DIR
   cd $GPG_IMPORT_DIR

   # Define the keys that I'm going to need
   CENTOS_KEY_URL='https://www.centos.org/keys/RPM-GPG-KEY-CentOS-7'
   CENTOS_GPG_KEY=${CENTOS_KEY_URL##*/}
   CENTOS_KEY_NAME="$CENTOS_GPG_KEY"
   EPEL_KEY_URL='https://mirror.csclub.uwaterloo.ca/fedora/epel/RPM-GPG-KEY-EPEL-7'
   EPEL_GPG_KEY=${EPEL_KEY_URL##*/}
   EPEL_KEY_NAME="$EPEL_GPG_KEY"
   PUPPETLABS_KEY_URL='https://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs'
   PUPPETLABS_GPG_KEY=${PUPPETLABS_KEY_URL##*/}
   PUPPETLABS_KEY_NAME="$PUPPETLABS_GPG_KEY"
   KATELLO_KEY_URL='http://yum.theforeman.org/RPM-GPG-KEY-foreman'
   KATELLO_GPG_KEY=${KATELLO_KEY_URL##*/}
   KATELLO_KEY_NAME="$KATELLO_GPG_KEY"
   LYNIS_KEY_URL='https://packages.cisofy.com/keys/cisofy-software-rpms-public.key'
   LYNIS_GPG_KEY=${LYNIS_KEY_URL##*/}
   LYNIS_KEY_NAME='RPM-GPG-KEY-cisofy-lynis'


   # Add the keys to Katello
   wget -q $CENTOS_KEY_URL
   wget -q $EPEL_KEY_URL
   wget -q $PUPPETLABS_KEY_URL
   wget -q $KATELLO_KEY_URL
   wget -q $LYNIS_KEY_URL

   hammer gpg create \
   --key "$CENTOS_GPG_KEY" \
   --name "$CENTOS_KEY_NAME"

   hammer gpg create \
   --key "$EPEL_GPG_KEY" \
   --name "$EPEL_KEY_NAME"

   hammer gpg create \
   --key "$PUPPETLABS_GPG_KEY" \
   --name "$PUPPETLABS_KEY_NAME"

   hammer gpg create \
   --key "$KATELLO_GPG_KEY" \
   --name "$KATELLO_KEY_NAME"

   hammer gpg create \
   --key "$LYNIS_GPG_KEY" \
   --name "$LYNIS_KEY_NAME"

   hammer gpg list

   # Clean up the temp directory
   cd -
   rm -rf $GPG_IMPORT_DIR

   # Create products
   CENTOS='CentOS 7'
   EPEL='EPEL 7'
   PUPPET='Puppet 5'
   KATELLO='Katello Agent'
   LYNIS='Lynis'

   hammer product create --name "$CENTOS"
   hammer product create --name "$EPEL"
   hammer product create --name "$PUPPET"
   hammer product create --name "$KATELLO"
   hammer product create --name "$LYNIS"

   hammer product list

   # Create repos for each product. Only yum based repos for now, apt versions can be added later if/when needed.
   # As well, puppet module repos, such as Puppet Forge, will be added once the developers resolve the issue in Foreman 1.20.1.
   # Lastly, docker repos will eventually need to be added too.
   CENTOS_MIRROR_URL='http://mirror.it.ubc.ca/centos'
   EPEL_MIRROR_URL='https://mirror.csclub.uwaterloo.ca/fedora/epel'
   PUPPETLABS_MIRROR_URL='https://yum.puppetlabs.com/puppet5/el'           # For puppet rpms, not puppet modules
   KATELLO_MIRROR_URL='https://yum.theforeman.org/client/1.20/el7'
   LYNIS_MIRROR_URL='https://packages.cisofy.com/community/lynis/rpm'
   OS_MAJOR_VERSION='7'
   ARCH='x86_64'
   OS_REPOS=(os updates extras centosplus fasttrack)

   # CentOS
   for REPO in ${OS_REPOS[@]}; do
      hammer repository create \
      --product "$CENTOS" \
      --name "${REPO}_$ARCH" \
      --label "${REPO}_$ARCH" \
      --content-type "yum" \
      --download-policy "on_demand" \
      --gpg-key "$CENTOS_KEY_NAME" \
      --url "$CENTOS_MIRROR_URL/$OS_MAJOR_VERSION/${REPO}/$ARCH/" \
      --mirror-on-sync "yes"
   done

   # EPEL
   hammer repository create \
   --product "$EPEL" \
   --name "epel_${ARCH}_rpm" \
   --label "epel_${ARCH}_rpm" \
   --content-type "yum" \
   --download-policy "on_demand" \
   --gpg-key "$EPEL_KEY_NAME" \
   --url "$EPEL_MIRROR_URL/$OS_MAJOR_VERSION/$ARCH/" \
   --mirror-on-sync "yes" \
   --verify-ssl-on-sync "yes"

   # Puppet
   hammer repository create \
   --product "$PUPPET" \
   --name "puppet_${ARCH}_rpm" \
   --label "puppet_${ARCH}_rpm" \
   --content-type "yum" \
   --download-policy "on_demand" \
   --gpg-key "$PUPPETLABS_KEY_NAME" \
   --url "$PUPPETLABS_MIRROR_URL/$OS_MAJOR_VERSION/$ARCH/" \
   --mirror-on-sync "yes" \
   --verify-ssl-on-sync "yes"

   # Katello Agent
   hammer repository create \
   --product "$KATELLO" \
   --name "katello_agent_${ARCH}_rpm" \
   --label "katello_agent_${ARCH}_rpm" \
   --content-type "yum" \
   --download-policy "on_demand" \
   --gpg-key "$KATELLO_KEY_NAME" \
   --url "$KATELLO_MIRROR_URL/$ARCH/" \
   --mirror-on-sync "yes" \
   --verify-ssl-on-sync "yes"

   # Lynis
   hammer repository create \
   --product "$LYNIS" \
   --name "lynis_rpm" \
   --label "lynis_rpm" \
   --content-type "yum" \
   --download-policy "on_demand" \
   --gpg-key "$LYNIS_KEY_NAME" \
   --url "$LYNIS_MIRROR_URL" \
   --mirror-on-sync "yes" \
   --verify-ssl-on-sync "yes"

   hammer repository list

   # Syncronize the repos
   REPO_IDS=( $(hammer --output json repository list | jq -r '.[].Id') )
   for ID in ${REPO_IDS[@]}; do \
      hammer repository synchronize --id "$ID"
   done

   # Create a daily sync-plan
   SYNC_PLAN_NAME='Daily'
   hammer sync-plan create \
   --name "$SYNC_PLAN_NAME" \
   --enabled=true \
   --interval daily \
   --organization-label $DEFAULT_ORG \
   --sync-date "$TODAY $DAILY_SYNC_TIME"

   # Associate the sync plan with all products
    PRODUCT_IDS=$(hammer --output json product list | jq '.[].ID')
    for ID in ${PRODUCT_IDS[@]}; do
        hammer product set-sync-plan --sync-plan $SYNC_PLAN_NAME --id $ID
    done

    hammer product list --sync-plan $SYNC_PLAN_NAME
}

# VM snapshot taken here 2019-02-05_11:35am

function create_content_structure {
   ###################################################################################
   ## Create Content View, Lifecycle Environments, Activation Keys and Subscriptions #
   ###################################################################################

   # Create a content view for our project
   CONTENT_VIEW_NAME="FTL CentOS 7"
   hammer content-view create \
   --name "$CONTENT_VIEW_NAME" \
   --description "Content view for FTL's CentOS 7"
   hammer content-view list

   # Add repositories to the content-view
   CONTENT_VIEW_ID=$(hammer --output json content-view list | jq ".[] | select(.Name | contains(\"$CONTENT_VIEW_NAME\")) | .[\"Content View ID\"]")
   UNIQUE_PRODUCTS_WITH_REPOS=$(hammer --output json repository list | jq -r '.[].Product' | sort | uniq | awk '{print $1}')
   for PRODUCT in ${UNIQUE_PRODUCTS_WITH_REPOS[@]}; do
      REPO_IDS=$(hammer --output json repository list | jq ".[] | select(.Product | contains(\"$PRODUCT\")) | .Id")
      PRODUCT_ID=$(hammer --output json product list | jq ".[] | select(.Name | contains(\"$PRODUCT\")) | .ID")
      for ID in ${REPO_IDS[@]}; do
         hammer content-view add-repository \
         --id "$CONTENT_VIEW_ID" \
         --product-id "$PRODUCT_ID" \
         --repository-id "$ID"; \
      done
   done

   # Publish the content view
   hammer content-view publish \
   --name "$CONTENT_VIEW_NAME" \
   --major 1 \
   --minor 0 \
   --description "Publishing repositories"

   # Create lifecycle environments
   hammer lifecycle-environment create \
   --name "dev" \
   --label "dev" \
   --prior "Library"

   hammer lifecycle-environment create \
   --name "prod" \
   --label "prod" \
   --prior "dev"

   hammer lifecycle-environment list

   # Promote the intial version of our content view to the development environment
   hammer content-view version promote \
   --content-view "$CONTENT_VIEW_NAME" \
   --version "1.0" \
   --from-lifecycle-environment "Library" \
   --to-lifecycle-environment "dev"

   hammer content-view version list

   # Create an activation key
   CONTENT_VIEW_KEY="$CONTENT_VIEW_NAME - key"
   hammer activation-key create \
   --name "$CONTENT_VIEW_KEY" \
   --description "Key to use with $CONTENT_VIEW_NAME" \
   --lifecycle-environment "dev" \
   --content-view "$CONTENT_VIEW_NAME" \
   --unlimited-hosts

   hammer activation-key list
   hammer subscription list

   SUBSCRIPTION_IDS=( $(hammer --output json subscription list | jq -r '.[].ID') )
   for ID in ${SUBSCRIPTION_IDS[@]}; do \
      hammer activation-key add-subscription \
      --name "$CONTENT_VIEW_KEY" \
      --quantity "1" \
      --subscription-id "$ID"
   done

   hammer content-view info --id $CONTENT_VIEW_ID

}

function dev_stage {
   echo "This is the dev stage"
   ######################
   # Setup Provisioning #
   ######################

   # I oculdn't figure out how to associate the foreman host with an org or location,
   # using hammer, so unfortunately I had to make that association via the GUI
   # This was necessary because otherwise I can't use its domain, its architecture, etc

   # List the domains, the only one should be the one associated with the Foreman host
   hammer domain list

   # Create a subnet
   FIRST_3_OCTETS=$(echo $IP | awk -F'.' '{print $1"."$2"."$3}')
   NETWORK="$FIRST_3_OCTETS.0"
   FROM="$FIRST_3_OCTETS.100"
   TO="$FIRST_3_OCTETS.200"

   hammer subnet create \
   --name "DC" \
   --network "$NETWORK" \
   --mask "255.255.255.0" \
   --gateway "$DEFAULT_GW" \
   --from "$FROM" \
   --to "$TO" \
   --dns-primary "$IP" \
   --boot-mode "DHCP" \
   --ipam "DHCP"

   hammer subnet list

   # Associate the domain with our smart proxy
   hammer domain update --id 1 --dns-id 1

   # Associate the subnet with the domain
   hammer subnet update --id 1 --domain-ids 1

   # Associate the subnet with the smart proxy
   hammer subnet update --id 1 --dhcp-id 1 --tftp-id 1 --dns-id 1

   # Create a machine architecture
   # hammer architecture list           # fails saying "Association not found for location" which I believe is a bug that is fixed in 1.21.x

   # Create a partition table
   #    We'll use a default one to start
   #hammer partition_table create --name "CentOS 7 - Bare Metal - Default" --file "$PWD/centos7_bare-metal_default_part.txt"

   # Create an OS
   #    Already created from a puppet fact on the Foreman host
   #hammer os create --name CentOS7 --major 7 --minor 6

   # Create a new provisioning template
   #    We'll use a default one to start
   #hammer template create --name "kickstart CentOS7" --type provision --file "$PWD/ks-centos7-default.txt

   # Associate OS with predefined template
   PROVISION_TEMPLATE_ID=$(hammer --output json template list | jq ".[] | select(.Name | startswith(\"Kickstart default\")) | select(.Type | startswith(\"provision\")) | .Id")
   hammer template update --id "$PROVISION_TEMPLATE_ID" --operatingsystem-ids 1

}

#################################################
#                   Main                        #
#################################################

# Check to see which stage of the installer we should start from
case $STAGE in
   install_katello)
      install_katello
      foreman-install_first_run
      foreman-install_second_run
      initial_full_backup
      create_products
      create_content_structure
      dev_stage
      ;;
   foreman-install_first_run)
      foreman-install_first_run
      foreman-install_second_run
      initial_full_backup
      create_products
      create_content_structure
      dev_stage
      ;;
   foreman-install_second_run)
      foreman-install_second_run
      initial_full_backup
      create_products
      create_content_structure
      dev_stage
      ;;
   create_products)
      create_products
      create_content_structure
      dev_stage
      ;;
   create_content_structure)
      create_content_structure
      dev_stage
      ;;
   dev_stage)
      dev_stage
      ;;
   *)
      echo "No choice was made"
      exit
      ;;
esac

