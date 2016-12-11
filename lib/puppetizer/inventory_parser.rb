module Puppetizer
  class InventoryParser
    @@csr_attributes=[
      'pp_uuid',
      'pp_instance_id',
      'pp_image_name',
      'pp_preshared_key',
      'pp_cost_center',
      'pp_product',
      'pp_project',
      'pp_application',
      'pp_service',
      'pp_employee',
      'pp_created_by',
      'pp_environment',
      'pp_role',
      'pp_software_version',
      'pp_department',
      'pp_cluster',
      'pp_provisioner',
      'pp_region',
      'pp_datacenter',
      'pp_zone',
      'pp_network',
      'pp_securitypolicy',
      'pp_cloudplatform',
      'pp_apptier',
      'pp_hostname',
    ]

    def self.csr_attributes
      @@csr_attributes
    end

    # parse a space delimited row and return tuple:
    # - hostname
    # - csr_attributes (true if found else false)
    # - hash (hash of all found attributes)
    def self.parse(row)
      split_row = row.split(/\s+/)
      hash = {}
      hostname = split_row.shift
      csr_attributes = false
      split_row.each do | s |
        if s.include?('=')
          kvp=s.split('=')
          hash[kvp[0]]=kvp[1]
          if self.csr_attributes.include?(kvp[0])
            csr_attributes = true
          end
        else
          hash[s]=true
        end
      end
      return hostname, csr_attributes, hash
    end

  end
end
