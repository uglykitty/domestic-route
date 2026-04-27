#!/bin/bash

delegated_apnic_latest_url=https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
delegated_apnic_latest_file=/tmp/delegated-apnic-latest

curl -Lsz $delegated_apnic_latest_file -o $delegated_apnic_latest_file\
 $delegated_apnic_latest_url

gateway=$(ip route | awk '/^default/ {print $3}')
interface=$(ip route | awk '/^default/ {print $5}')
gateway6=$(ip -6 route | awk '/^default/ {print $3}')
interface6=$(ip -6 route | awk '/^default/ {print $5}')

function ip_route_add() {
    cmd="ip -$1 route add $2 via $3 dev $4"
    $cmd
    if [ $? -ne 0 ]; then
        echo "Failed to execute: $cmd"
    fi
}

if [ ! -z "$gateway" ] && [ ! -z "$interface" ]; then
    ip4=$(dig +short wangguofang.net A | head -n 1)
    ip_route_add 4 $ip4 $gateway $interface
    ip_route_add 4 10.0.0.0/8 $gateway $interface

    cat $delegated_apnic_latest_file |
    grep "^apnic|CN|ipv4" |
    awk -F"|" '{print $4 "/" 32-log($5)/log(2)}' |
    while read line; do
        ip_route_add 4 $line $gateway $interface
    done
fi

if [ ! -z "$gateway6" ] && [ ! -z "$interface6" ]; then
    cat $delegated_apnic_latest_file |
    grep "^apnic|CN|ipv6" |
    awk -F"|" '{print $4 "/" $5}' |
    while read line; do
        ip_route_add 6 $line $gateway6 $interface6
    done
fi
