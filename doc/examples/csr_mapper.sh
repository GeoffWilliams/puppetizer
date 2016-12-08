#!/bin/bash
#
# Example CSR mapper
# ==================
# Lets say you have a file on the system put there by your provisioner
# and you want to be able to use this to automatically write the 
# csr_attributes file, you can use this script to write it for you, 
# avoiding the need to manually specify each entry in inventory/hosts
#
# To do this we will capture a bunch of variables and then write-out
# a csr


# puppet fields wanted

# HOST_LBU -> pp_department
# HOST_IN_DMZ -> pp_zone
# HOST_ENVIRONMENT -> pp_environment
# HOST_DC -> pp_datacenter
input_file='/etc/.system.INFO'
if [ -f $input_file ] ; then
  pp_department=$(awk -F'=' '/HOST_LBU/ {print $2}' < $input_file)
  dmz=$(awk -F'=' '/HOST_IN_DMZ/ {print $2}' < $input_file)
  if [ "$dmz" == "INTERNAL" ] ; then
    pp_dmz="NON-DMZ"
  else
    pp_dmz="DMZ"
  fi 
  pp_environment=$(awk -F'=' '/HOST_ENVIRONMENT/ {print $2}' < $input_file)
  pp_datacenter=$(awk -F'=' '/HOST_DC/ {print $2}' < $input_file)
else
  echo "No system info available at $input_file - cannot continue!"
  exit 1
fi

