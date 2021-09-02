source ./vars.sh
set -e

# To set the fedora cloud image password
# LIBGUESTFS_BACKEND=direct virt-sysprep -a Fedora-Cloud-Base-34-1.2.x86_64.qcow2 --password fedora:password:fedora

# Start  nodes
for l in $LEAVES; do
    for n in $NODES; do

TERM=xterm expect -c "
set timeout 300
set uplinks [list $(echo ${UPLINK[@]})]
spawn bash -c \"virsh console $l-$n\"
sleep 1
send \"\r\"
expect {
  timeout { exit 1 }
  eof { exit 1 }
  \"* login:\"
}
send \"fedora\r\"
expect \"Password:\"
send \"fedora\r\"
sleep 1
send \"sudo -i\r\"
expect \"*#\"
if {\"node0\" == \"$n\"} {
    send \"nmcli connection modify 'Wired connection 1' IPv4.method manual IPv4.address 192.168.${l: -1}.$((${n: -1}+1))/24\r\"
    expect \"*#\"
    send \"nmcli connection modify 'Wired connection 1' IPv4.gateway 192.168.${l: -1}.254\r\"
}

if {\"node1\" == \"$n\"} {
    send \"nmcli connection modify 'Wired connection 1' IPv4.method manual IPv4.address 192.168.3.$((${l: -1}+1))/24\r\"
    expect \"*#\"
    send \"nmcli connection modify 'Wired connection 1' IPv4.gateway 192.168.3.254\r\"
}

if {\"node2\" == \"$n\"} {
    send \"nmcli connection modify 'Wired connection 1' IPv4.method disabled\r\"
    expect \"*#\"
    send \"nmcli connection add type vlan con-name vlan0007 dev eth0 id 7 ip4 192.168.7.$((${l: -1}+1))/24 gw4 192.168.7.254\r\"
}
expect \"*#\"
send \"nmcli connection reload\r\"
expect \"*#\"
send \"hostname $l-$n\r\"
expect \"*#\"
send \"exit\r\"
sleep 1
send \"exit\r\"
"
echo ""
echo ""

    done
done
