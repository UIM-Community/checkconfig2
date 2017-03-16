package Libs::Tools;
use strict;
use warnings;
use Exporter qw(import);

use lib "D:/apps/Nimsoft/perllib";
use lib "D:/apps/Nimsoft/Perl64/lib/Win32API";
use Nimbus::API;
use Nimbus::Session;
use Nimbus::CFG;
use Nimbus::PDS;

our @EXPORT_OK = qw(createDir LogTime Request);

sub createDir {
	my @dir = split(";",shift);
    foreach(@dir) {
        if( !(-d "$_") ) {
            # $NMS_Logger("Create local directory named $dir");
            mkdir("$_") or die "Unable to create $_ directory!";
        }
    }
}

sub Request {
	my $PDS = pdsCreate();
	my ($RC,$RQ) = nimNamedRequest(shift,shift,$PDS,1);
	pdsDelete($PDS);
	return ($RC,$RQ);
}

sub LogTime {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d%02d%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
	$nice_timestamp =~ s/\s+/_/g;
	$nice_timestamp =~ s/://g;
    return $nice_timestamp;
}
