#!/usr/bin/env bash

set -xe

echo "Current Configuration:"
echo ""
iptables-save --table "filter"
echo ""

# This is complicated by docker daemon managing some of the IPv4 FORWARD chain, so this
# script can't just do e.g. iptables-restore on the filter table.

chain_exists=$(
    iptables -nL FIREWALL >/dev/null 2>/dev/null
    echo $?
)
link_exists=$(
    iptables -C INPUT -j FIREWALL >/dev/null 2>/dev/null
    echo $?
)

chain6_exists=$(
    ip6tables -nL FIREWALL >/dev/null 2>/dev/null
    echo $?
)
link6_exists=$(
    ip6tables -C INPUT -j FIREWALL >/dev/null 2>/dev/null
    echo $?
)

if [ "$1" = 'clear' ]; then
    if [ $link_exists == 0 ]; then iptables -D INPUT -j FIREWALL; fi
    if [ $link6_exists == 0 ]; then ip6tables -D INPUT -j FIREWALL; fi
    if [ $chain_exists == 0 ]; then
        iptables -F FIREWALL
        iptables -X FIREWALL
    fi
    if [ $chain6_exists == 0 ]; then
        ip6tables -F FIREWALL
        ip6tables -X FIREWALL
    fi

    echo "New configuration:"
    echo ""
    iptables-save --table "filter"
    echo ""
    exit 0
fi

# Create firewall chain and populate with rules for INPUT filtering

iptables -N FIREWALL 2>/dev/null || true
iptables -F FIREWALL

ip6tables -N FIREWALL 2>/dev/null || true
ip6tables -F FIREWALL

iptables -N LOGDROP 2>/dev/null || true
iptables -F LOGDROP
iptables -A LOGDROP -m limit --limit 5/min -j LOG --log-prefix "v4 Dropped: " --log-level 5
iptables -A LOGDROP -j DROP

ip6tables -N LOGDROP 2>/dev/null || true
ip6tables -F LOGDROP
ip6tables -A LOGDROP -m limit --limit 5/min -j LOG --log-prefix "v6 Dropped: " --log-level 5
ip6tables -A LOGDROP -j DROP

#

iptables -A FIREWALL -j ACCEPT -m conntrack --ctstate ESTABLISHED,RELATED
iptables -A FIREWALL -j ACCEPT -i lo
iptables -A FIREWALL -j LOGDROP -m conntrack --ctstate INVALID # Never reject when in invalid state
iptables -A FIREWALL -j ACCEPT -p icmp --icmp-type ping -m limit --limit 240/min -s 192.168.1.0/24
iptables -A FIREWALL -j ACCEPT -p icmp --icmp-type pong -m limit --limit 240/min

ip6tables -A FIREWALL -j ACCEPT -m conntrack --ctstate ESTABLISHED,RELATED
ip6tables -A FIREWALL -j ACCEPT -i lo
ip6tables -A FIREWALL -j LOGDROP -m conntrack --ctstate INVALID # Never reject when in invalid state
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type destination-unreachable -m limit --limit 240/min
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type packet-too-big -m limit --limit 240/min
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type time-exceeded -m limit --limit 240/min
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type parameter-problem -m limit --limit 240/min
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type router-advertisement -m hl --hl-eq 255 -d ff02::1
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type neighbour-solicitation -m hl --hl-eq 255 -d ff02::/32
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type neighbour-advertisement -m hl --hl-eq 255 -d fe80::/32 # Only accept advertisments to link local addresses
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type echo-request -m limit --limit 240/min -s fe80::/32
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type echo-reply -m limit --limit 240/min

# Multicast Name Resolution
iptables -A FIREWALL -j ACCEPT -p udp --dport 5353 -s 192.168.1.0/24 -d 224.0.0.251 -m comment --comment "mDNS"
for hoplimit in 1 255; do
    ip6tables -A FIREWALL -j ACCEPT -p udp --dport 5353 -d ff02::fb -m hl --hl-eq $hoplimit -m comment --comment "mDNS"
done

# Perhaps in the future, if we subscribe to LLMNR, these would be useful
# iptables -A FIREWALL -j DROP -p udp --dport 5355 -s 192.168.1.0/24 -d 224.0.0.252 -m comment --comment "LLMNR (Windows)"
# for hoplimit in 1 255; do
#   ip6tables -A FIREWALL -j DROP -p udp --dport 5355 -d ff02::1:3 -m hl --hl-eq $hoplimit -m comment --comment "LLMNR (Windows)"
# done

# GMP, because we live in a world of multicast now
iptables -A FIREWALL -j ACCEPT -s 192.168.1.0/24 -d 224.0.0.0/8 -p igmp
ip6tables -A FIREWALL -j ACCEPT -s fe80::/32 -d ff30::/24 -p icmpv6
ip6tables -A FIREWALL -j ACCEPT -p icmpv6 --icmpv6-type 143 -s fe80::/32 -d ff02::16 -m hl --hl-eq 1 -m comment --comment "Multicast Listener Reports"

# RIP
ip6tables -A FIREWALL -j ACCEPT -p udp --dport 521 -s fe80::/32 -d ff02::9 -m hl --hl-eq 255 -m comment --comment "RIPng from router"

# DHCP
ip6tables -A FIREWALL -j ACCEPT -p udp --dport 546 --sport 547 -s fe80::1:1/32 -m hl --hl-eq 64 -m comment --comment "DHCPv6 from router"

# Custom rules
iptables -A FIREWALL -j ACCEPT -s 192.168.1.0/24 -p tcp --dport 22 -m comment --comment "SSH"
ip6tables -A FIREWALL -j ACCEPT -s fe80::/32 -p tcp --dport 22 -m comment --comment "SSH"
iptables -A FIREWALL -j ACCEPT -s 192.168.1.0/24 -p tcp --dport 9090 -m comment --comment "Prometheus"
ip6tables -A FIREWALL -j ACCEPT -s fe80::/32 -p tcp --dport 9090 -m comment --comment "Prometheus"

# Common drops for the sake of log noise
iptables -A FIREWALL -j DROP -p udp --dport 67 --sport 68 -d 255.255.255.255 -m comment --comment "DHCP broadcasts from other devices"
iptables -A FIREWALL -j DROP -p udp -m addrtype --dst-type BROADCAST --dport 9999 -m comment --comment "TPLink Kasa discovery protocol"
iptables -A FIREWALL -j DROP -p udp -m addrtype --dst-type BROADCAST --dport 10101 -m comment --comment "Google Home discovery"
iptables -A FIREWALL -j DROP -p udp -m addrtype --dst-type BROADCAST --sport 9487 --dport 9478 -m comment --comment "Google Home discovery (2)"
for cmd in iptables ip6tables; do
    $cmd -A FIREWALL -j DROP -p udp -m multiport --dports 137,138 -m comment --comment "netbios chatter"
    $cmd -A FIREWALL -j DROP -p udp --dport 17500 -m comment --comment "dropbox chatter"
done

iptables -A FIREWALL -j LOGDROP
ip6tables -A FIREWALL -j LOGDROP

# Reject quickly on the local network
ip6tables -A FIREWALL -j REJECT -m hl --hl-eq 255 --reject-with icmp6-adm-prohibited

####################################################################
# Finally, activate the chain as the first step of the INPUT chain

if [ $link_exists == 0 ]; then iptables -D INPUT -j FIREWALL; fi
iptables -A INPUT -j FIREWALL

if [ $link6_exists == 0 ]; then ip6tables -D INPUT -j FIREWALL; fi
ip6tables -A INPUT -j FIREWALL

echo "New configuration:"
echo ""
iptables-save --table "filter"
echo ""
