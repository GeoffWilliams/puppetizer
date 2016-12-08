#!/bin/sh
#
# Compute a Puppet Enterprise platform tag
# EG, rhel-7-x64
#
# We use /bin/sh because not all targets will have bash installed

# 
ARCH=$(uname -p)

if [ "$(uname -s)" = "Linux" ] ; then
    if [ -f /etc/redhat-release ] && [ -r /etc/redhat-release ] && [ -s /etc/redhat-release ]; then
        PLATFORM='el'
        RELEASE="$(sed 's/.*\ release\ \([[:digit:]]\+\).*/\1/g;q' /etc/redhat-release)"
    else
        echo "Unsupported linux flavor"
        exit 1
    fi
elif [ "$(uname -s)" = "SunOS" ]; then
    PLATFORM='solaris'
    # We get back 5.10 but we only care about the right side of the decimal.
    RELEASE=$(uname -r | awk -F. '{print $2}')
elif [ "$(uname -s)" = "AIX" ] ; then
    PLATFORM='aix'
    ARCH='power'
    RELEASE=$(oslevel | cut -d'.' -f1,2)
else
    echo "unsupported platform"
    exit 1
fi

if [ "$ARCH" = "i686" ] ; then
    ARCH_MUNGED='i386'
else
    ARCH_MUNGED=$ARCH
fi

echo "${PLATFORM}-${RELEASE}-${ARCH_MUNGED}"
