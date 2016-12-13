use strict;
use warnings;

package Nimprobe::hub;
use lib "D:/apps/Nimsoft/perllib";
use lib "D:/apps/Nimsoft/Perl64/lib/Win32API";
use Nimbus::API;
use Nimbus::PDS;
use Nimbus::CFG;
use DBI;

sub new {
    my ($class,$id,$opt) = @_;
    my $this = {
        id          => $id,
        name        => $opt->get("name"),
        robotname   => $opt->get("robotname"),
        domain      => $opt->get("domain"),
        origin      => $opt->get("origin"),
        ip          => $opt->get("ip"),
        version     => $opt->get("version"),
        tunnel      => ($opt->get("tunnel_ip")) ? "YES" : "NO",
        source      => ($opt->get("source")) ? 1 : 0
    };
    return bless($this,ref($class) || $class);
}

sub insert {
    my ($this,$DB) = @_;
    my $request;
    $request = $DB->prepare("INSERT INTO hubs_list (id,domain,origin,name,ip,versions,tunnel) VALUES(NULL,?,?,?,?,?,?)");
    $request->execute(
        $this->{domain},
        $this->{origin},
        $this->{name},
        $this->{ip},
        $this->{version},
        $this->{tunnel}
    );
    $request->finish;
}

sub robotCallback {
    my ($this,$DB,$code,$time) = @_;
    my $request;
    $request = $DB->prepare("UPDATE hubs_list SET getrobots_success=? , getrobots_time=? WHERE id=?");
    $request->execute(
        $code,
        $time,
        $this->{id}
    );
    $request->finish;
}

sub robotAll {
    my ($this,$DB,$time) = @_;
    my $request;
    $request = $DB->prepare("UPDATE hubs_list SET getallrobots_time=? WHERE id=?");
    $request->execute(
        $time,
        $this->{id}
    );
    $request->finish;
}

1;
