/opt/puppetlabs/puppet/bin/puppet resource service puppet ensure=stopped
/opt/puppetlabs/puppet/bin/puppet resource service puppet ensure=running enable=true
/opt/puppetlabs/puppet/bin/puppet resource service mcollective ensure=stopped
/opt/puppetlabs/puppet/bin/puppet resource service mcollective ensure=running enable=true
