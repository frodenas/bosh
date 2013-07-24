# Setup base chroot
stage base_debootstrap
stage base_apt

# Bosh steps
stage bosh_users
stage bosh_debs
stage bosh_monit
stage bosh_ruby
stage bosh_agent
stage bosh_sysstat
stage bosh_sysctl
stage bosh_ntpdate
stage bosh_sudoers

# Micro BOSH
if [ ${bosh_micro_enabled:-no} == "yes" ]
then
  stage bosh_micro
fi

# Install GRUB/kernel/etc
stage system_grub
stage system_kernel
stage system_xen_guest_utils
stage system_rackspace_guest_agent

# Misc
stage system_parameters

# Finalisation
stage bosh_clean
stage bosh_harden
stage bosh_harden_ssh
stage bosh_tripwire
stage bosh_dpkg_list

# Image/bootloader
stage image_create
stage image_install_grub
stage image_rackspace_update_grub
stage image_openstack_prepare_stemcell

# Final stemcell
stage stemcell_openstack