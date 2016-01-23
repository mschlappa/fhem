#!/usr/bin/perl
#
# ZE-Services
#
# Anzeige von Akkustand und Reichweite vom Renault Zoe in fhem
#
# Idee 'geklaut' von https://github.com/nabossha/ZEServices
# Vielen Dank an Nando Bosshart fuer die Vorarbeit !
#
# Quick & Dirty Portiert nach Perl von Marcus Schlappa 
# Aufruf kann z.B. in Cron alle 30min erfolgen
# 

use strict;
use WWW::Curl;
use WWW::Curl::Easy;
use XML::Simple;
use Data::Dumper;
use Time::Stamp;

# Zugangsdaten fuer Z.E. Services
my $username = "deinUsername" ;
my $password = "deinKennwort";
my $vin = "deineFahrgestellnummer";

# Adresse und Port von fhem Telnet Service
# Muss angepasst werden, falls fhem auf einer anderen Maschine laeuft
# in fhem muss ein Dummy-Device mit dem Namen zoe existieren
my $nccmd =  "nc 127.0.0.1 7072";

# Nachricht an Server zum Aufbau der Session
my $xml = '<ns1:SmartphoneNewLoginRequest xmlns:ns1="urn:com:renault:smartphone.userservices:v1" xmlns:ns3="urn:com:renault:gdc:type:user:v1" xmlns:ns4="urn:com:hitachi:gdc:type:authenticationmanagercommon:v1" xmlns:ns2="urn:com:hitachi:gdc:type:authenticationmanagercommon:v1">
	<SmartphoneNewLoginInfo>
		<ns1:UserNewLoginInfo>
			<ns4:UserId>'.$username.'</ns4:UserId>
			<ns4:Password>'.$password.'</ns4:Password>
		</ns1:UserNewLoginInfo>
		<ns1:DeviceToken></ns1:DeviceToken>
		<ns1:UUID></ns1:UUID>
		<ns1:Locale>DE</ns1:Locale>
		<ns1:AppVersion></ns1:AppVersion>
		<ns1:SmartphoneType>IPHONE</ns1:SmartphoneType>
		<CountryCode>DE</CountryCode>
	</SmartphoneNewLoginInfo>
</ns1:SmartphoneNewLoginRequest>';

# Serveradresse Z.E.Services
my $url = "https://rno-smartgtw.viaaq.eu/aqPortal/B2CSmartphoneProxy/UserService";

# HTTP Header
my @header = ("Content-type: text/xml","Content-length: ".length($xml));

my $response;

my $curl = WWW::Curl::Easy->new();
$curl->setopt(CURLOPT_URL, $url);
$curl->setopt(CURLOPT_HEADER, 1);
$curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);
$curl->setopt(CURLOPT_SSL_VERIFYHOST, 0);
$curl->setopt(CURLOPT_CUSTOMREQUEST, 'POST');
$curl->setopt(CURLOPT_POST, 1);
$curl->setopt(CURLOPT_POSTFIELDS, $xml);
$curl->setopt(CURLOPT_HTTPHEADER, \@header);
$curl->setopt(CURLOPT_WRITEDATA, \$response);
my $ret = $curl->perform;

#check for curl-errors:
my $error = $curl->errbuf();
  if($ret != 0){
    print "200 - Curl error: ".$error;
    return;
  }
#check for 404:
my $httpCode = $curl->getinfo(CURLINFO_HTTP_CODE);
  if($httpCode == 404) {
    print "210 - Curl error 404: ".$url;
    return;
  }

#separating header and body gets SESSION-ID and XML-data:
my $header_size = $curl->getinfo(CURLINFO_HEADER_SIZE);
my $header = substr($response, 0, $header_size);

#close $curl neccessary?

#print $header;

#get cookie and set the current session-variable:
my @matches = ($header =~ m/^Set-Cookie:\s*([^;]*)/mi); 
my $currentSession;
foreach my $item (@matches[0]) {
  $currentSession = $item;
}

#print $currentSession;

###### Get Remote Status from Z.E. Services

my $xml = '<ns4:SmartphoneGetNewCurrentDataRequest xmlns:ns3="urn:com:renault:gdc:type:portalcommon:v1" xmlns:ns4="urn:com:renault:gdc:type:smartphoneEvDashboard:v1" xmlns:ns2="urn:com:renault:gdc:type:evDashboard:v1">
		<ns3:VehicleServiceRequestHeader>
			<ns3:VIN>'.$vin.'</ns3:VIN>
			<ns3:Caller>SMARTPHONE-APP</ns3:Caller>
		</ns3:VehicleServiceRequestHeader>
	</ns4:SmartphoneGetNewCurrentDataRequest>';

my $url = "https://rno-smartgtw.viaaq.eu/aqPortal/B2CSmartphoneProxy/EvDashboardService";

my $curl = WWW::Curl::Easy->new();

my @header = ("Content-type: text/xml","Content-length: ".length($xml));

my $response;

#add our session cookie!
$curl->setopt(CURLOPT_COOKIE, $currentSession);
$curl->setopt(CURLOPT_URL, $url);
$curl->setopt(CURLOPT_HEADER, 1);
$curl->setopt(CURLOPT_SSL_VERIFYPEER, 0);
$curl->setopt(CURLOPT_SSL_VERIFYHOST, 0);
$curl->setopt(CURLOPT_CUSTOMREQUEST, 'POST');
$curl->setopt(CURLOPT_POST, 1);
$curl->setopt(CURLOPT_POSTFIELDS, $xml);
$curl->setopt(CURLOPT_HTTPHEADER, \@header);
$curl->setopt(CURLOPT_WRITEDATA, \$response);

my $ret = $curl->perform;

#separating header and body gets SESSION-ID and XML-data:
my $header_size = $curl->getinfo(CURLINFO_HEADER_SIZE);
my $data = substr($response, $header_size);

my $ref = XMLin($data);

#print Dumper $ref;

#my $echocmd =  "echo setreading zoe $key $value";
#my $nccmd =  "nc 127.0.0.1 7072";

#system(" $echocmd | $nccmd ");

my $key;
my $value;
my $echocmd;


$key = "akku";
$value = $ref->{'ns3:GetCurrentDataResponse'}->{'StateOfCharge'}->{'ns3:BatteryStatus'}->{'ns3:BatteryRemainingPercent'};
$echocmd =  "echo setreading zoe $key $value";
system(" $echocmd | $nccmd ");

$key = "reichweite";
$value = $ref->{'ns3:GetCurrentDataResponse'}->{'StateOfCharge'}->{'ns3:BatteryStatus'}->{'ns3:CruisingRange'};
$echocmd =  "echo setreading zoe $key $value";
system(" $echocmd | $nccmd ");

$key = "zeitpunkt";
$value = $ref->{'ns3:GetCurrentDataResponse'}->{'StateOfCharge'}->{'ns3:OperationDateAndTime'};
my $unixTs  = Time::Stamp::parsegm($value);
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($unixTs);
$value = "$hour:$min:$sec"; 
$echocmd =  "echo setreading zoe $key $value";
system(" $echocmd | $nccmd ");
