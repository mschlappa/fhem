##############################################################################
#
# 70_KEBA.pm
#
# a module to send/receive messages or send commands to/from a 
# KEBA KeContact P20 Wallbox (c-Series with Ethernet option only). 
#
# This wallbox is intended to load Electric Vehicles
#
# written 2015 by Marcus Schlappa <mschlappa at gmx dot de>
#
# Version = 1.1   02.12.2015
#
##############################################################################



package main;
use strict;
use warnings;
use JSON;
use Scalar::Util qw(looks_like_number);

my %KEBA_gets = (
  "info"   => "i",
  "update" => "report"
);



my %KEBA_sets = (
  "enableState" => "ena",
  "current"     => "curr",
  #"failsave"    => "failsave",
  "outputX2"    => "output"
);



my %KEBA_state = (
  0 => "starting",
  1 => "not ready for charging",
  2 => "ready for charging",
  3 => "charging",
  4 => "error",
  5 => "authorization rejected"
);



my %KEBA_plug = (
  0 => "unplugged",
  1 => "plugged on wallbox",
  3 => "plugged on wallbox, locked",
  5 => "plugged on wallbox and ev",
  7 => "plugged on wallbox and ev, locked"
);



my %KEBA_enablestate = (
  0 => "disabled",
  1 => "enabled"
);



my %KEBA_output = (
  0 => "open",
  1 => "closed"
);



sub KEBA_Initialize($) {

  my ($hash) = @_;

  $hash->{DefFn}      = 'KEBA_Define';
  $hash->{UndefFn}    = 'KEBA_Undef';
  $hash->{SetFn}      = 'KEBA_Set';
  $hash->{GetFn}      = 'KEBA_Get';
  $hash->{ReadFn}     = 'KEBA_Read';
  $hash->{AttrList}   = $readingFnAttributes;
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



sub KEBA_Undef($$)    
{                     
  my ( $hash, $arg ) = @_; 
  my $socket = $hash->{CD};    
  if ($socket) {close($socket);}
  RemoveInternalTimer($hash);    
  return undef;                  
}    



sub KEBA_connect($){

  my ($hash) = @_;

  my $name = $hash->{NAME};
  my $ip = $hash->{Host};
  my $port = $hash->{Port};
	
  my $socket = IO::Socket::INET->new(Proto => 'udp', LocalPort => $port);
	
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
  my $socket = $hash->{CD};
  
  my $commandStack;
  my $command;
  
  if (defined ($hash->{Command})){
  	$commandStack = $hash->{Command};
	my @a = split(/#/,$commandStack,2);
	$command = $a[0];
	$commandStack = $a[1];
	$hash->{Command} = $commandStack;

  } else{
	Log 3, "KEBA sendCommand: No Command to send";  
	return;
  }
  
  my $response;

  if (!(defined $command)){
    return;
  }

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
  Log 3, "Data: $response";
  
  $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );
  
  my $first = substr($response,0,1);

  if ($first ne "{"){
   $hash->{LAST_MESSAGE} = $response;
   Log 3, "received message: $response";
   return;
  }
 
  my $decoded = decode_json($response);

  readingsBeginUpdate($hash);

  foreach my $key (keys %{$decoded}){

    my $value = $decoded->{$key};
    $key =~ tr/ //d;

    if ($key eq "State"){
      $value = $KEBA_state{$value};     

    }elsif ($key eq "Plug"){
      $value = $KEBA_plug{$value};  

    }elsif ($key eq "Enablesys" || $key eq "Enableuser"){
      $value = $KEBA_enablestate{$value};    

    }elsif ($key eq "Output"){
      $value = $KEBA_output{$value};     

    }else {
	  Log 4, "KEBA: No Mapping found: $key"; 	
     
    }
    readingsBulkUpdate($hash, $key, $value);

  } 
  readingsEndUpdate($hash, 1);

  #send futher command if exists in command Queue
  KEBA_sendCommand($hash);
  
}



sub KEBA_Get($@) {

  my ($hash, @param) = @_;

  return '"get KEBA" needs at least one argument' if (int(@param) < 2);

  return '"get KEBA" has no parameter' if (int(@param) > 2);

  my $name = shift @param;
  my $opt = shift @param;

  return '"get KEBA $opt" has no parameter' if (int(@param) > 2);

  if(!$KEBA_gets{$opt}) {
    my @cList = keys %KEBA_gets;
    return "Unknown argument $opt, choose one of " . join(" ", @cList);
  }
  
  my $cmd = $KEBA_gets{$opt};

  # get Commands in Queue
  my $commandStack;
  
  if (defined ($hash->{Command})){
  	$commandStack = $hash->{Command};
  } 

  if ($opt eq "update"){

    # prepare new commands
    my $commands = "$cmd 1#$cmd 2#$cmd 3#";

    # add new commands
    $commandStack = $commandStack.$commands;

    $hash->{Command}  = $commandStack; 

    KEBA_sendCommand($hash);

  }elsif($opt eq "info"){

    # prepare new command
    my $commands = "$cmd";
	
    # add new commands
    $commandStack = join("#",$commands);
	
    # write Command-Queue back to hash
    $hash->{Command}  = $commandStack; 

    KEBA_sendCommand($hash);
	  
  }else{
  	
    Log 3, "Unknown command: $cmd";
  }

	
}



sub KEBA_Set($@) {
	
  my ($hash, @param) = @_;
	
  #return 'set KEBA needs at least one argument and option' if (int(@param) < 3);
	
  my $name = shift @param;
  my $opt = shift @param;
  my $value = join("", @param);

  if(!defined($KEBA_sets{$opt})) {
    my @cList = keys %KEBA_sets;
    return "Unknown argument $opt, choose one of " . join(" ", @cList);
  }

  if (!looks_like_number($value)){
	  return "Parameter must be a number";
  }

  if ($opt eq "current" && ($value < 6000 || $value > 63000)){
	  return "The value for current must be between 6000 and 63000";
	  
  }elsif ($opt eq "enableState" && ($value < 0 || $value > 1)){
	  return "The value for enableState must be 0 (disable) or 1 (enable)";
	  
  }elsif ($opt eq "outputX2" && ($value < 0 || $value > 150)){
	  return "The value for outputX2 must be\n 0 (open)\n 1 (closed)\n between 10 and 150 (Pulse output with the specified number of pulses (pulses / kWh))";
  }	
	
  	
  my $cmd = $KEBA_sets{$opt}." ".$value;

  # get Commands in Queue
  my $commandStack;
  
  if (defined ($hash->{Command})){
  	$commandStack = $hash->{Command};
  } 

  # prepare new command
  my $commands = $cmd;

  # add new commands
  $commandStack = join("#",$commands);
	
  # write Command-Queue back to hash
  $hash->{Command}  = $commandStack; 
  $hash->{STATE} = $cmd;

  Log 3 , "setCmd: $cmd";
	
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
