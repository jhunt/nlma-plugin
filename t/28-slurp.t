#!perl

use Test::More;
use Test::Deep::NoTest;
do "t/common.pl";

###################################################################
# SLURP

ok_plugin(0, "SLURP OK - slurped as scalar", undef, "Output is scalar", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'slurped as scalar';

	my $scalar_output = SLURP("data/slurp/normal");

	CRITICAL "output of slurp is not scalar" unless $scalar_output eq "first line\nsecond line\n";
	DONE;
});

ok_plugin(0, "SLURP OK - slurped as array", undef, "Output is array", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'slurped as array';

	my @array_test   = ("first line" ,"second line");
	my @array_output = SLURP("data/slurp/normal");

	CRITICAL "Output is not array" unless eq_deeply(@array_test, @array_output);
	DONE;
});

ok_plugin(0, "SLURP OK - undef input", undef, "Undef SLURP", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'undef input';

	my $output = SLURP(undef);

	CRITICAL "Output is defined when there should be none" if defined($output);
	DONE;
});

ok_plugin(0, "SLURP OK - null input", undef, "Null SLURP", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => 'null input';

	my $output = SLURP("");

	CRITICAL "Not null output when there should be none" if defined($output);
	DONE;
});

ok_plugin(0, "SLURP OK - File not found", undef, "File not found", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'SLURP';
	START default => "File not found";

	my $output = SLURP("missing-input");

	CRITICAL "Found output when there should be none" if defined $output;
	DONE;
});

ok_plugin(0, "SLURP OK - File unreadable", undef, "File unreadable", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "SLURP";
	START default => "File unreadable";

	chmod 0000, "data/slurp/unreadable";
	my $output = SLURP("data/slurp/unreadable");
	chmod 0644, "data/slurp/unreadable";

	CRITICAL "Output from unreadable input" if defined $output;
	DONE;
});

done testing;
