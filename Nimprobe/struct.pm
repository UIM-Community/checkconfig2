use strict;
use warnings;

package Nimprobe::struct;
use Nimbus::API;
use Nimbus::PDS;
use Nimbus::CFG;
use Term::ANSIColor qw(:constants);
use Win32::Console::ANSI;

my $FH;

sub new {
    my ($class) = shift;
    my $name = shift;
    my $version = shift;
    my $CFG = new Nimbus::CFG("$name.cfg");
    my $this = {
        name        => $name,
        version     => $version,
        loglevel    => $CFG->{'setup'}->{'loglevel'} || 3,
        logfile     => $CFG->{'setup'}->{'logfile'} || "logs/$name.log",
        login       => $CFG->{'setup'}->{'login'} || "administrator",
        password    => $CFG->{'setup'}->{'password'} || "nimsoft01",
        sess        => undef
    };
    return bless($this,$class);
}

sub start {
    my $this = shift;

    unless(open($FH,">", "checkconfig.log")) {
        warn "Unabled to open super log files! \n";
        return;
    }

    my $rc = nimLogin("$this->{login}","$this->{password}");
    if(not $rc) {
        die "Unable to connect to the nimsoft HUB !\n";
    }

    $this->log("*************************************************",1);
    $this->log("Probe $this->{name} started at ".localtime(),1);
    $this->log("*************************************************",1);
    $this->localLog("*************************************************",1);
    $this->localLog("Probe $this->{name} started at ".localtime(),1);
    $this->localLog("*************************************************",1);
}

sub log {
    my ($this,$msg,$level) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $level = $level || 1;
    if($level <= $this->{loglevel}) {
        print YELLOW,"$hour:$min",RESET," : $msg\n",RESET;
    }
}

sub localLog {
    my ($this,$msg,$level) = @_;
    $level = $level || 3;
    if($level <= $this->{loglevel}) {
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        print $FH "$mday/$mon $hour:$min:$sec - $msg\n";
    }
}


sub close {
    my $this = shift;
    $this->log("*************************************************",1);
    $this->log("Probe $this->{name} ended at ".localtime(),1);
    $this->log("*************************************************",1);
    $this->localLog("*************************************************",1);
    $this->localLog("Probe $this->{name} ended at ".localtime(),1);
    $this->localLog("*************************************************",1);
    close $FH;
}

1;
