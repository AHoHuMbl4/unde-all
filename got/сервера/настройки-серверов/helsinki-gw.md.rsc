# 2026-02-25 20:09:24 by RouterOS 7.21.3
# system id = agsEannhrrD
#
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no name=external
set [ find default-name=ether2 ] disable-running-check=no mtu=1450 name=\
    internal
/interface wireguard
add listen-port=51820 mtu=1420 name=wg-local
/ip address
add address=10.3.0.1/24 interface=wg-local network=10.3.0.0
/ip dhcp-client
add interface=external
add interface=internal
/ip firewall filter
add action=accept chain=forward comment="WG local -> Helsinki LAN" \
    in-interface=wg-local
add action=accept chain=forward comment="Helsinki LAN -> WG local" \
    out-interface=wg-local
/ip route
add dst-address=10.2.0.0/24 gateway=wg-local
/ipv6 nd
set [ find default=yes ] advertise-dns=yes
/system clock
set time-zone-name=Europe/Helsinki
/system identity
set name=helsinki-gw
