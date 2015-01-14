#!perl

use Test::More;
require "t/common.pl";

###################################################################
# basic status calls - OK/WARNING/CRITICAL/UNKNOWN

ok_plugin(0, "STAT OK - okay", undef, "OK()", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK "okay";
	DONE;
});

ok_plugin(1, "STAT WARNING - warn", undef, "WARNING()", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	WARNING "warn";
	DONE;
});

ok_plugin(2, "STAT CRITICAL - crit", undef, "CRITICAL()", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	CRITICAL "crit";
	DONE;
});

ok_plugin(3, "STAT UNKNOWN - unknown", undef, "UNKNOWN()", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	UNKNOWN "unknown";
	DONE;
});

ok_plugin(3, "STAT UNKNOWN - Check appears to be broken; no problems triggered", undef, "no statuses called", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	DONE;
});

###################################################################
# basic status calls - messages are optional

ok_plugin(0, "STAT OK", undef, "OK() without a message", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK;
	DONE;
});

ok_plugin(1, "STAT WARNING", undef, "WARNING() without a message", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	WARNING;
	DONE;
});

ok_plugin(2, "STAT CRITICAL", undef, "CRITICAL() without a message", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	CRITICAL;
	DONE;
});

ok_plugin(3, "STAT UNKNOWN", undef, "UNKNOWN() without a message", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	UNKNOWN;
	DONE;
});

###################################################################
# triage - pick the worst tracked message

ok_plugin(1, "STAT WARNING - warn", undef, "WARNING() + OK() = WARNING", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK      "okay";
	WARNING "warn";
	OK      "okay again";
	DONE;
});

ok_plugin(2, "STAT CRITICAL - crit", undef, "CRITICAL() + WARNING() + OK() = CRITICAL", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK       "okay";
	WARNING  "warn";
	CRITICAL "crit";
	DONE;
});

ok_plugin(3, "STAT UNKNOWN - unknown", undef, "UNKNOWN() trumps all", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK       "okay";
	WARNING  "warn";
	CRITICAL "crit";
	UNKNOWN  "unknown";
	OK       "but that was fine";
	WARNING  "might want to look at this one";
	DONE;
});

ok_plugin(3, "STAT UNKNOWN - first", undef, "Only the first UNKNOWN() matters", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	UNKNOWN "first";
	UNKNOWN "second";
	DONE;
});

ok_plugin(0, "STAT OK - a b c", undef, "All OK() messages are handled", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK "a";
	OK "b";
	OK "c";
});

ok_plugin(1, "STAT WARNING - a b c", undef, "All WARNING() messages are handled", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK "okays are ignored";
	WARNING "a";
	WARNING "b";
	WARNING "c";
});

ok_plugin(2, "STAT CRITICAL - a b c", undef, "All CRITICAL() messages are handled", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "STAT";
	OK "okays are ignored";
	WARNING "warnings are ignored";
	CRITICAL "a";
	CRITICAL "b";
	CRITICAL "c";
});

done_testing;
