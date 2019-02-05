# README

## Automathttps://dcsc.lenovo.com/#/ed_install.sh
This script is intended to bootstrap the setup a simple Foreman/Katello server.

### Goal
Build a simple lab network with Foreman/Katello providing DNS and DHCP.

### Requirements
* Start with two bare metal boxes, a switch, necessary cabling, a simple home router, an Internet connection and my laptop
* Automate the build of a Foreman/Katello server that will provide the following services to the lab:
  * Authoritative DNS (fwd and rev)
  * Recursive DNS
  * DHCP/TFTP for PXE booting bare metal hosts
  * Puppet
  * Content management (yum, puppet modules, isos)
* Boot a PXE enabled host
* Foreman discovers the host and displays its facts
* Admin converts the discovered host into a managed host, which will install CentOS
* Foreman should configure the host as both a libvirt and a docker compute resource
* Using Foreman, the admin creates a new CentOS VM on the libvirt compute resource
* Using Foreman, the admin creates a new Docker container on the docker compute resource

### Process
* Manually configure one bare metal box as a Proxmox server
* Upload the latest CentOS minimal ISO to the Proxmox server
* Create a CentOS VM on the Proxmox server with the following specs:
  * virtual CDROM using CentOS minimal iso image
  * 4 virtual cores
  * 8GB (8192MB) RAM
  * 100GB disk (VirtIO SCSI)
  * Network attached to default bridge with no VLANs (VirtIO device)
* During the CentOS install
  * Set the hostname to a FQDN, such as foreman.example.com
  * Configure the network device
    * Static IP
    * Use a public DNS server, such as 9.9.9.9
    * Set the search domain (example.com)
  * Use the default partitioning scheme
  * Create a root password
* Once the VM is created and rebooted
  * copy the automated_install.sh and local.conf files to your home directory
  * edit the local.conf file as needed
  * `chmod 750 automated_install.sh`
  * `./automated_install.sh &`


The build will take a very long time, but you will be able to watch the progress.
