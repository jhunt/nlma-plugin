#!perl

use Test::More;
require "t/common.pl";

###################################################################
# ok_plugin tests
sub test_ok_plugin
{
	my ($code) = @_;
	ok_plugin($code, "exit $code", undef, "ok_plugin exits properly", sub {
		print "exit $code\n";
		for (my $i = 1; $i <= $code + 1; $i++) {
			print "multiline output #$i!\n";
		}
		exit $code;
	});
}

for (my $i = 0; $i < 20; $i++) {
	# Yo Dawg, I heard you like testing, so I put a test in your tests,
	# that tests your test.
	test_ok_plugin($i);
}

done_testing;
