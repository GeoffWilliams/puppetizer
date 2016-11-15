#!/bin/bash

# temporary script to download the gems we want for offline usage 
# into a directory called 'gems/cache'
mkdir -p gems/cache
pushd gems/cache

for GEM in  domain_name \
            escort \
            hiera-eyaml \
            highline \
            http-cookie \
            mime-types \
            mime-types-data \
            nesty \
            netrc \
            pe_rbac \
            puppetclassify \
            rest-client \
            trollop \
            unf \
            unf_ext ; do
  gem fetch $GEM
done

#gem install puppetclassify -i gems --no-rdoc --no-ri
#gem install pe_rbac -i gems --no-rdoc --no-ri
#gem install hiera-eyaml -i gems --no-rdoc --no-ri




