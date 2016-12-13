use strict;
use warnings;

package Nimprobe::robot;
use lib "D:/apps/Nimsoft/perllib";
use lib "D:/apps/Nimsoft/Perl64/lib/Win32API";
use Nimbus::API;
use Nimbus::PDS;
use Nimbus::CFG;
use DBI;

sub new {
    my ($class,$id,$hubid,$opt) = @_;
    my $this = {
        id          => $id,
        hubid       => $hubid,
        name        => $opt->get("name"),
        origin      => $opt->get("origin"),
        addr        => $opt->get("addr"),
        version     => $opt->get("version"),
        ip          => $opt->get("ip"),
        status      => $opt->get("status"),
        os_major    => $opt->get("os_major"),
        os_minor    => $opt->get("os_minor"),
        os_user1    => $opt->get("os_user1"),
        os_user2    => $opt->get("os_user2"),
        os_description => $opt->get("os_description")
    };
    return bless($this,ref($class) || $class);
}

sub insert {
    my ($this,$DB) = @_;
    my $request;
    $request = $DB->prepare("INSERT INTO robots_list (id,hubid,origin,name,ip,versions,status,os_major,os_minor,os_user1,os_user2,os_description) VALUES(NULL,?,?,?,?,?,?,?,?,?,?,?)");
    $request->execute(
        $this->{hubid},
        $this->{origin},
        $this->{name},
        $this->{ip},
        $this->{version},
        $this->{status},
        $this->{os_major},
        $this->{os_minor},
        $this->{os_user1},
        $this->{os_user2},
        $this->{os_description}
    );
    $request->finish;
}

sub probeCallback {
    my ($this,$DB,$code,$time) = @_;
    my $request;
    $request = $DB->prepare("UPDATE robots_list SET probeslist_success=? , probeslist_responsetime=? WHERE id=?");
    $request->execute($code,$time,$this->{id});
    $request->finish;
}

1;
