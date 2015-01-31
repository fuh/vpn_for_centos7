#!/bin/bash

# Build by mayitbe.net

wget -c http://dl.fedoraproject.org/pub/epel/7/x86_64/x/xl2tpd-1.3.6-7.el7.x86_64.rpm
wget -c http://dl.fedoraproject.org/pub/epel/7/x86_64/p/pptpd-1.4.0-2.el7.x86_64.rpm
yum -y install openswan net-tools ppp xl2tpd-1.3.6-7.el7.x86_64.rpm pptpd-1.4.0-2.el7.x86_64.rpm
rm -rf xl2tpd-1.3.6-7.el7.x86_64.rpm
rm -rf pptpd-1.4.0-2.el7.x86_64.rpm

cat >> /etc/pptpd.conf << EOF
localip 192.168.144.1
remoteip 192.168.144.2-254
EOF

cat >> /etc/ppp/options.pptpd <<EOF
ms-dns 8.8.8.8
ms-dns 8.8.4.4
EOF

cat > /etc/ipsec.conf << EOF
config setup
	protostack=netkey
	dumpdir=/var/run/pluto/
	nat_traversal=yes
        virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:25.0.0.0/8,%v4:100.64.0.0/10,%v6:fd00::/8,%v6:fe80::/10

conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT

conn L2TP-PSK-noNAT
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=YOUR_IPADDR
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
EOF

cat > /etc/ipsec.secrets << EOF
include /etc/ipsec.d/*.secrets
YOUR_IPADDR   %any:  PSK "mayitbe.net"
EOF

cat > get_local_ip.py <<EOF
#!/usr/bin/env python
import socket
def Get_local_ip():
    try:
        csock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        csock.connect(('8.8.8.8', 80))
        (addr, port) = csock.getsockname()
        csock.close()
        return addr
    except socket.error:
        return "127.0.0.1"

if __name__ == "__main__":
    local_IP = Get_local_ip()
    print local_IP
EOF
chmod +x get_local_ip.py
localip=`./get_local_ip.py`
sed -i "s/YOUR_IPADDR/$localip/g" /etc/ipsec.conf
sed -i "s/YOUR_IPADDR/$localip/g" /etc/ipsec.secrets
rm -rf get_local_ip.py

echo 1 > /proc/sys/net/ipv4/ip_forward
for each in /proc/sys/net/ipv4/conf/*
do
    echo 0 > $each/accept_redirects
    echo 0 > $each/send_redirects
done

systemctl restart ipsec.service
ipsec verify

cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]

[lns default]
ip range = 192.168.1.128-192.168.1.254
local ip = 192.168.1.99
require chap = yes
refuse pap = yes
require authentication = yes
name = LinuxVPNserver
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat > /etc/ppp/options.xl2tpd << EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns  8.8.8.8
ms-dns  8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
lock
proxyarp
connect-delay 5000
EOF

cat > /etc/ppp/chap-secrets << EOF
vpn * 123456 *
EOF

cat >> /etc/rc.d/rc.local <<EOF
iptables -A INPUT -p gre -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.144.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -j MASQUERADE
iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
echo 1 > /proc/sys/net/ipv4/ip_forward
for each in /proc/sys/net/ipv4/conf/*
do
    echo 0 > $each/accept_redirects
    echo 0 > $each/send_redirects
done
systemctl restart ipsec.service
/usr/sbin/xl2tpd
systemctl restart pptpd
EOF

chmod +x /etc/rc.d/rc.local

iptables -A INPUT -p gre -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.144.0/24 -j MASQUERADE
iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
echo 1 > /proc/sys/net/ipv4/ip_forward
systemctl restart ipsec.service
systemctl restart pptpd
systemctl enable pptpd
iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -j MASQUERADE
/usr/sbin/xl2tpd

echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "Success! And the VPN account is:"
echo "Method:PPTP or L2TP"
echo "User:vpn"
echo "Password:123456"
echo "PSK:xl2tpdayitbe.net"
echo "If you want to modify, with vim tool in /etc/ppp/chap-secrets"
echo "Good luck!"
