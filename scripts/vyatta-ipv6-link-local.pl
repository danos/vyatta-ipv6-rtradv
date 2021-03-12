#!/usr/bin/perl
#
# Module: vyatta-ipv6-link-local.pl
#
# **** License ****
# Copyright (c) 2017-2021, AT&T Intellectual Property. All rights reserved.
# Copyright (c) 2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# **** End License ****
#
# Syntax:
#    vyatta-ipv6-link-local.pl --update <ifname> <IPv6-address> [--verbose]
#    vyatta-ipv6-link-local.pl --delete <ifname> <IPv6-address> [--verbose]
#
# The first form will update a new  link-local IPv6 address on <ifname>
# Any other link-local address already configured or auto-generated
# for the interface will be deleted.
#
# The second form removes configured link-local address.
# This will result in link-local address to be autoconfigured if
# ipv6 is already enabled.
#

use strict;
use warnings;

use Getopt::Long;
use Net::IP;
use Vyatta::Interface;

my @update;
my @delete;

my $verbose = '';

GetOptions(
    "update=s{2}" => \@update,
    "delete=s{2}" => \@delete,
    "verbose"     => \$verbose,
) or usage();

update_ll_addr(@update) if (@update);
delete_ll_addr(@delete) if (@delete);
exit 0;

sub usage {
    print <<EOF;
Updates or deletes configured link-local IPv6 address on the interface
Usage:	$0 --update <ifname> <IPv6address> [--verbose]
	$0 --delete <ifname> <IPv6address> [--verbose]
EOF
    exit 1;
}

# Test if IPv6 is disabled on this interface
sub ipv6_disabled {
    my $name = shift;

    open my $f, '<', "/proc/sys/net/ipv6/conf/$name/disable_ipv6"
      or return;
    my $disabled = <$f>;
    close $f;

    chomp $disabled;
    return $disabled eq '1';
}

sub update_ll_addr {
    my ( $ifname, $address ) = @_;

    # We expect the interface to exist and to be configured for IPv6
    die "Error: Interface $ifname does not exist.\n"
      unless ( -d "/proc/sys/net/ipv6/conf/$ifname" );

    my $ip = new Net::IP($address);

    my $type = ( $ip->iptype() );
    die "Error: not a valid link-local IPv6 address: $address"
      if ( $type ne "LINK-LOCAL-UNICAST" );

    my $intf = new Vyatta::Interface($ifname);
    $intf or die "Unknown interface name/type: $ifname\n";
    my $cmd_prefix =
      $intf->can("vrf_cmd_prefix") ? $intf->vrf_cmd_prefix() : "";
    my @ll_addr_line =
      grep /net6/, qx(${cmd_prefix}ip -6 addr show dev $ifname scope link);

    for ( my $i = 0 ; $i <= $#ll_addr_line ; $i++ ) {

        my @addr_line = split( ' ', $ll_addr_line[$i] );
        my $ll_addr = $addr_line[1];
        if ( system("${cmd_prefix}ip -6 addr del $ll_addr dev $ifname") != 0 ) {
            warn "Delete $ll_addr on $ifname failed \n";
        }
    }
    if ( system("${cmd_prefix}ip -6 addr add $address/64 dev $ifname") != 0 ) {
        warn "IPv6 address $address on $ifname add failed \n";
    } elsif ($verbose) {
        print "$address replaced any other link-local addresses on $ifname \n";
    }

    exit 0;
}

sub get_mac_address {
    my $ifname = shift;

    # Get 48-bit MAC addr of $ifname
    open my $sysfs, '<', "/sys/class/net/$ifname/address"
      or die "can't open /sys/class/net/$ifname/address: $!";
    my $macaddr = <$sysfs>;
    close $sysfs;
    chomp $macaddr;

    my @octets = split( ':', $macaddr );
    die "Error: $macaddr not a 48 bit MAC address, IPv6 or IPv4 address\n"
      unless ( $#octets == 15 || $#octets == 5 || $#octets == 3 );

    return @octets;
}

sub get_eui64_address {
    my ( $ifname, $address ) = @_;

    # We expect the interface to exist and to be configured for IPv6
    die "Error: Interface $ifname does not exist.\n"
      unless ( -d "/proc/sys/net/ipv6/conf/$ifname" );

    my $ip = new Net::IP($address);
    die "Error: not a valid IP address: $address"
      unless defined($ip);

    my $prefix_len = $ip->prefixlen();
    die "Error: Prefix length is $prefix_len is not 64"
      if ( $prefix_len != 64 );

    # construct the host part from the MAC address
    my @ea = get_mac_address($ifname);

    if ( $#ea == 15 ) {

        # If HW address is an IPv6 address e.g. for tunnels, instead use
        # the permanent MAC address (not persistent across reboots)
        my $macaddr = ( split( ' ', qx(/sbin/ethtool -P $ifname) ) )[2];
        die "Error: No permanent address found for $ifname\n"
          unless defined($macaddr);
        @ea = split( ':', $macaddr );
    }

    my @eui64;
    if ( $#ea == 3 ) {

        # Modified EUI-64 is constructed from the IPv4 address given
        # in the h/w address as per RFC5342 section 2.2.1
        @eui64 = ( "0200", "5efe", "$ea[0]$ea[1]", "$ea[2]$ea[3]" );
    } else {

        # flip locally assigned bit per RFC 2373
        $ea[0] = sprintf( "%x", hex( $ea[0] ) ^ 0x2 );

        # construct EUI64 address array
        @eui64 = ( "$ea[0]$ea[1]", "$ea[2]ff", "fe$ea[3]", "$ea[4]$ea[5]" );
    }

    # Form 128-bit IPv6 addr based by adding the host part to the prefix
    my $eui64suffix = new Net::IP( "::" . join ":", @eui64 );
    my $ipv6_addr = $ip->binadd($eui64suffix);
    return $ipv6_addr->ip . "/64";
}

sub delete_ll_addr {
    my ( $ifname, $address ) = @_;
    my $intf = new Vyatta::Interface($ifname);
    $intf or die "Unknown interface name/type: $ifname\n";
    my $cmd_prefix =
      $intf->can("vrf_cmd_prefix") ? $intf->vrf_cmd_prefix() : "";

    if ( system("${cmd_prefix}ip -6 addr del $address/64 dev $ifname") != 0 ) {
        warn "IPv6 address $address on $ifname delete failed \n";
    }
    if ( ipv6_disabled($ifname) ) {
        print
"IPv6 disabled: $ifname, Link-local will be autoconfigured when IPv6 is enabled";
    } else {
        my $prefix = ("fe80::/64");
        my $ipv6_addr = get_eui64_address( $ifname, $prefix );

        if ( system("${cmd_prefix}ip -6 addr add $ipv6_addr dev $ifname") != 0 )
        {
            warn "IPv6 address $ipv6_addr configuration on $ifname failed \n";
        } elsif ($verbose) {
            print "$ipv6_addr link-local address autoconfigured on $ifname \n";
        }
    }
    exit 0;
}

