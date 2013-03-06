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

	CRITICAL "Output is not array" unless eq_deeply(@array_test, @array_output);
	DONE;
});

ok_plugin(0, "SLURP OK - undef input", undef, "Undef SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'undef input';

	my $output = SLURP(undef);

	CRITICAL "Output is defined when it should not be" if defined($output);
	DONE;
});

ok_plugin(0, "SLURP OK - null iput", undef, "Null SLURP", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'null input';

	my $output = SLURP("");

	CRITICAL "Not null output" if defined($output);
	DONE;
});

ok_plugin(0, "SLURP OK - File not readable", undef, "File unreadable", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => "File not readable";

	my $output = SLURP("unreadable-input");

	CRITICAL "Found readable output when it should not be" if defined $output;
	DONE;
});

done testing;
