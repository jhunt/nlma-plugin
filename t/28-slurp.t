#!perl

use Test::More;
do "t/common.pl";

###################################################################
# SLURP

ok_plugin(0, "SLURP OK - slurped as scalar", undef, "scalar SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'retrieve normal';

	DONE;
});

ok_plugin(0, "SLURP OK - slurped null", undef, "null SLURP", sub {

});

done testing;
