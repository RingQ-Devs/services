#!/bin/sh

#move to script directory so all relative paths work
cd "$(dirname "$0")"

#includes
. ../config.sh
. ../colors.sh
. ../environment.sh

apt-get update && apt-get install -y curl memcached haveged apt-transport-https
apt-get update && apt-get install -y gnupg gnupg2
apt-get update && apt-get install -y wget lsb-release sox

if [ ."$cpu_architecture" = ."x86" ]; then
	# RingQ patch: use our own apt mirror at ringq-devs.github.io/services
	# instead of SignalWire's repo. Mirror is pinned to FreeSWITCH 1.10.12 and
	# carries the matching sound/music packages. No auth.conf needed (public).
	# Original SignalWire fetch removed; see docs/PLAN-freeswitch-mirror.md.
	curl -fsSL -o /usr/share/keyrings/ringq-services-archive-keyring.gpg https://ringq-devs.github.io/services/keys/ringq-services-archive-keyring.gpg
	echo "deb [signed-by=/usr/share/keyrings/ringq-services-archive-keyring.gpg] https://ringq-devs.github.io/services/ `lsb_release -sc` main" > /etc/apt/sources.list.d/ringq-services.list
fi
if [ ."$cpu_architecture" = ."arm" ]; then
	wget --http-user=signalwire --http-password=$switch_token -O /usr/share/keyrings/signalwire-freeswitch-repo.gpg https://freeswitch.signalwire.com/repo/deb/rpi/debian-release/freeswitch_archive_g0.pub
	echo "machine freeswitch.signalwire.com login signalwire password $switch_token" > /etc/apt/auth.conf
	echo "deb [signed-by=/etc/apt/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/rpi/debian-release/ `lsb_release -sc` main" > /etc/apt/sources.list.d/freeswitch.list
	echo "deb-src [signed-by=/etc/apt/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/rpi/debian-release/ `lsb_release -sc` main" >> /etc/apt/sources.list.d/freeswitch.list
fi

apt-get update
apt-get install -y gdb ntp
apt-get install -y freeswitch-meta-bare freeswitch-conf-vanilla freeswitch-mod-commands freeswitch-mod-console freeswitch-mod-logfile
# RingQ patch: sound packages (freeswitch-sounds-*, freeswitch-music-default)
# removed from the mirror. The say modules remain because they're code, not audio.
# If voice prompts / hold music are needed later, re-mirror those packages and
# add the corresponding install + post-install dance back here.
apt-get install -y freeswitch-lang-en freeswitch-mod-say-en
apt-get install -y freeswitch-mod-say-es freeswitch-mod-say-es-ar
apt-get install -y freeswitch-mod-say-fr
apt-get install -y freeswitch-mod-enum freeswitch-mod-cdr-csv freeswitch-mod-event-socket freeswitch-mod-sofia freeswitch-mod-sofia-dbg freeswitch-mod-loopback
apt-get install -y freeswitch-mod-conference freeswitch-mod-db freeswitch-mod-dptools freeswitch-mod-expr freeswitch-mod-fifo freeswitch-mod-httapi
apt-get install -y freeswitch-mod-hash freeswitch-mod-esl freeswitch-mod-esf freeswitch-mod-fsv freeswitch-mod-valet-parking freeswitch-mod-dialplan-xml freeswitch-dbg
apt-get install -y freeswitch-mod-sndfile freeswitch-mod-native-file freeswitch-mod-local-stream freeswitch-mod-tone-stream freeswitch-mod-lua freeswitch-meta-mod-say
apt-get install -y freeswitch-mod-xml-cdr freeswitch-mod-verto freeswitch-mod-callcenter freeswitch-mod-rtc freeswitch-mod-png freeswitch-mod-json-cdr freeswitch-mod-shout
apt-get install -y freeswitch-mod-sms freeswitch-mod-sms-dbg freeswitch-mod-cidlookup freeswitch-mod-memcache
apt-get install -y freeswitch-mod-imagick freeswitch-mod-tts-commandline freeswitch-mod-directory
apt-get install -y freeswitch-mod-av freeswitch-mod-flite freeswitch-mod-distributor freeswitch-meta-codecs
apt-get install -y freeswitch-mod-pgsql
apt-get install -y libyuv-dev

#make sure that postgresql is started before starting freeswitch
sed -i /lib/systemd/system/freeswitch.service -e s:'local-fs.target:local-fs.target postgresql.service:'
