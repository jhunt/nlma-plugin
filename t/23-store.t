#!perl

use Test::More;
do "t/common.pl";

###################################################################

unlink "t/data/tmp/mon_test.value" if -f "t/data/tmp/mon_test.value";

ok_plugin(0, "STORE OK - good", undef, "Store/Retrieve", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "store";
	START;
	my $val = RETRIEVE("test.value");
	WARNING "got a value... $val" if $val;

	$val = 3;
	STORE("test.value", 3);
	my $other = RETRIEVE("test.value");
	WARNING "got back wrong value... $val" if $val != 3;

	OK "good";
	DONE;
});

ok_plugin(3, "STORE UNKNOWN - Could not open 't/ENOENT/mon_test.fail' for writing", undef, "Store failure", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/ENOENT";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "store";
	START;
	STORE("test.fail", 42);
	DONE;
});

ok_plugin(0, "STORE OK - arrays work", undef, "Store and retrieve arrays", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "store";
	START;

	my @list = ("first\n", "second\n", "third\n");
	STORE("test.list", \@list);

	my $read_scalar = RETRIEVE("test.list");
	$read_scalar eq "first\nsecond\nthird\n" or CRITICAL "STORE(list) / RETRIEVE(scalar) fails: $read_scalar";

	my @read_list = RETRIEVE("test.list");
	$read_list[0] eq "first\n"  or CRITICAL "RETRIEVE(list)[0] is $read_list[0]";
	$read_list[1] eq "second\n" or CRITICAL "RETRIEVE(list)[1] is $read_list[1]";
	$read_list[2] eq "third\n"  or CRITICAL "RETRIEVE(list)[2] is $read_list[2]";

	OK "arrays work";
	DONE;
});

done_testing;
