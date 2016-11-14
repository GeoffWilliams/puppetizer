#!/bin/bash

# temporary script to download the gems we want for offline usage 
# into a directory called 'gems'

gem install puppetclassify -i gems --no-rdoc --no-ri
gem install pe_rbac -i gems --no-rdoc --no-ri
gem install hiera-eyaml -i gems --no-rdoc --no-ri




