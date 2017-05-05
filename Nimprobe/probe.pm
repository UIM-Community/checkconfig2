package Nimprobe::probe;
use lib "D:/apps/Nimsoft/perllib";
use lib "D:/apps/Nimsoft/Perl64/lib/Win32API";
use Nimbus::API;
use Nimbus::PDS;
use Nimbus::CFG;
use DBI;

my $ID = 0;

my %PCM = (
    cdm => {
        custom => {
            pattern => 'disk,custom'
        }
    },
    processes => {
        watcher => {
            pattern => 'watchers'
        }
    },
    logmon => {
        profiles => {
            pattern => 'profiles'
        }
    },
    ntservices => {
        services => {
            pattern => 'services',
            needed_key => {
                active => 'yes'
            }
        }
    },
    ntevl => {
        logs => {
            pattern => 'logs'
        }
    },
    dirscan => {
        watcher => {
            pattern => 'watchers'
        }
    }
);


sub new {
    my ($class,$robotid,$opt,$env) = @_;
    $ID++;
    my $this = {
        id          => $ID,
        robotid     => $robotid,
        env         => $env,
        name        => $opt->{$env}{"name"},
        logfile     => $opt->{$env}{"logfile"},
        config      => $opt->{$env}{"config"},
        type        => $opt->{$env}{"type"},
        description => $opt->{$env}{"description"},
        active      => $opt->{$env}{"active"},
        group       => $opt->{$env}{"group"},
        version     => $opt->{$env}{"pkg_version"},
        build       => $opt->{$env}{"pkg_build"},
        process_state => $opt->{$env}{"process_state"} || "unknown",
        pathCFG     => undef
    };
    return bless($this,ref($class) || $class);
}

sub insert {
    my ($this,$DB) = @_;
    my $request;
    $request = $DB->prepare("INSERT INTO probes_list (id,robotid,name,active,versions,build,process_state) VALUES(NULL,?,?,?,?,?,?)");
    $request->execute(
        $this->{robotid},
        $this->{name},
        $this->{active},
        $this->{version},
        $this->{build},
        $this->{process_state}
    );
    $request->finish;
}

sub callbackCONF {
    my ($this,$DB,$code,$time) = @_;
    my $request;
    $request = $DB->prepare("UPDATE probes_list SET getconfig_responsetime=? , getconfig_success=? WHERE id=?");
    $request->execute($time,$code,$this->{id});
    $request->finish;
    return 1;
}

sub scanCONF {
    my ($this,$ProbePDS_CFG,$path) = @_;
    my $CFG_Handler;
    unless(open($CFG_Handler,">>","$path")) {
        warn "\nUnable to create file\n";
        return 0;
    }
    $this->{pathCFG} = $path;
    my @ARR_CFG_Config = Nimbus::PDS->new($ProbePDS_CFG)->asHash();
    print $CFG_Handler $ARR_CFG_Config[0]{'file_content'};
    close $CFG_Handler;
    return 1;
}

sub parseCONF {
    my ($this,$DB) = @_;
    my $monitored = $this->{env};
    if($PCM{$monitored}) {

        my $tempCFG = Nimbus::CFG->new("$this->{pathCFG}");
        foreach my $monitoredSection ( keys %{ $PCM{$monitored} } ) {
            my @array = split(",",$PCM{$monitored}{$monitoredSection}{pattern});
            my $final;
            if(scalar @array > 1) {
                for my $i (0 .. $#array) {
                    if($i == 0) {
                        $final = $tempCFG->{$array[$i]};
                    }
                    else {
                        $final = $final->{$array[$i]};
                    }
                }
            }
            else {
                $final = $tempCFG->{$PCM{$monitored}{$monitoredSection}{pattern}};
            }
            undef $tempCFG;
            undef @array;

            foreach my $key ( keys %{ $final } ) {
                my $Authorize_Insert = 1;
                my $ActiveVal = $final->{$key}{active};
                if($PCM{$monitored}{$monitoredSection}{needed_key}) {
                    foreach my $CONF_STR_Profile ( keys $PCM{$monitored}{$monitoredSection}{needed_key} ) {
                        if($final->{$key} ne '') {
                            if($PCM{$monitored}{$monitoredSection}{needed_key}{$CONF_STR_Profile} ne $final->{$key}{active}) {
                                $Authorize_Insert = 0;
                            }
                        }
                        else {
                            $Authorize_Insert = 0;
                        }
                    }
                }
                if($Authorize_Insert) {
                    my $INSERT_CONF = $DB->prepare("INSERT INTO probes_config (id,probeid,probe,profile,active) VALUES(NULL,?,?,?,?)");
                    if(lc $monitored eq "cdm") {
                        $key =~ s/#/\//g;
                    }
                    elsif(lc $monitored eq "logmon") {
                        $key =~ s/\//#/g;
                    }
                    $INSERT_CONF->execute($this->{id},uc $monitored,$key,$ActiveVal);
                    $INSERT_CONF->finish;
                }
            }

        }

    }
}

1;
