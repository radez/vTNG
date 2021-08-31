source ./vars.sh
set -e


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
  \"cirros login:\"
}
send \"cirros\r\"
expect \"Password:\"
send \"gocubsgo\r\"
sleep 1
send \"sudo -i\r\"
expect \"#\"
if {\"node0\" == \"$n\"} {
    send \"ip a a 192.168.${l: -1}.$((${n: -1}+1))/24 dev eth0\r\"
    expect \"#\"
    send \"ip link set eth0 up\r\"
    expect \"#\"
    send \"ip r a default via 192.168.${l: -1}.254\r\"
    expect \"#\"
}

if {\"node1\" == \"$n\"} {
    send \"ip a a 192.168.3.$((${l: -1}+1))/24 dev eth0\r\"
    expect \"#\"
    send \"ip link set eth0 up\r\"
    expect \"#\"
    send \"ip r a default via 192.168.3.254\r\"
    expect \"#\"

}

if {\"node2\" == \"$n\"} {
    send \"ip a a 192.168.7.$((${l: -1}+1))/24 dev eth0\r\"
    expect \"#\"
    send \"ip link set eth0 up\r\"
    expect \"#\"
    send \"ip r a default via 192.168.7.254\r\"
    expect \"#\"

}
"

    done
done
