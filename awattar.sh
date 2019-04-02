#!/bin/bash
#
# Skript laedt aktuelle Preisinformationen des Stromanbieters aWATTar 
# ueber die REST-Schnittstelle herunter und speichert sie in einer
# SQLite Datenbank fuer spaetere Auswertungen.
# 
# Voraussetzungen:
#
# - SQLite muss im Pfad vorhanden sein 
#   (https://sqlite.org)         
#
# - Command-line JSON processor 'jq' muss vorhanden sein 
#   (https://github.com/stedolan/jq)
#
# von Marcus Schlappa
# mschlappa at gmx dot de
#
# v0.1 vom 02.04.2019
#
#

# aWATTar REST Api
fname=marketdata
url=https://api.awattar.de/v1/$fname 

#  SQLite DB-Name
dbname=$fname.db

# alte  Preisinfos loeschen
rm -f $fname

if [ ! -f $dbname ]
then
  echo $dbname existiert noch nicht und wird angelegt.
  sqlite3 $dbname "create table preis (beginn TIMESTAMP PRIMARY KEY , preis DECIMAL );"
else
  echo $dbname ist vorhanden.
fi
 

# lese den maximalen Timestamp aus der Preis-Tabelle
maxbeginn=$(sqlite3 $dbname "select max(beginn) from preis;")


# falls noch kein Datensatz vorhanden ist wird der aktuelle Timestamp gesetzt
if [ -z "$maxbeginn" ]
then
  maxbeginn=$(date +%s%N | cut -b1-13)
fi

maxbeginn=$[$maxbeginn+1]

echo aktuelle Preis-Daten herunterladen mit Beginn $maxbeginn 
curl -s $url?start=$maxbeginn >$fname

if [ ! -f $fname ]
then
  echo Preisinformationen konnten nicht geladen werden
  exit
fi



# Auswerten der heruntergeladenen Preisinfos
length=$(cat marketdata | jq '.data | length')

jq -c '.data | .[] | (.start_timestamp | tostring) + "," + (.marketprice | tostring )' $fname | while read i; do
  set=$(echo $i | cut -d '"' -f 2)
  sqlite3 $dbname "insert into preis (beginn,preis) values ($set);"
done

minpreis=$(sqlite3 $dbname "select beginn, min(preis) from preis;")

echo Der minimale Preis ist $minpreis


