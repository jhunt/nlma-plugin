#!perl

use Test::More;
do "t/common.pl";

###################################################################

my $plugin = Synacor::SynaMon::Plugin::Base->new;
isa_ok($plugin, 'Synacor::SynaMon::Plugin::Base');
is($plugin->state_file_path("test.out"), "/var/tmp/mon_test.out", "Default state file path generation");
$ENV{MONITOR_STATE_FILE_DIR} = "/env";
$ENV{MONITOR_STATE_FILE_PREFIX} = "PRE";
is($plugin->state_file_path("test.out"), "/env/PRE_test.out", "Overrides state file path generation");

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

unlink "t/data/tmp/mon_undef" if -f "t/data/tmp/mon_undef";
ok_plugin(0, "STORE OK - no data stored", undef, "STORE(undef) is a noop", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "store";
	START;

	STORE "undef", undef;
	my $val = RETRIEVE("undef");
	!defined($val) || WARNING "retrieved value from file: $val";
	OK "no data stored";
	DONE;
});
ok(! -f "t/data/tmp/mon_undef", "STORE(undef) does not create a file");

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

unlink "t/data/tmp/mon_retr.new" if -f "t/data/tmp/mon_retr.new";
ok(! -f "t/data/tmp/mon_retr.new", "mon_retr.new should not exist");
ok_plugin(0, "RETR OK - good", undef, "RETRIEVE touches a new file", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START default => "good";

	my $val = RETRIEVE "retr.new", touch => 1;
	!defined($val) or CRITICAL "retrieved real value '$val' from retr.new (should ENOENT)";
	DONE;
});
ok(! -f "t/data/tmp/mon_retr.new", "mon_retr.new should not exist after plugin run");

system("touch -d 2012-01-01 t/data/tmp/mon_retr.new");
my @stat = stat("t/data/tmp/mon_retr.new");
cmp_ok($stat[ 9], '<', time - 86400, "mon_retr.new is at least a day old (mtime)");
ok_plugin(0, "RETR OK - touch files", undef, "RETRIEVE touches the file", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START default => "touch files";

	RETRIEVE "retr.new", touch => 1;
	DONE;
});
@stat = stat("t/data/tmp/mon_retr.new");
cmp_ok($stat[ 9], '>', time - 86400, "mon_retr.new is less than a day old (mtime)");


unlink "t/data/tmp/mon_no_touch" if -f "t/data/tmp/mon_no_touch";
ok(! -f "t/data/tmp/mon_no_touch", "mon_no_touch should not exist");
ok_plugin(0, "RETR OK - dont touch files", undef, "RETRIEVE can be told not touch files", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START default => "dont touch files";

	my $val = RETRIEVE "no_touch";
	!defined($val) or CRITICAL "retrieved real value '$val' from no_touch (should ENOENT)";
	DONE;
});
ok(! -f "t/data/tmp/mon_no_touch", "mon_no_touch should still not exist");

ok(! -e "t/ENOENT", "t/ENOENT directory should not exist");
ok_plugin(0, "RETR OK - failed without touch", undef, "RETRIEVE handles bad parent dir", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/ENOENT";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START default => "failed without touch";

	my $val = RETRIEVE "enoent";
	!defined($val) or CRITICAL "retrieved real value '$val' from enoent (should ENOENT)";
	DONE;
});
ok(! -e "t/ENOENT", "t/ENOENT direct should still not exist");

ok(! -e "t/ENOENT", "t/ENOENT directory should not exist");
ok_plugin(0, "RETR OK - failed touch", undef, "RETRIEVE handles bad parent dir", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/ENOENT";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START default => "failed touch";

	my $val = RETRIEVE "enoent", touch => 1;
	!defined($val) or CRITICAL "retrieved real value '$val' from enoent (should ENOENT)";
	DONE;
});
ok(! -e "t/ENOENT", "t/ENOENT direct should still not exist");


system("touch -d 2012-01-01 t/data/tmp/mon_state.perms");
@stat = stat("t/data/tmp/mon_state.perms");
chmod 000, "t/data/tmp/mon_state.perms";
cmp_ok($stat[ 9], '<', time - 86400, "mon_state.perms is at least a day old (mtime)");
ok_plugin(0, "RETR OK - good", undef, "RETRIEVE (touch) handles bad permissions", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START default => "good";

	my $val = RETRIEVE "state.perms", touch => 1;
	!defined($val) or CRITICAL "retrieved real value '$val' from state.perms (should EPERM)";
	DONE;
});
@stat = stat("t/data/tmp/mon_state.perms");
chmod 0400, "t/data/tmp/mon_state.perms";
# Interestingly, you can touch a file you own that is chmod'd 000.
cmp_ok($stat[ 9], '>', time - 86400, "mon_state.perms is less than a day old (mtime)");


done_testing;
