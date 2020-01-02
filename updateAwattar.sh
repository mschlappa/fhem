#!/bin/bash
#
# 

result=$(/home/pi/awattar.sh $1) 

time=$(echo $result | cut -d ' ' -f 1)
mittelwertOpt=$(echo $result | cut -d ' ' -f 2)
mittelwertGesamt=$(echo $result | cut -d ' ' -f 3)
mittelwertRest=$(echo $result | cut -d ' ' -f 4)

isoTime=$(date -d @$time +"%F %H:%M:%S")

echo setreading aWATTar mittelwertOpt $mittelwertOpt | nc 127.0.0.1 7072
echo setreading aWATTar mittelwertGesamt $mittelwertGesamt | nc 127.0.0.1 7072
echo setreading aWATTar mittelwertRest $mittelwertRest | nc 127.0.0.1 7072
echo setreading aWATTar startzeit $isoTime | nc 127.0.0.1 7072
