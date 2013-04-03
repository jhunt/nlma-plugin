#!perl

use Test::More;
do "t/common.pl";

###################################################################
# name detection

ok_plugin(0, "01-BASE.T OK - done", undef, "auto-detect plugin name", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN;
	START;
	OK("done");
	DONE;
});

ok_plugin(0, "BASE OK - done", undef, "ITM-2217 - strip CHECK_ prefix", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "CHECK_BASE";
	OK "done";
	DONE;
});

ok_plugin(0, "BASE OK - done", undef, "ITM-2217 - strip FETCH_ prefix", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "FETCH_BASE";
	OK "done";
	DONE;
});

ok_plugin(0, "BASE_CHECK_FETCH_STUFF OK - done", undef, "ITM-2217 - don't strip prefix", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "BASE_CHECK_FETCH_STUFF";
	OK "done";
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

ok_plugin(3, "UNKNOWN - Incorrect framework version 56.7+ (installed: $Synacor::SynaMon::Plugin::VERSION)", undef, "bad version check", sub {
	eval "use Synacor::SynaMon::Plugin qw(:easy 56.7);";
	PLUGIN name => "VERS";
	START;
	OK;
	DONE;
});

ok_plugin(0, "VERS OK", undef, "good version check", sub {
	eval "use Synacor::SynaMon::Plugin qw(:easy 1.0);";
	PLUGIN name => "VERS";
	START;
	OK;
	DONE;
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

ok_plugin(3, "TEST UNKNOWN - undef", undef, "Dummy STATUS undef", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS undef, "undef";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - Missing Status", undef, "Dummy STATUS missing", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "MISSING", "Missing Status";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - Missing Status - Name", undef, "Dummy STATUS missing", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "UP", "Missing Status - Name";
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

ok_plugin(3, "BAIL UNKNOWN - an unknown error occurred", undef, "Bail with no status", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "bail";
	START;
	BAIL("an unknown error occurred");
	OK "all good"; # never reached
	DONE;
});

ok_plugin(3, "BAIL UNKNOWN - bad unknown message", undef, "Bail with invalid status", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "bail";
	START;
	BAIL("fake status", "bad unknown message");
	OK "all good"; # never reached
	DONE:
});

ok_plugin(1, "BAIL WARNING - warning failure??", undef, "Bail with alternate syntax", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "bail";
	START;
	BAIL("WARNING", "warning failure??");
	OK "all good"; # never reached
	DONE;
});

###################################################################

ok_plugin(0, "EVAL OK", undef, "evaluate test", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "eval";
	START;
	EVALUATE 0,    "never triggered";
	EVALUATE "OK", "also never triggered";
	DONE;
});

ok_plugin(2, "EVAL CRITICAL - triggered", undef, "evaluate test with non-OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "eval";
	START;
	EVALUATE "CRITICAL", "triggered";
	DONE;
});

ok_plugin(3, "EVAL UNKNOWN - undef", undef, "evaluate test with undef status values", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "eval";
	START;
	EVALUATE undef, "undef";
	DONE;
});

ok_plugin(3, "EVAL UNKNOWN - Missing Status", undef, "evaluate test with missing status values", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "eval";
	START;
	EVALUATE "MISSING", "Missing Status";
	DONE;
});

ok_plugin(3, "EVAL UNKNOWN - Missing Status - name", undef, "evaluate test with missing name status values", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "eval";
	START;
	EVALUATE "UP", "Missing Status - name";
	DONE;
});

done_testing;
