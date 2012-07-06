#!perl

use Test::More;

sub ok_plugin
{
	my ($exit, $summary, $perfdata, $message, $sub) = @_;

	my ($e, $s, $p, $output);
	pipe my ($parent, $child);
	my $pid = fork;

	if ($pid) {
		close $child;

		$output = <$parent>;
		close $parent;

		wait;
		$e = $? >> 8; # FIXME: be more explicit

	} elsif ($pid == 0) {
		close $parent;
		open(STDOUT, ">&=" . fileno($child));
		$sub->();
		exit 42; # jus tin case

	} else {
		fail "$message - Couldn't fork: $!";
	}

	($s, $p) = map { s/^\s+//; s/\s$//; $_ } split /\|/, $output;

	is($s, $summary, "$message: expected summary output");
	is($p, $perf,    "$message: expected perfdata output") if $perf;
	is($e, $exit,    "$message: expect exit code $exit");
}

###################################################################
# name detection

ok_plugin(0, "PLUGIN.T OK - done", undef, "auto-detect plugin name", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN;
	START;
	OK("done");
	DONE;
});

###################################################################

ok_plugin(0, "DEFAULT OK - default message", undef, "default OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "default";
	START default => "default message";
	DONE;
});

###################################################################

ok_plugin(3, "ATEXIT UNKNOWN - Check appears to be broken; no problems triggered", undef, "fall off the end test", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "atexit";
	START;
});

###################################################################

ok_plugin(0, "TEST OK - okay", undef, "Dummy OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	OK "okay";
	DONE;
});

ok_plugin(1, "TEST WARNING - warn", undef, "Dummy WARN", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	WARNING "warn";
	DONE;
});

ok_plugin(2, "TEST CRITICAL - bad!", undef, "Dummy CRITICAL", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	CRITICAL "bad!";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - ???", undef, "Dummy UNKNOWN", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	UNKNOWN "???";
	DONE;
});

###################################################################

ok_plugin(0, "TEST OK - okay", undef, "Dummy STATUS OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "OK", "okay";
	DONE;
});

ok_plugin(1, "TEST WARNING - warn", undef, "Dummy STATUS WARN", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "WARNING", "warn";
	DONE;
});

ok_plugin(2, "TEST CRITICAL - bad!", undef, "Dummy STATUS CRITICAL", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "CRITICAL", "bad!";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - ???", undef, "Dummy STATUS UNKNOWN", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "UNKNOWN", "???";
	DONE;
});

###################################################################

ok_plugin(0, "THOLD OK - value is 4", "value=4;;;;", "Thresholds 4<5 && 4<8", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 4;
	CHECK_VALUE $val, "value is $val",
	           warning => 6, critical => 8;
	TRACK_VALUE "value", 4;
	DONE;
});

ok_plugin(1, "THOLD WARNING - value is 7", "value=4;;;;", "Thresholds 7>6 && 7<8", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 7;
	CHECK_VALUE $val, "value is $val",
	            warning => 6, critical => 8;
	TRACK_VALUE "value", 4;
	DONE;
});

ok_plugin(2, "THOLD CRITICAL - value is 9", "value=4;;;;", "Thresholds 9>6 && 9>8", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 9;
	CHECK_VALUE $val, "value is $val",
	            warning => 6, critical => 8;
	TRACK_VALUE "value", 4;
	DONE;
});

ok_plugin(0, "THOLD OK - value is 4", "value=4;;;;", "Thresholds 5<6; no crit", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 4;
	CHECK_VALUE $val, "value is $val",
	            warning => 6;
	TRACK_VALUE "value", 4;
	DONE;
});

ok_plugin(1, "THOLD WARNING - value is 9", "value=4;;;;", "Thresholds 9>6; no crit", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 9;
	CHECK_VALUE $val, "value is $val",
	             warning => 6;
	TRACK_VALUE "value", 4;
	DONE;
});

ok_plugin(0, "THOLD OK - value is 7", "value=4;;;;", "Thresholds no warn; 7<8", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 7;
	CHECK_VALUE $val, "value is $val",
	            critical => 8;
	TRACK_VALUE "value", 4;
	DONE;
});

###################################################################

ok_plugin(2, "BAIL CRITICAL - bail early", undef, "Bail early", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "bail";
	START;
	BAIL(CRITICAL "bail early");
	OK "all good"; # never reached
	DONE;
});

###################################################################

ok_plugin(0, "ALERT OK - good", undef, "alert test", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "alert";
	START;
	ALERT 0,    "never triggered";
	ALERT "OK", "also never triggered";
	OK "good";
	DONE;
});

ok_plugin(2, "ALERT CRITICAL - triggered", undef, "alert test with non-OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "alert";
	START;
	ALERT "CRITICAL", "triggered";
	DONE;
});

###################################################################

ok_plugin(0, "TIMEOUT OK - no timeout", undef, "No Timeout", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 1, "timeout triggered";
	STOP_TIMEOUT;
	OK "no timeout";
	DONE;
});

ok_plugin(2, "Timed out after 1s", undef, "Timeout / no stage", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 1;
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

ok_plugin(2, "Timed out after 1s: in first stage", undef, "Timeout / stage1", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 1, "in first stage";
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

ok_plugin(2, "Timed out after 2s: stage 2", undef, "Timeout / stage2", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 2, "stage 1";
	sleep 1;
	STAGE "stage 2";
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

###################################################################

unlink "t/data/tmp/mon_test.value" if -f "t/data/tmp/mon_test.value";

ok_plugin(0, "STORE OK - good", undef, "Store/Retrieve", sub {
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "store";
	START;
	my $val = RETRIEVE("test.value");
	WARNING "got a value... $val" if $val;

	$val = 3;
	STORE("test.value", 3);
	my $other = RETRIEVE("test.value");
	WARNING "got back wrong value... $val" if $val != 3;

	OK "good";
	DONE;
});

ok_plugin(3, "STORE UNKNOWN - Could not open 't/ENOENT/mon_test.fail' for writing", undef, "Store failure", sub {
	$ENV{MONITOR_STATE_FILE_DIR} = "t/ENOENT";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "store";
	START;
	STORE("test.fail", 42);
	DONE;
});

###################################################################

chmod 0400, "t/data/creds";
chmod 0400, "t/data/creds.corrupt";

chmod 0000, "t/data/creds.perms";
chmod 0664, "t/data/creds.insecure";

ok_plugin(0, "CREDS OK - good", undef, "Credentials OK", sub {
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	my ($user, $pass);

	($user, $pass) = CREDENTIALS("db");
	unless ($user eq "dbuser" && $pass eq "dbpass") {
		CRITICAL "db: $user/$pass";
	}

	($user, $pass) = CREDENTIALS("passonly");
	unless (!defined $user && $pass eq "secret") {
		CRITICAL "passonly: $user/$pass";
	}

	($user, $pass) = CREDENTIALS("useronly");
	unless ($user eq "monitor_rw" && !defined $pass) {
		CRITICAL "useronly: $user/$pass";
	}

	OK "good";
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Credentials key 'unknown' not found", undef, "Non-existent key", sub {
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("unknown");
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Corrupt credentials key 'corrupt'", undef, "Bad key", sub {
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("corrupt");
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Could not find credentials file", undef, "Credentials file missing", sub {
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.DNE";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Could not read credentials file", undef, "Credentials file unreadable", sub {
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.perms";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Insecure credentials file; mode is 0664 (not 0400)", undef, "Creds file insecure", sub {
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.insecure";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Corrupted credentials file", undef, "Creds file corrupted", sub {
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.corrupt";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

system("chmod 644 t/data/creds*");

###################################################################

ok_plugin(0, "DEBUG OK - good", undef, "Debugging / Dumping", sub {
	PLUGIN name => "debug";
	START;
	DEBUG("this is a debug statement");
	DUMP(qw(and this is a dumped array));
	OK "good";
	DONE;
});

done_testing;
