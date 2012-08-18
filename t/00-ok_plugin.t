#!perl

use Test::More;
do "t/common.pl";

###################################################################
# ok_plugin tests
sub test_ok_plugin
{
	my ($code) = @_;
	ok_plugin($code, "exit $code", undef, "ok_plugin exits properly", sub {
		for (my $i = 1; $i <= $code + 1; $i++) {
			print "exit $code\n";
		}
		exit $code;
	});
}

for (my $i = 0; $i < 20; $i++) {
	test_ok_plugin($i);
}

done_testing;
