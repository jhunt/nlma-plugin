#!perl

use Test::More;
require "t/common.pl";

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

ok_plugin(0, "TEST OK", undef, "Message-less OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	OK;
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

ok_plugin(3, "TEST UNKNOWN - %TILDE%", undef, "Dummy STATUS UNKNOWN escape tilda", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "UNKNOWN", "~";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - %TILDE%%AMP%%DOLLAR%%LT%%GT%%QUOT%%BTIC%", undef, "Dummy STATUS UNKNOWN escape illegal", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "UNKNOWN", "~&\$<>\"`";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - Test status", undef, "Dummy STATUS UNKNOWN remove newlines", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "UNKNOWN", "Test \n\nstatus\n\n\n";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - Test status", undef, "Dummy STATUS UNKNOWN remove carriage return", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "UNKNOWN", "Test \rstatus";
	DONE;
});

ok_plugin(3, "TEST UNKNOWN - Test status extended", undef, "Dummy STATUS UNKNOWN remove vertical whitespace", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	STATUS "UNKNOWN", "Test \x0bstatus\x0b extended";
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

ok_plugin(2, "TEST CRITICAL - %TILDE%%TILDE%%TILDE%", undef, "Critical bail properly formats messages", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "TEST";
	START;
	BAIL(CRITICAL "~~~");
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

my $X = 'x' x 9; # +1 = 10
my $size_msg = "SIZE OK - ".("$X " x 400).'(alert truncated @4k)';
ok_plugin(0, $size_msg, undef, "Truncate Messages", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "size";
	START;

	CRITICAL "length discrepancy (".length($size_msg)." >= 4096)" if length($size_msg) >= 4096;
	for (1 .. 600) { OK $X; }
	DONE;
});

$X = 'x' x 39; # +1 = 40
$size_msg = 'SIZE OK - '.("$X " x 100).'(alert truncated @4k)';
ok_plugin(0, $size_msg, undef, "Bigger Truncate Messages", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "size";
	START;

	CRITICAL "length discrepancy (".length($size_msg)." >= 4096)" if length($size_msg) >= 4096;
	for (1 .. 600) { OK $X; }
	DONE;
});

$X = 'x' x 500;
$size_msg = "SIZE OK - $X $X $X";
ok_plugin(0, $size_msg, undef, "Maximum single message size", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "size";
	START;

	CRITICAL "length discrepancy (".length($size_msg)." >= 4096)" if length($size_msg) >= 4096;
	OK 'x' x 1024;
	OK 'x' x 2024;
	OK 'x' x 8192;
	DONE;
});

$X = 'x' x 500;     # we should get 6 of these (501 * 6 = 3006b)
my $Y = 'y' x 500;  # we should get 1 of these
$size_msg = "SIZE OK - $X $X $X $X $X $X $Y (alert truncated \@4k)";
ok_plugin(0, $size_msg, undef, "Maximum single message size", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "size";
	START;

	CRITICAL "length discrepancy (".length($size_msg)." >= 4096)" if length($size_msg) >= 4096;
	OK 'first message';
	OK 'x' x (rand(1024) + 1024) for 1 .. 16; # more than six
	OK 'y' x (rand(1024) + 1024);
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

###################################################################

ok_plugin(0, "TRACK OK", "key1=42;;", "track value", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "track"; START;
	TRACK_VALUE key1 => 42;
	OK; DONE;
});

ok_plugin(0, "TRACK OK", "", "track value", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "track"; START;
	TRACK_VALUE key1 => 42;
	OK; DONE;
}, ['--noperf']);

done_testing;
