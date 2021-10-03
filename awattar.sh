#!/bin/bash
#
# Beim Stromanbieter aWATTar aendern sich im Tarif 'HOURLY' 
# die Strompreise stuendlich.
#
# Dieses Skript laedt aktuelle Preisinformationen des Stromanbieters
# ueber deren REST-Schnittstelle herunter und gibt den Startzeitpunkt 
# des preisoptimalen Zeitfensters als Timestamp (Unix Epoche) zurueck.
#
# Als Parameter wird ein positiver Integerwert uebergeben, der 
# die Groesse des gewuenschten Zeitfensters in Stunden angibt. Wenn kein 
# Parameter uebergeben wurde wird das Zeitfenster mit 1(h) angenommen.
# 
# Voraussetzungen:
#
# - Command-line JSON processor 'jq' muss vorhanden sein 
#   (https://github.com/stedolan/jq)
#
# - Command GNU bc muss vorhanden sein
#
#
# von Marcus Schlappa
# mschlappa at gmx dot de
#
# v0.3 vom 03.10.2021
#
#

# URI der aWATTar REST Api
fname=marketdata
url=https://api.awattar.de/v1/$fname 

# Path to 'jq'
jqcmd=/usr/local/bin/jq

# Uebergebener Parameter gibt die Groesse des Zeitfensters in Stunden an
windowsize=$1

# Wenn kein Parameter uebergeben wurde, ist das Zeitfenster 1(Stunde)
if [ "$#" -ne 1 ]
then
    windowsize=1
fi

# Das Zeitfenster darf nicht beliebig gewaehlt werden
if [[ $windowsize -lt 1 || $windowsize -gt 6 ]] 
then 
  echo "Zeitfenster muss groesser 0 und kleiner als 7 sein"
  exit 1;
fi


# ggf. alte  Preisinfos loeschen
rm -f $fname

# aktuelle Preis-Daten herunterladen
curl -k -s $url >$fname

if [ ! -f $fname ]
then
  echo "Preisinformationen konnten nicht geladen werden"
  exit 2;
fi



# Anzahl der heruntergeladenen Preis-Intervalle
length=$(cat marketdata | $jqcmd '.data | length')

# Groesse der Arrays bestimmen
asize=$[$length+$windowsize-1]

# Arrays (Timestamp/ Preis) mit passender Groesse initialisieren und vorbelegen
declare -a zeit=( $(for i in $(seq 1 $asize); do echo 0; done) )
declare -a preis=( $(for i in $(seq 1 $asize); do echo 9999; done) )



# Array mit den gelesenen Werten der REST Schnittstelle fuellen
count=0;
mittelwert=0;
while read i; do
  t=$(echo $i | cut -d '"' -f 2 | cut -d ',' -f 1);
  p=$(echo $i | cut -d '"' -f 2 | cut -d ',' -f 2);
  zeit[$count]=$t;
  preis[$count]=$p;
  count=$[$count+1];
  mittelwert=$(bc <<< "scale=0;$mittelwert+($p*100)/1");
done < <($jqcmd -c '.data | .[] | (.start_timestamp | tostring) + "," + (.marketprice | tostring )' $fname)



# Finde Minimum
 min=999999
 # Schleife ueber alle Preise
 for n in $(seq $windowsize $asize); do
   index=$[$n-$windowsize]
   sum=0;
   # Alle Werte im Zeitfenster addieren
   for m in $(seq 1 $windowsize); do
    index2=$[$index+$m-1]
    p=${preis[$index2]}
    sum=$(bc <<< "scale=0;$sum+($p*100)/1")
   done
   # Ggf. gefundenes neues Minimum merken
   (( $sum < $min )) && min=$sum && minindex=$index
 done


# Rueckgabe des preisoptimalen Start-Zeitpunkts als Unix Epoch
startzeitpunkt=$(bc <<< "${zeit[$minindex]}/1000");

# Mittelwert des Preises innerhalb des preisoptimalen Zeitfensters
mittelwertOpt=$(bc <<< "scale=2;$min/$windowsize*1.19/1000"); 

# Mittelwert des Preises ueber alle gelesenen Werte
mittelwertGesamt=$(bc <<< "scale=2;$mittelwert/$length*1.19/1000"); 

# Mittelwert des Preises ohne die Preise im optimalen Zeitfenster
mittelwertRest=$(bc <<< "scale=1;($length*$mittelwertGesamt-($windowsize*$mittelwertOpt))/($length-$windowsize)");

# Rueckgabe der Ergebnisse
echo $startzeitpunkt $mittelwertOpt $mittelwertGesamt $mittelwertRest
