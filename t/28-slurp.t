#!perl

use Test::More;
use Test::Deep::NoTest;
do "t/common.pl";

###################################################################
# SLURP

ok_plugin(0, "SLURP OK - slurped as scalar", undef, "scalar SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'retrieve normal';

	my $scalar_output = SLURP("data/slurp/normal");

	CRITICAL "output of slurp is not scalar" unless $scalar_output eq "first line\nsecond line\n"); 
	DONE;
});


ok_plugin(0, "SLURP OK - slurped as array", undef, "array SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'retrieve normal';

	my @array_test   = ("first line" ,"second line");
	my @array_output = SLURP("data/slurp/normal");

	CRITICAL "output of slurp is not array" unless eq_deeply(@array_test, @array_output);
	DONE;
});

ok_plugin(0, "SLURP OK - slurped null", undef, "null SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => '';

	my $scalar = SLURP(undef);

	CRITICAL "Not defined scalar" unless !defined($scalar);
	DONE;
});

done testing;
