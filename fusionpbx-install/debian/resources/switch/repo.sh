#!/bin/sh

#move to script directory so all relative paths work
cd "$(dirname "$0")"

#includes
. ../config.sh
. ../colors.sh
. ../environment.sh

apt-get update && apt-get install -y curl memcached haveged apt-transport-https
apt-get update && apt-get install -y gnupg gnupg2
apt-get update && apt-get install -y wget lsb-release

# RingQ patch: use our own apt mirror instead of SignalWire.
# See docs/PLAN-freeswitch-mirror.md.
curl -fsSL -o /usr/share/keyrings/ringq-services-archive-keyring.gpg https://ringq-devs.github.io/services/keys/ringq-services-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/ringq-services-archive-keyring.gpg] https://ringq-devs.github.io/services/ `lsb_release -sc` main" > /etc/apt/sources.list.d/ringq-services.list
