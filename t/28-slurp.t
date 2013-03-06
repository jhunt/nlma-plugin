#!perl

use Test::More;
use Test::Deep::NoTest;
do "t/common.pl";

###################################################################
# SLURP

ok_plugin(0, "SLURP OK - slurped as scalar", undef, "Output is scalar", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'retrieve normal';

	my $scalar_output = SLURP("data/slurp/normal");

	CRITICAL "output of slurp is not scalar" unless $scalar_output eq "first line\nsecond line\n");
	DONE;
});


ok_plugin(0, "SLURP OK - slurped as array", undef, "Output is array", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'retrieve normal';

	my @array_test   = ("first line" ,"second line");
	my @array_output = SLURP("data/slurp/normal");

	CRITICAL "output of slurp is not array" unless eq_deeply(@array_test, @array_output);
	DONE;
});

ok_plugin(0, "SLURP OK - slurped undef", undef, "undef SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'undef input';

	my $scalar = SLURP(undef);

	CRITICAL "Defined scalar" unless !defined($scalar);
	DONE;
});

ok_plugin(0, "SLURP OK - slurped null", undef, "null SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'null input';

	my $scalar = SLURP("");

	CRITICAL "Not null scalar" unless !defined($scalar);
	DONE;
});


ok_plugin(0, "SLURP UNKNOWN - File not readable", undef, "File unreadable", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START;

	SLURP("data/slurp/unreadable");

	DONE;
});

done testing;
