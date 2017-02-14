use strict;
use warnings;

# ************************************************* #
# Chargement des librairies !
# ************************************************* #
use lib "D:/apps/Nimsoft/perllib";
use lib "D:/apps/Nimsoft/Perl64/lib/Win32API";
use Nimbus::API;
use Nimbus::CFG;
use Nimbus::PDS;

# ************************************************* #
# Chargement des packages !
# ************************************************* #
use Nimprobe::struct;
use Nimprobe::hub;
use Nimprobe::robot;
use Nimprobe::probe;
use Libs::Tools;
use Cwd;
use Time::HiRes qw( time );
use DBI;
use Term::ANSIColor qw(:constants);
use Win32::Console::ANSI;
use File::Copy;

# ************************************************* #
# Global vars
# ************************************************* #
my $LOG = 1;
my $GBL_Time_ScriptExecutionTime = time();
my $GBL_Time_ExecutionTimeStart = Libs::Tools::LogTime();
my $GBL_STR_ProbeName = "checkconfig";
my $GBL_STR_ProveVersion = "2.6";
my $GBL_STR_Directory = getcwd;
my $GBL_STR_RemoteHUB = "hub";
my $GBL_STR_Time_Format = "%.2f";
my $GBL_INT_FailCount = 0;
my $DB;

my $CFG = Nimbus::CFG->new("$GBL_STR_ProbeName.cfg");

my %GBL_Hash_Hubs = ();
{
    my @Temp_Hubs = split(",",$CFG->{"monitoring"}->{"hubs_list"});
    foreach(@Temp_Hubs) {
        $GBL_Hash_Hubs{$_} = 1;
    }
}
my %Excluded_Robots;
{
    my @Temp_Excluded_Robots = split(",",$CFG->{"monitoring"}->{"excluded_robots"});
    foreach(@Temp_Excluded_Robots) {
        $Excluded_Robots{$_} = 1;
    }
}
my @MonitoredProbes = split(",",$CFG->{"monitoring"}->{"monitored_probes"});
my $GetRobotConfiguration = $CFG->{"monitoring"}->{"get_probes_configuration"};
my $hubs_restrict = $CFG->{"monitoring"}->{"hubs_restrict"};
my $conf_commit = $CFG->{"monitoring"}->{"conf_commit"};
my $get_probes_log = $CFG->{"monitoring"}->{"get_probes_log"};
my $get_packages = $CFG->{"monitoring"}->{"get_packages"} || 0;
my $robot_secondcheck = $CFG->{"monitoring"}->{"robots_secondcheck"};

# Load WITH -F param !
my $RobotTXT = 0;
my %RobotsHash_TXT = ();

# ************************************************* #
# Create local directory for the probes
# ************************************************* #
Libs::Tools::createDir("Output;Output/$GBL_Time_ExecutionTimeStart");

# ************************************************* #
# Création et configuration de la probe !
# ************************************************* #
my $NMS_Probe;
$NMS_Probe = new Nimprobe::struct($GBL_STR_ProbeName,$GBL_STR_ProveVersion);
$NMS_Probe->start();
{
    sub breakApplication { # Ctrl-C key in console-mode for breaking script !
        print "\n\n!!! CTRL-C BREAKING CONSOLE !!!\n\n";
        $DB->commit;
        $DB->disconnect;
        exit(1);
    }
    $SIG{INT} = \&breakApplication;
}


# ************************************************* #
# Requête SQL cross platform
# ************************************************* #
my %RequeteSQL = (
    "SQLite" => {
        createHUB => "CREATE TABLE IF NOT EXISTS hubs_list (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL,
            domain TEXT NOT NULL,
            origin TEXT,
            ip TEXT NOT NULL,
            versions VARCHAR(255),
            tunnel VARCHAR(10) NOT NULL,
            getrobots_success TINYINT,
            getrobots_time INTEGER,
            getallrobots_time INTEGER
        )",
        createROBOT => "CREATE TABLE IF NOT EXISTS robots_list (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hubid INTEGER NOT NULL,
            status TINYINT NOT NULL,
            os_major TEXT,
            os_user1 TEXT,
            os_user2 TEXT,
            os_minor TEXT,
            os_description TEXT,
            name VARCHAR(255) NOT NULL,
            ip TEXT NOT NULL,
            origin TEXT NOT NULL,
            versions VARCHAR(255),
            probeslist_success TINYINT,
            probeslist_responsetime INTEGER,
            packages_success TINYINT,
            FOREIGN KEY(hubid) REFERENCES hubs_list(id)
        )",
        createPROBE => "CREATE TABLE IF NOT EXISTS probes_list (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            robotid INTEGER NOT NULL,
            name TEXT NOT NULL,
            active TINYINT NOT NULL,
            versions VARCHAR(255),
            build INTEGER,
            process_state TEXT,
            getconfig_success TINYINT,
            getconfig_responsetime INTEGER,
            FOREIGN KEY(robotid) REFERENCES robots_list(id)
        )",
        createPKG => "CREATE TABLE IF NOT EXISTS packages_list (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            robotid INTEGER NOT NULL,
            name VARCHAR(255) NOT NULL,
            description TEXT,
            version VARCHAR(255),
            build VARCHAR(255),
            date DATE,
            install_date DATE,
            FOREIGN KEY(robotid) REFERENCES robots_list(id)
        )",
        createMISSING => "CREATE TABLE IF NOT EXISTS missing_probes (
            robotid INTEGER NOT NULL,
            name TEXT NOT NULL,
            FOREIGN KEY(robotid) REFERENCES robots_list(id)
        )",
        createCONF => "CREATE TABLE IF NOT EXISTS probes_config (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            probeid INTEGER NOT NULL,
            probe TEXT NOT NULL,
            profile TEXT NOT NULL,
            FOREIGN KEY(probeid) REFERENCES probes_list(id)
        )",
        dropROBOT => 'DROP TABLE IF EXISTS robots_list;',
        dropPROBE => 'DROP TABLE IF EXISTS probes_list;',
        dropHUB => 'DROP TABLE IF EXISTS hubs_list;',
        dropCONF => 'DROP TABLE IF EXISTS probes_config;',
        dropMISSING => 'DROP TABLE IF EXISTS missing_probes;',
        dropPKG => 'DROP TABLE IF EXISTS packages_list;'
    }
);
$RequeteSQL{"MySQL"} = $RequeteSQL{"SQLite"};

my $DB_File = "checkconfig.db";
if(-e $DB_File) {
    print "Unlink database file!\n";
    unlink($DB_File);
}

# ************************************************* #
# Connexion et Hydratation
# ************************************************* #
my $GBL_STR_DB_Type = $CFG->{"database"}->{"type"};
my $GBL_STR_DB_File = $CFG->{"database"}->{"file"};
my $GBL_STR_DB_User = $CFG->{"database"}->{"user"};
my $GBL_STR_DB_Pass = $CFG->{"database"}->{"pass"};
my $GBL_BOOL_DB_Err = $CFG->{"database"}->{"err"};
my $GBL_STR_DB_Host = $CFG->{"database"}->{"host"};
my $GBL_STR_DB_Port = $CFG->{"database"}->{"port"};
{
    if($GBL_STR_DB_Type eq "MySQL") {
        $DB = DBI->connect("DBI:mysql:database=$GBL_STR_DB_File;host=$GBL_STR_DB_Host;port=$GBL_STR_DB_Port","$GBL_STR_DB_User","$GBL_STR_DB_Pass",{
            RaiseError => $GBL_BOOL_DB_Err,
            AutoCommit => 0
        }) or die DBI::errstr;
    }
    elsif($GBL_STR_DB_Type eq "SQLite") {
        $DB = DBI->connect("dbi:$GBL_STR_DB_Type:dbname=$GBL_STR_DB_File.db","$GBL_STR_DB_User","$GBL_STR_DB_Pass",{
            RaiseError => $GBL_BOOL_DB_Err,
            AutoCommit => 0
        }) or die DBI::errstr;
    }

    # Create and Drop database !
    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{dropHUB});
    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{createHUB});

    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{dropROBOT});
    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{createROBOT});

    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{dropPROBE});
    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{createPROBE});

    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{dropPKG});
    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{createPKG});

    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{dropMISSING});
    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{createMISSING});

    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{dropCONF});
    $DB->do($RequeteSQL{$GBL_STR_DB_Type}{createCONF});

    $DB->commit or die DBI->errstr;
}

# ************************************************* #
# Commands line option !! (-h == help, -f == robotfile)
# ************************************************* #

my $FILENAME;
if(scalar @ARGV > 0) {
    if($ARGV[0] eq "--f" and exists $ARGV[1]) {
        $RobotTXT = 1;
        $FILENAME = $ARGV[1];
        if(open(my $robotlist, '<:encoding(UTF-8)',$FILENAME)) {
            my $row;
            while($row = <$robotlist>) {
                $row =~ s/;//g;
                $row =~ s/,//g;
                $row =~ s/^\s+|\s+$//g;
                my $new_row = lc $row;
                $RobotsHash_TXT{"$new_row"} = 0;
            }
        }
        else {
            warn "Could not open robots file $FILENAME";
            exit(1);
        }
    }
    else {
        warn "This script argument doesn't exist! Please check help.html.";
        exit(1);
    }
}
else {
    $NMS_Probe->log("No script argument!",2);
    $NMS_Probe->localLog("No script argument!",2);
}
# ************************************************* #
# Get HUBS
# ************************************************* #
sub doWork() {
    my $NMS_HUB_RES;
    my ($FINAL_RC_HUB,$RC) = NIME_ERROR;
    for(my $i = 1;$i <= 3;$i++) {
        ($RC,$NMS_HUB_RES) = Libs::Tools::Request("$GBL_STR_RemoteHUB","gethubs");
        if($RC == NIME_OK) {
            $FINAL_RC_HUB = NIME_OK;
            last;
        }
        else {
            $NMS_Probe->log(YELLOW."$GBL_STR_RemoteHUB".RESET." not responding (timed out). [try $i]",1);
            $NMS_Probe->localLog("$GBL_STR_RemoteHUB not responding (timed out). [try $i]",1);
        }
    }

    if($FINAL_RC_HUB == NIME_OK) {

        if(scalar keys %GBL_Hash_Hubs > 0 or $hubs_restrict == 0) {
            my $HUBS_PDS = Nimbus::PDS->new($NMS_HUB_RES);

            # ************************************************* #
            # Récupérer les hubs !
            # ************************************************* #
            my @HubsList = ();
            my $HUBID_Count = 0;
            for( my $count = 0; my $HUBNFO = $HUBS_PDS->getTable("hublist",PDS_PDS,$count); $count++) {
                $HUBID_Count++;
                my $HUB = new Nimprobe::hub($HUBID_Count,$HUBNFO);
                if($hubs_restrict) {
                    if(exists $GBL_Hash_Hubs{$HUB->{name}}) {
                        if(not $GBL_Hash_Hubs{$HUB->{name}}) {
                            $NMS_Probe->log(GREEN."$HUB->{name}".RESET.YELLOW." EXCLUDED from checkconfig pool.",2);
                            $NMS_Probe->localLog("$HUB->{name} EXCLUDED from checkconfig pool.",2);
                            $HUBID_Count--;
                            next;
                        }
                        else {
                            $NMS_Probe->log(GREEN."$HUB->{name} INCLUDED in the checkconfig pool.",2);
                            $NMS_Probe->localLog("$HUB->{name} INCLUDED in the checkconfig pool.",2);
                        }
                    }
                    else {
                        $NMS_Probe->log(GREEN."$HUB->{name}".RESET.YELLOW." EXCLUDED from checkconfig pool.",2);
                        $NMS_Probe->localLog("$HUB->{name} EXCLUDED from checkconfig pool.",2);
                        $HUBID_Count--;
                        next;
                    }
                }
                # if(not $HUB->{source}) {}
                $HUB->insert($DB);
                push(@HubsList,$HUB);
                Libs::Tools::createDir("Output/$GBL_Time_ExecutionTimeStart/$HUB->{name}");
            }
            $DB->commit;
            $NMS_Probe->log(GREEN."\n--------- Hubs processing done ---------\n",3);
            $NMS_Probe->localLog("Hubs processing done",3);

            if(scalar @HubsList == 0) {
                $NMS_Probe->log(YELLOW "[MAJOR] No hubs find on Nimsoft!",1);
                $NMS_Probe->localLog("[MAJOR] No hubs find on Nimsoft!",1);
                return;
            }

            # ************************************************* #
            # Récupérer les robots de chaque HUB !
            # ************************************************* #
            my @RobotsList = ();
            my $ROBOT_Count = 0;
            foreach(@HubsList) {

                my $count_retry = 0;
                while($count_retry < 1) {
                    $count_retry++;
                    my $LOCAL_GetRobots_CallbackTime = time();
                    my ($RC,$RQ_Robot) = Libs::Tools::Request("/$_->{domain}/$_->{name}/$_->{robotname}/hub","getrobots");
                    my $LOCAL_GetRobots_End_CallbackTime = sprintf("$GBL_STR_Time_Format",time() - $LOCAL_GetRobots_CallbackTime);
                    $NMS_Probe->log(GREEN."HUB $_->{name} ".RESET." processing",2);
                    $NMS_Probe->localLog("HUB $_->{name} processing",2);
                    if($RC == NIME_OK) {
                        $_->robotCallback($DB,($RC) ? 0 : 1,$LOCAL_GetRobots_End_CallbackTime);
                        my $ROBOT_PDS = Nimbus::PDS->new($RQ_Robot);
                        for( my $count = 0; my $ROBOTNFO = $ROBOT_PDS->getTable("robotlist",PDS_PDS,$count); $count++) {
                            $ROBOT_Count++;
                            my $robot = new Nimprobe::robot($ROBOT_Count,$_->{id} - 1,$ROBOTNFO);

                            if(exists $Excluded_Robots{$robot->{name}}) {
                                $ROBOT_Count--;
                                $NMS_Probe->log("$robot->{name} is excluded from the pool.",2);
                                $NMS_Probe->localLog("$robot->{name} is excluded from the pool.",2);
                                next;
                            }

                            if($RobotTXT == 1) {
                                if( not exists($RobotsHash_TXT{$robot->{name}}) ) {
                                    $ROBOT_Count--;
                                    next;
                                }
                                else {
                                    $NMS_Probe->log(YELLOW."\t => $robot->{name} ".RESET."is in the list!",3);
                                    $NMS_Probe->localLog("$robot->{name} is in the list!",3);
                                }
                                $RobotsHash_TXT{$robot->{name}} = 1;
                            }
                            $robot->insert($DB);

                            if($robot->{status} =~ /^(0)$/) {
                                push(@RobotsList,$robot);
                                Libs::Tools::createDir("Output/$GBL_Time_ExecutionTimeStart/$_->{name}/$robot->{name}");
                            }
                        }
                        last;
                    }
                    else {
                        $_->robotCallback($DB,($RC) ? 0 : 1,$LOCAL_GetRobots_End_CallbackTime);
                        $NMS_Probe->log(RED."[ERR] ".RESET."Unable to get robotslist ! [try $count_retry]",1);
                        $NMS_Probe->localLog("[CRITICAL] Unable to get robotslist [try $count_retry]",1);
                    }
                    $_->robotAll($DB,sprintf("$GBL_STR_Time_Format",time() - $LOCAL_GetRobots_CallbackTime));
                    $DB->commit;
                }

            }
            $NMS_Probe->log(GREEN."\n--------- All robots processing done ---------\n",3);
            $NMS_Probe->localLog("All robots processing done",3);

            # ************************************************* #
            # Récupérer les probes ainsi que les configurations de celle-nécessaire !
            # ************************************************* #
            if($conf_commit) {
                $DB->{AutoCommit} = 1;
            }

            my $ROBOT_REF = 0;
            my @RobotsList_retry = ();
            foreach(@RobotsList) {
                $ROBOT_REF++;
                my $robotInstance = $_;
                print "\n";
                $NMS_Probe->log(MAGENTA."Started probe_list for robot ".RESET.GREEN."$_->{name}".RESET." [count $ROBOT_REF / $ROBOT_Count]",2);
                $NMS_Probe->localLog("Started probe_list for robot $_->{name} [count $ROBOT_REF / $ROBOT_Count]",2);

                $NMS_Probe->log(YELLOW."Robot version => ".RESET.GREEN."$_->{version}",2);
                $NMS_Probe->localLog("Robot version => $_->{version}",2);
                $NMS_Probe->log("----------------------------->",3);

                if($get_packages) {

                    $NMS_Probe->log(YELLOW."Get packages from robot!",2);
                    $NMS_Probe->localLog("Get packages from robot!",2);
                    my $PDS = pdsCreate();
                    my ($PKG_RC,$PKG_OBJ) = nimNamedRequest("$_->{addr}/controller","inst_list_summary",$PDS,1);
                    pdsDelete($PDS);

                    my $PKG_CODE = 0;
                    if($PKG_RC == NIME_OK) {
                        my $PACKAGE_PDS = Nimbus::PDS->new($PKG_OBJ);
                        for( my $count = 0; my $PKGNFO = $PACKAGE_PDS->getTable("pkg",PDS_PDS,$count); $count++) {
                            my $request = $DB->prepare("INSERT INTO packages_list (id,robotid,name,description,version,build,date,install_date) VALUES(NULL,?,?,?,?,?,?,?)");
                            $request->execute(
                                $_->{id},
                                $PKGNFO->get("name"),
                                $PKGNFO->get("description"),
                                $PKGNFO->get("version"),
                                $PKGNFO->get("build"),
                                $PKGNFO->get("date"),
                                $PKGNFO->get("install_date")
                            );
                            $request->finish;
                        }
                        $PKG_CODE = 1;
                    }
                    my $rc_robots_pkg = $DB->prepare("UPDATE robots_list SET packages_success=? WHERE id=?");
                    $rc_robots_pkg->execute($PKG_CODE,$_->{id});
                    $rc_robots_pkg->finish;
                }

                my $LOCAL_GetProbes_CallbackTime = time();
                my ($RC,$RQ_Probe) = Libs::Tools::Request("$_->{addr}/controller","probe_list");
                my $LOCAL_GetProbes_End_CallbackTime = sprintf("$GBL_STR_Time_Format",time() - $LOCAL_GetProbes_CallbackTime);
                if($RC == NIME_OK) {
                    $_->probeCallback($DB,1,$LOCAL_GetProbes_End_CallbackTime);
                    my $Probe_PDS = Nimbus::PDS->new($RQ_Probe);
                    my $ProbeNFO = $Probe_PDS->asHash();

                    # ************************************************* #
                    # Pour toutes les probes qu'on monitore !
                    # ************************************************* #
                    my $FailedsProbes = "";
                    foreach(@MonitoredProbes) {

                        # Exclude nt probe on linux
                        if($robotInstance->{os_minor} eq "Linux") {
                            if($_ eq "ntservices" || $_ eq "ntevl" || $_ eq "ntperf") {
                                next;
                            }
                        }

                        # Si la probe existe !
                        if($ProbeNFO->{$_}) {


                            my $probeEnv_Name = $_;

                            my $probe;
                            $probe = new Nimprobe::probe($robotInstance->{id},$ProbeNFO,$probeEnv_Name);
                            $probe->insert($DB);

                            # ************************************************* #
                            # Récupération et parsing des configurations de sonde Nimsoft !
                            # ************************************************* #
                            my $probeGroupe = lc $probe->{group};
                            my $tempGroup = "probes/$probeGroupe/$_/";
                            my $configName  = $probe->{config};
                            my $logName = "$probe->{name}.log";

                            if($probe->{name} eq "hub") {
                                $tempGroup = "hub";
                                $configName = "hub.cfg";
                                $logName = "hub.log";
                            }
                            if($probe->{name} eq "controller") {
                                $tempGroup = "robot";
                                $configName = "controller.cfg";
                                $logName = "controller.log"
                            }
                            if($probe->{name} eq "nas") {
                                $tempGroup = "probes/service/$probe->{name}/";
                            }

                            my $IHUB = $HubsList[$robotInstance->{hubid}];
                            if($GetRobotConfiguration) {
                                my $PDS_args = pdsCreate();

                                pdsPut_PCH ($PDS_args,"directory","$tempGroup");
                                pdsPut_PCH ($PDS_args,"file","$configName");
                                pdsPut_INT ($PDS_args,"buffer_size",10000000);

                                my $LOCAL_GetConf_CallbackTime = time();
                                my $RC_CONF = NIME_ERROR;
                                my $RC_W;
                                my $ProbePDS_CFG;
                                for(my $i = 1;$i <= 3;$i++) {
                                    ($RC_W, $ProbePDS_CFG) = nimNamedRequest("$robotInstance->{addr}/controller", "text_file_get", $PDS_args,3);
                                    if($RC_W == NIME_OK) {
                                        $RC_CONF = NIME_OK;
                                        last;
                                    }
                                }
                                pdsDelete($PDS_args);
                                my $LOCAL_GetConf_End_CallbackTime = sprintf("$GBL_STR_Time_Format",time() - $LOCAL_GetConf_CallbackTime);

                                if($RC_CONF == NIME_OK) {
                                    $NMS_Probe->log(GREEN."[SUCCESS] ".RESET."download configuration of ".RESET.YELLOW."$_",3);
                                    $NMS_Probe->localLog("[SUCCESS] download configuration of $_",3);
                                    if($probe->callbackCONF($DB,1,$LOCAL_GetConf_End_CallbackTime)) {
                                    }
                                    my $completePath = "Output/$GBL_Time_ExecutionTimeStart/$IHUB->{name}/$robotInstance->{name}/$probe->{config}";
                                    if($probe->scanCONF($ProbePDS_CFG,$completePath)) {
                                        $probe->parseCONF($DB);
                                        $NMS_Probe->log(GREEN."[SUCCESS] ".RESET."Parse ".YELLOW."$_".RESET." configuration.",3);
                                        $NMS_Probe->localLog("[SUCCESS] Parse $_ configuration.",3);
                                    }
                                    else {
                                        $NMS_Probe->log(RED."[ERR] ".RESET." Parse $_ configuration.",1);
                                        $NMS_Probe->localLog("[ERR] Parse $_ configuration.",1);
                                    }
                                }
                                else {
                                    $probe->callbackCONF($DB,0,$LOCAL_GetConf_End_CallbackTime);
                                    $NMS_Probe->log(RED."[ERR] ".RESET."to get conf of $_");
                                }

                            }

                            if($get_probes_log) {
                                my $log_pds = pdsCreate();
                                pdsPut_PCH ($log_pds,"directory","$tempGroup");
                                pdsPut_PCH ($log_pds,"file","$logName");
                                pdsPut_INT ($log_pds,"buffer_size",10000000);

                                my ($RC_LOG, $LOGPDS) = nimNamedRequest("$robotInstance->{addr}/controller", "text_file_get", $log_pds,3);
                                pdsDelete($log_pds);

                                if($RC_LOG == NIME_OK) {
                                    my $CFG_Handler;

                                    my $completePath = "Output/$GBL_Time_ExecutionTimeStart/$IHUB->{name}/$robotInstance->{name}/$logName";
                                    unless(open($CFG_Handler,">>","$completePath")) {
                                        warn "\nUnable to create log file\n";
                                        return 0;
                                    }
                                    my @ARR_CFG_Config = Nimbus::PDS->new($LOGPDS)->asHash();
                                    print $CFG_Handler $ARR_CFG_Config[0]{'file_content'};
                                    close $CFG_Handler;
                                    $NMS_Probe->log(GREEN."[SUCCESS]".RESET." Download log of => ".RESET.YELLOW."$logName",3);
                                    $NMS_Probe->localLog("[SUCCESS] Download log of => $logName",3);
                                }
                                else {
                                    $NMS_Probe->log(RED."[ERR]".RESET." Download log of => ".RESET.YELLOW."$logName",3);
                                    $NMS_Probe->log("[ERR] Download log of => $logName",3);
                                }
                            }
                            if($get_probes_log || $GetRobotConfiguration) {
                                $NMS_Probe->log("----------------------------->",3);
                            }

                        }
                        else {
                            $FailedsProbes.= "$_,";
                            my $missing_probes;
                            $missing_probes = $DB->prepare("INSERT INTO missing_probes(robotid,name) VALUES (?,?)");
                            $missing_probes->execute($robotInstance->{id},$_);
                            $missing_probes->finish;
                        }
                    }
                    if(length($FailedsProbes) > 0) {
                        $NMS_Probe->log(YELLOW."[INFO] ".RESET."Failed probelist => ".YELLOW."$FailedsProbes",2);
                        $NMS_Probe->localLog("Failed probelist => $FailedsProbes",2);
                    }
                }
                else {
                    if(not $robot_secondcheck) {
                        $_->probeCallback($DB,0,$LOCAL_GetProbes_End_CallbackTime);
                    }
                    $NMS_Probe->log(RED."[ERR] ".RESET."Impossible d'avoir la liste des sondes pour le robot ".YELLOW."$_->{name}",1);
                    $NMS_Probe->localLog("Impossible d'avoir la liste des sondes pour le robot $_->{name}",1);
                    $NMS_Probe->log(RED."[ERR] ".RESET."Status du robot => ".YELLOW."$_->{status}",2);
                    $NMS_Probe->localLog("Status du robot => $_->{status}",2);
                    $NMS_Probe->log("----------------------------->",3);
                    if($_->{status} == 0 && $_->{ip} ne "127.0.0.1") {
                        my $i = 2;
                        while($i--) {
                            sleep(1);
                        }
                        push(@RobotsList_retry,$robotInstance);
                    }
                    $GBL_INT_FailCount++;
                }
                $NMS_Probe->log(MAGENTA."Finish probe_list for robot ".RESET.GREEN."$_->{name}",3);
                $NMS_Probe->localLog( "Finish probe_list for robot $_->{name}",3);

            }

            foreach(@RobotsList_retry) {
                my $robotInstance = $_;
                print "\n";
                $NMS_Probe->log(MAGENTA."Started probe_list for robot ".RESET.GREEN."$_->{name}".RESET."",2);
                $NMS_Probe->localLog("Started probe_list for robot $_->{name}",2);

                $NMS_Probe->log(YELLOW."Robot version => ".RESET.GREEN."$_->{version}",2);
                $NMS_Probe->localLog("Robot version => $_->{version}",2);
                $NMS_Probe->log("----------------------------->",3);
                my $LOCAL_GetProbes_CallbackTime = time();
                my ($RC,$RQ_Probe) = Libs::Tools::Request("$_->{addr}/controller","probe_list");
                my $LOCAL_GetProbes_End_CallbackTime = sprintf("$GBL_STR_Time_Format",time() - $LOCAL_GetProbes_CallbackTime);
                if($RC == NIME_OK) {
                    $GBL_INT_FailCount--;
                    my $Probe_PDS = Nimbus::PDS->new($RQ_Probe);
                    my $ProbeNFO = $Probe_PDS->asHash();

                    # ************************************************* #
                    # Pour toutes les probes qu'on monitore !
                    # ************************************************* #
                    my $FailedsProbes = "";
                    foreach(@MonitoredProbes) {
                        # Si la probe existe !
                        if($ProbeNFO->{$_}) {
                            my $probeEnv_Name = $_;

                            my $probe;
                            $probe = new Nimprobe::probe($robotInstance->{id},$ProbeNFO,$probeEnv_Name);
                            $probe->insert($DB);

                            # ************************************************* #
                            # Récupération et parsing des configurations de sonde Nimsoft !
                            # ************************************************* #
                            my $probeGroupe = lc $probe->{group};
                            my $tempGroup = "probes/$probeGroupe/$_/";
                            my $configName  = $probe->{config};
                            my $logName = "$probe->{name}.log";

                            if($probe->{name} eq "hub") {
                                $tempGroup = "hub";
                                $configName = "hub.cfg";
                                $logName = "hub.log";
                            }
                            if($probe->{name} eq "controller") {
                                $tempGroup = "robot";
                                $configName = "controller.cfg";
                                $logName = "controller.log"
                            }
                            if($probe->{name} eq "nas") {
                                $tempGroup = "probes/service/$probe->{name}/";
                            }

                            my $IHUB = $HubsList[$robotInstance->{hubid}];
                            if($GetRobotConfiguration) {
                                my $PDS_args = pdsCreate();

                                pdsPut_PCH ($PDS_args,"directory","$tempGroup");
                                pdsPut_PCH ($PDS_args,"file","$configName");
                                pdsPut_INT ($PDS_args,"buffer_size",10000000);

                                my $LOCAL_GetConf_CallbackTime = time();
                                my $RC_CONF = NIME_ERROR;
                                my $RC_W;
                                my $ProbePDS_CFG;
                                for(my $i = 1;$i <= 3;$i++) {
                                    ($RC_W, $ProbePDS_CFG) = nimNamedRequest("$robotInstance->{addr}/controller", "text_file_get", $PDS_args,3);
                                    if($RC_W == NIME_OK) {
                                        $RC_CONF = NIME_OK;
                                        last;
                                    }
                                }
                                pdsDelete($PDS_args);
                                my $LOCAL_GetConf_End_CallbackTime = sprintf("$GBL_STR_Time_Format",time() - $LOCAL_GetConf_CallbackTime);

                                if($RC_CONF == NIME_OK) {
                                    $NMS_Probe->log(GREEN."[SUCCESS] ".RESET."download configuration of ".RESET.YELLOW."$_",3);
                                    $NMS_Probe->localLog("[SUCCESS] download configuration of $_",3);
                                    if($probe->callbackCONF($DB,1,$LOCAL_GetConf_End_CallbackTime)) {
                                    }
                                    my $completePath = "Output/$GBL_Time_ExecutionTimeStart/$IHUB->{name}/$robotInstance->{name}/$probe->{config}";
                                    if($probe->scanCONF($ProbePDS_CFG,$completePath)) {
                                        $probe->parseCONF($DB);
                                        $NMS_Probe->log(GREEN."[SUCCESS] ".RESET."Parse ".YELLOW."$_".RESET." configuration.",3);
                                        $NMS_Probe->localLog("[SUCCESS] Parse $_ configuration.",3);
                                    }
                                    else {
                                        $NMS_Probe->log(RED."[ERR] ".RESET." Parse $_ configuration.",1);
                                        $NMS_Probe->localLog("[ERR] Parse $_ configuration.",1);
                                    }
                                }
                                else {
                                    $probe->callbackCONF($DB,0,$LOCAL_GetConf_End_CallbackTime);
                                    $NMS_Probe->log(RED."[ERR] ".RESET."to get conf of $_");
                                }

                            }

                            if($get_probes_log) {
                                my $log_pds = pdsCreate();
                                pdsPut_PCH ($log_pds,"directory","$tempGroup");
                                pdsPut_PCH ($log_pds,"file","$logName");
                                pdsPut_INT ($log_pds,"buffer_size",10000000);

                                my ($RC_LOG, $LOGPDS) = nimNamedRequest("$robotInstance->{addr}/controller", "text_file_get", $log_pds,3);
                                pdsDelete($log_pds);

                                if($RC_LOG == NIME_OK) {
                                    my $CFG_Handler;

                                    my $completePath = "Output/$GBL_Time_ExecutionTimeStart/$IHUB->{name}/$robotInstance->{name}/$logName";
                                    unless(open($CFG_Handler,">>","$completePath")) {
                                        warn "\nUnable to create log file\n";
                                        return 0;
                                    }
                                    my @ARR_CFG_Config = Nimbus::PDS->new($LOGPDS)->asHash();
                                    print $CFG_Handler $ARR_CFG_Config[0]{'file_content'};
                                    close $CFG_Handler;
                                    $NMS_Probe->log(GREEN."[SUCCESS]".RESET." Download log of => ".RESET.YELLOW."$logName",3);
                                    $NMS_Probe->localLog("[SUCCESS] Download log of => $logName",3);
                                }
                                else {
                                    $NMS_Probe->log(RED."[ERR]".RESET." Download log of => ".RESET.YELLOW."$logName",3);
                                    $NMS_Probe->log("[ERR] Download log of => $logName",3);
                                }
                            }

                            $NMS_Probe->log("----------------------------->",3);

                        }
                        else {
                            $FailedsProbes.= "$_,";
                        }
                    }

                    if(length($FailedsProbes) > 0) {
                        $NMS_Probe->log(YELLOW."[INFO] ".RESET."Failed probelist => ".YELLOW."$FailedsProbes",2);
                        $NMS_Probe->localLog("Failed probelist => $FailedsProbes",2);
                    }
                }
                else {
                    $NMS_Probe->log(RED."[ERR] ".RESET."Impossible d'avoir la liste des sondes pour le robot ".YELLOW."$_->{name}",1);
                    $NMS_Probe->localLog("Impossible d'avoir la liste des sondes pour le robot $_->{name}",1);
                    $NMS_Probe->log(RED."[ERR] ".RESET."Status du robot => ".YELLOW."$_->{status}",2);
                    $NMS_Probe->localLog("Status du robot => $_->{status}",2);
                    $NMS_Probe->log("----------------------------->",3);
                }
                $NMS_Probe->log(MAGENTA."Finish probe_list for robot ".RESET.GREEN."$_->{name}",3);
                $NMS_Probe->localLog( "Finish probe_list for robot $_->{name}",3);

            }

            if(not $conf_commit) {
                $DB->commit;
            }
            print "\n";
        }
        else {
            $NMS_Probe->log(YELLOW."Please enter a list of hubs in the configuration file !",1);
            $NMS_Probe->localLog("Please enter a list of hubs in the configuration file !",1);
        }

    }
    else {
        $NMS_Probe->log(RED."Unable to get the list of HUBS from => '$GBL_STR_RemoteHUB' ",1);
        $NMS_Probe->localLog("Unable to get the list of HUBS from => '$GBL_STR_RemoteHUB' ",1);
    }
}
doWork();

$NMS_Probe->log(GREEN."Count of robot that fail get_probes callback =>".RESET.YELLOW." $GBL_INT_FailCount",1);
$NMS_Probe->localLog("Count of robot that fail get_probes callback => $GBL_INT_FailCount",1);

# ************************************************* #
# Reject file for robotslist with -F args
# ************************************************* #
if($RobotTXT == 1) {
    $NMS_Probe->log("Generate reject file !",3);
    $NMS_Probe->localLog("Generate reject file !",3);
    my $file_handler;
    unless(open($file_handler,">", $ARGV[2] || "Output/$GBL_Time_ExecutionTimeStart/$GBL_Time_ExecutionTimeStart-reject.txt")) {
        warn "Unabled to open rejected_files \n";
        return;
    }
    foreach my $key ( keys %RobotsHash_TXT ) {
        if($RobotsHash_TXT{$key} == 0) {
            print $file_handler "$key\n";
        }
    }
    close $file_handler;
    copy("$FILENAME","Output/$GBL_Time_ExecutionTimeStart/$FILENAME") or warn "Log copy failed! $!";
}

# Create SQLite view
if($GBL_STR_DB_Type eq "SQLite") {
    $NMS_Probe->log("Create SQLite view!",3);
    $NMS_Probe->localLog("Create SQLite view!",3);
    $DB->{AutoCommit} = 0;
    my $v1 = $DB->prepare("CREATE VIEW IF NOT EXISTS 'nimsoft_doublon' AS SELECT name, count(name) as count FROM robots_list GROUP BY name ORDER BY count DESC");
    $v1->execute();
    $v1->finish;
    my $v2 = $DB->prepare("CREATE VIEW IF NOT EXISTS 'nimsoft_conf' AS SELECT robot.name, config.probe, config.profile FROM probes_config config JOIN probes_list probe ON probe.id = config.probeid JOIN robots_list robot ON robot.id = probe.robotid");
    $v2->execute();
    $v2->finish;
    my $v3 = $DB->prepare("CREATE VIEW IF NOT EXISTS 'nimsoft_probes_list' AS SELECT '/' || hubs.domain || '/' || hubs.name || '/' || robots.name as ADDR, probes.name, probes.versions, probes.process_state FROM probes_list probes JOIN robots_list robots ON robots.id = probes.robotid JOIN hubs_list hubs ON hubs.id = robots.hubid");
    $v3->execute();
    $v3->finish;
    my $v4 = $DB->prepare("CREATE VIEW IF NOT EXISTS 'nimsoft_missingprobes' AS SELECT robot.name AS robotname,missing.name AS probeName FROM missing_probes missing JOIN robots_list robot ON robot.id = missing.robotid");
    $v4->execute();
    $v4->finish;
    my $v5 = $DB->prepare("CREATE VIEW IF NOT EXISTS 'nimsoft_robotsdown' AS SELECT * FROM robots_list WHERE status='2'");
    $v5->execute();
    $v5->finish;
    my $v6 = $DB->prepare("CREATE VIEW IF NOT EXISTS
    	'nimsoft_diffversion_count'
    AS
    SELECT
    	RL.name as RobotName,RL.status,RL.os_minor,P.name,P.versions,P.build
    FROM
    	probes_list P
    INNER JOIN
    	robots_list RL ON RL.id = P.robotid
    WHERE
    	(P.name = 'cdm' AND ( P.versions != '5.40HF3MET06' OR P.build != 4 ) ) OR
    	(P.name = 'ntevl' AND (P.versions != '4.22-HF1' OR P.build != 1) ) OR
    	(P.name = 'logmon' AND (P.versions != '3.55' OR P.build != 5 ) ) OR
    	(P.name = 'dirscan' AND (P.versions != '3.14' OR P.build != 18 ) ) OR
    	(P.name = 'ntservices' AND (P.versions != '3.24HF' OR P.build != 2) ) OR
    	(P.name = 'ntperf' AND (P.versions != '1.89' OR P.build != 24 ) ) OR
    	(P.name = 'processes' AND ( P.versions != '4.31-HF' OR P.build != 271 ) )");
    $v6->execute();
    $v6->finish;
    $DB->commit;
}

$DB->disconnect;

# Move checkconfig.db if dataType == SQLite !
if($GBL_STR_DB_Type eq "SQLite"){
    $NMS_Probe->log(YELLOW."Copy SQLite database to the local execution directory!",3);
    $NMS_Probe->localLog("Copy SQLite database to the local execution directory!",3);
    copy("$GBL_STR_DB_File.db","Output/$GBL_Time_ExecutionTimeStart/$GBL_STR_DB_File.db") or warn "SQLite database copy failed: $!";
}

copy("checkconfig.log","Output/$GBL_Time_ExecutionTimeStart/checkconfig.log") or warn "Log copy failed! $!";

# ************************************************* #
# Fin du script
# ************************************************* #
$NMS_Probe->close();

my $GBL_Time_ScriptExecutionTime_End = time();
my $FINAL_TIME = sprintf("$GBL_STR_Time_Format", $GBL_Time_ScriptExecutionTime_End - $GBL_Time_ScriptExecutionTime);

print MAGENTA."\nFinal execution time = ".RESET.YELLOW."$FINAL_TIME second(s) !\n".RESET;

1;
__END__
