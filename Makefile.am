# SPDX-License-Identifier: GPL-2.0-only
opdir		 = $(datadir)/vyatta-op/templates
share_perl5dir	 = $(datarootdir)/perl5
libudevdir	 = /lib/udev
etcudevdir	 = /etc/udev
initddir	 = /etc/init.d
modprobedir	 = /etc/modprobe.d
yangdir = /usr/share/configd/yang

sysconf_DATA	 =
sbin_SCRIPTS	 =

sbin_SCRIPTS += scripts/vyatta_gen_radvd.pl
sbin_SCRIPTS += scripts/vyatta-ipv6-eui64.pl
sbin_SCRIPTS += scripts/vyatta-ipv6-link-local.pl
sbin_SCRIPTS += scripts/vyatta-ipv6-autoconf.sh
sbin_SCRIPTS += scripts/vyatta-ipv6-forwarding.sh
sbin_SCRIPTS += scripts/vyatta-ipv6-rtradv.sh

modprobe_DATA = etc/modprobe.d/ipv6.conf

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(yangdir)
	cd yang && $(cpiop) $(DESTDIR)$(yangdir)
