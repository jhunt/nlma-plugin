#!perl

use Test::More;
do "t/common.pl";

###################################################################
# ok_plugin_help tests
sub test_ok_plugin_help
{
	my $expect = <<EOF
exit 3
exit 3
EOF
	;
	ok_plugin_help($expect, "ok_plugin exits properly", sub {
		print "exit 3\n";
		print "exit 3\n";
		exit 3;
	}, []);
}

for (my $i = 0; $i < 20; $i++) {
	test_ok_plugin_help();
}

done_testing;
