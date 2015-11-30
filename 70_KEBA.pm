##############################################################################
#
# 70_KEBA.pm
#
# a module to send/receive messages or send commands 
# to a KEBA P20 Wallbox with Ethernet. 
#
# This wallbox is intended to load Electric Vehicles
#
# written 2015 by Marcus Schlappa <mschlappa at gmx.de>
#
# Version = 1.0   29.11.2015
#
##############################################################################


package main;
use strict;
use warnings;
use Blocking;
use JSON;

my %KEBA_gets = (
	"info"	=> "i",
	"report1"	=> "report 1",
	"report2"  => "report 2",
	"report3"  => "report 3",
);

my %KEBA_sets = (
	"enable"	=> "ena 1",
	"disable"	=> "ena 0"
	#"current"  => "curr"
);





sub KEBA_Initialize($) {

    my ($hash) = @_;

    $hash->{DefFn}      = 'KEBA_Define';
    $hash->{SetFn}      = 'KEBA_Set';
    $hash->{GetFn}      = 'KEBA_Get';
    $hash->{ReadFn}     = 'KEBA_Read';
}





sub KEBA_Define($$) {
	
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    
    if(int(@param) != 4) {
		return "KEBA_Define: number of arguments incorrect. Usage:\n" .
		         "define <name> KEBA <host> <port>";
    }

    $hash->{Host}  = $param[2];
    $hash->{Port} = $param[3];
	
	Log3 $hash, 3, "$hash->{NAME} will read from KEBA at $hash->{Host}:$hash->{Port} " ;
 
    KEBA_connect($hash);

}





sub KEBA_connect($){

    my ($hash) = @_;

    my $name = $hash->{NAME};
    my $ip = $hash->{Host};
    my $port = $hash->{Port};
	
    my $socket = IO::Socket::INET->new(
          Proto    => 'udp',
		  LocalPort => $port
      );
	
	if($socket) {

		$hash->{STATE} = "Listening";
	    $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );

	    $hash->{FD}    = $socket->fileno();
	    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
	    $hash->{CONNECTS}++;
	    $selectlist{$name} = $hash;
		
	    Log3 $name, 3, "listening for $name on $hash->{Port}";
	}else{
		Log3 $name, 3, "socket could not be created!";
	}
}





sub KEBA_sendCommand($)
{
 my ($hash) = @_;

 my $name = $hash->{NAME};
 my $ip = $hash->{Host};
 my $port = $hash->{Port};
 my $command = $hash->{Command};
 my $socket = $hash->{CD};

 my $response;

 Log 3, "$name Sending command: ".$command;

 my $ipaddr = inet_aton($ip);
 my $destaddr = sockaddr_in($port, $ipaddr);
 send($socket, $command, 0, $destaddr);
 Log 3, "$name Command was sent";
 
}





sub KEBA_Read($){
  
  my ($hash) = @_;
  my $socket = $hash->{CD};
  my $response;
 
  $socket->recv($response,512);

  Log 3, "Message received";
  Log 4, "Data: $response";
  
  $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );
  
  my $first = substr($response,0,1);

  # keine JSON Nachricht => Direkte Ausgabe im Reading 'LASTMSG'
  if ($first ne "{"){
   $hash->{LAST_MESSAGE} = $response;
   Log 3, "received message: $response";
   return;
  }
 
  my $decoded = decode_json($response);

  readingsBeginUpdate($hash);

  foreach my $key (keys $decoded){

    my $value = $decoded->{$key};
    $key =~ tr/ //d;
    readingsBulkUpdate($hash, $key, $value);

  }
 
  readingsEndUpdate($hash, 1);
  
}





sub KEBA_Get($@) {

	my ($hash, @param) = @_;
	
	return '"get KEBA" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;

	if(!$KEBA_gets{$opt}) {
		my @cList = keys %KEBA_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	
	if($attr{$name}{formal} eq 'yes') {
	    return $KEBA_gets{$opt}.', sir';
    }
    
	$hash->{Command}  = $KEBA_gets{$opt};
    KEBA_sendCommand($hash);
	
}





sub KEBA_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set KEBA" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
	
	if(!defined($KEBA_sets{$opt})) {
		my @cList = keys %KEBA_sets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	
	$value = $KEBA_sets{$opt};
	
    $hash->{STATE} = $value;
	$hash->{Command}  = $value;
	
	KEBA_sendCommand($hash);
    
}



1;

=pod
=begin html

<a name="KEBA"></a>
<h3>KEBA</h3>
<ul>
    <i>KEBA</i> Allows you to control KEBA P20 Wallbox with Ethernet Option.
    <br><br>
    <a name="KEBAdefine"></a>
    <b>Define</b>
    <ul>
        <code>define <name> KEBA <ip> <port></code>
        <br><br>
        Example: <code>define &lt;name&gt; KEBA &lt;host&gt; &lt;port&gt;</code><br>
    </ul>
    <br>
    
    <a name="KEBAset"></a>
    <b>Set</b><br>
    <ul>
        <code>set <name> <option></code>
        <br><br>
        You can enable or disable the wallbox with <i>set</i> command.
        <br><br>
    </ul>
    <br>

    <a name="KEBAget"></a>
    <b>Get</b><br>
    <ul>
        <code>get <name> <option></code>
        <br><br>
        You can <i>get</i> the status of the wallbox via info report1-3 
    </ul>
    <br>    
</ul>

=end html

=cut￿
