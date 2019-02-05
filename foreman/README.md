# README

## Automated_install.sh
This script is intended to bootstrap the setup a simple Foreman/Katello server.

### Goal
Build a simple lab network with Foreman/Katello providing DNS and DHCP.

### Process Overview
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
