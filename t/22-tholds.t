#!perl

use Test::More;
require "t/common.pl";

###################################################################

ok_plugin(0, "THOLD OK - value is 4", "value=4;;", "Thresholds 4<5 && 4<8", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 4;
	CHECK_VALUE $val, "value is $val",
	           warning => 6, critical => 8;
	TRACK_VALUE "value", $val;
	DONE;
});

ok_plugin(0, "THOLD OK - skipped check", undef, "skip_OK test", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 4;
	CHECK_VALUE $val, "value is $val",
	           skip_OK => 1,
	           warning => 6, critical => 8;
	OK "skipped check";
	DONE;
});

ok_plugin(1, "THOLD WARNING - value is 7", "value=7;6;8", "Thresholds 7>6 && 7<8", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 7;
	CHECK_VALUE $val, "value is $val",
	            warning => 6, critical => 8;
	TRACK_VALUE "value", $val,
	            warning => 6, critical => 8;
	DONE;
});

ok_plugin(2, "THOLD CRITICAL - value is 9", "value=9;6;8;0;99", "Thresholds 9>6 && 9>8", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 9;
	CHECK_VALUE $val, "value is $val",
	            warning => 6, critical => 8;
	TRACK_VALUE "value", $val,
	            warning => 6, critical => 8,
	            min => 0, max => 99;
	DONE;
});

ok_plugin(0, "THOLD OK - value is 4", "value=4;;", "Thresholds 5<6; no crit", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 4;
	CHECK_VALUE $val, "value is $val",
	            skip_OK => 0,
	            warning => 6;
	TRACK_VALUE "value", $val;
	DONE;
});

ok_plugin(1, "THOLD WARNING - value is 9", "value=9;;", "Thresholds 9>6; no crit", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 9;
	CHECK_VALUE $val, "value is $val",
	             warning => 6;
	TRACK_VALUE "value", $val;
	DONE;
});

ok_plugin(0, "THOLD OK - value is 7", "value=7;;", "Thresholds no warn; 7<8", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 7;
	CHECK_VALUE $val, "value is $val",
	            critical => 8;
	TRACK_VALUE "value", $val;
	DONE;
});

# this test makes sure we always understand the
# Nagios Threshold Format, in case we ever make
# good on threats to ditch Nagios::Plugin
ok_plugin(1, "THOLD WARNING - value is 42", undef, "Nagios Threshold Format", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "THOLD";
	START;
	my $val = 42;
	CHECK_VALUE $val, "value is $val",
	            warning  => '@40:45',
	            critical => '@45:';
	DONE;
});

ok_plugin(0, "THOLD OK", undef, "ANALYZE_THOLD works properly", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "THOLD";
	START;
	my $val = 42;
	# Verify that 1) ANALYZE_THOLD returns indicating a match, and 2) no extra messages were generated
	CRITICAL("ANALYZE_THOLD did not determine a match when it should have.")
		unless ANALYZE_THOLD($val, '@40:45') == 1;
	# Verify that ANALYZE_THOLD correctly doesn't find a match.
	CRITICAL("ANALYZE_THOLD found a match when it should not have.")
		unless ANALYZE_THOLD($val, "60") == 0;
	OK;
});

done_testing;
