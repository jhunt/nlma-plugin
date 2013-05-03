#!perl

use Test::More;
use Test::Deep;
require "t/common.pl";

###################################################################

my $plugin = Synacor::SynaMon::Plugin::Base->new;
isa_ok($plugin, 'Synacor::SynaMon::Plugin::Base');
is($plugin->state_file_path("test.out"), "/var/tmp/mon_test.out", "Default state file path generation");

is($plugin->state_file_path("test.out", in => "/tmp/other"),
   "/tmp/other/mon_test.out", "Override location with 'in' option");

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

my $notice = "DEPRECATION NOTICE: RETRIEVE in list context is deprecated";
ok_plugin(0, "RETRIEVE OK - deprecation ignored", undef, "Ignore deprecation notices for RETRIEVE in list context", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retrieve";
	START;
	my @list = RETRIEVE("test.list");
	OK "deprecation ignored";
	DONE;
});
ok_plugin(3, "RETRIEVE UNKNOWN - $notice", undef, "DEPRECATION of RETRIEVE in list context", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	$ENV{MONITOR_FAIL_ON_DEPRECATION} = 1;
	PLUGIN name => "retrieve";
	START;
	my @list = RETRIEVE("test.list");
	OK "failed to fail";
	DONE;
});

$notice = "DEPRECATION NOTICE: STORE(ref) is deprecated as of v1.20; use 'as =%GT% yaml' or 'as =%GT% json'";
ok_plugin(3, "STORE UNKNOWN - $notice", undef, "STORE(ref) deprecation notice", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	$ENV{MONITOR_FAIL_ON_DEPRECATION} = 1;
	PLUGIN name => "store";
	START;
	STORE("test.list", [1,2,3]);
	OK "failed to fail";
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


## STORE / RETRIEVE formats (raw, json, yaml/yml)
{
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";

	my $plugin = Synacor::SynaMon::Plugin::Base->new;
	my ($data, $raw, $out);

	$data = { key1 => "value1",
	          list => [qw/a b c/] };

	$raw = <<EOF;
key1: value1
list:
  - a
  - b
  - c
EOF

	$plugin->store("formatted", $raw);
	$out = $plugin->retrieve("formatted", as => "yaml");
	cmp_deeply($out, $data, "Read back the same YAML we wrote out (as => yaml)");

	$plugin->store("formatted", $out, as => "yAmL");
	$out = $plugin->retrieve("formatted", as => "YML");
	cmp_deeply($out, $data, "Read back the same YAML we wrote out (as => YML)");

	$raw = '{"key1":"value1","list":["a","b","c"]}';
	$plugin->store("formatted", $raw);
	$out = $plugin->retrieve("formatted", as => "json");
	cmp_deeply($out, $data, "Read back the same JSON we wrote out (as => json)");

	$plugin->store("formatted", $out, as => "JsOn");
	$out = $plugin->retrieve("formatted", as => "rAW");
	is($raw, $out, "RAW read did not equal RAW write");

	$raw = "this is raw";
	$plugin->store("formatted", $raw, as => "RAW");
	$out = $plugin->retrieve("formatted");
	is($raw, $out, "RAW read did not equal RAW write");
};

ok_plugin(3, "RETR UNKNOWN - Unknown format for RETRIEVE: XML", undef, "RETRIEVE as unknown format UNKNOWNS", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START;

	my $raw = '{"key1":"value1","list":["a","b","c"]}'."\n";
	STORE "formatted", $raw;
	my $out = RETRIEVE "formatted", as => "XML"; # HA!
	OK "somehow we triggered the OK... RETRIEVE as => XML didnt fail...";
});

ok_plugin(3, "STORE UNKNOWN - Unknown format for STORE: SQL", undef, "STORE as unknown format UNKNOWNS", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "store";
	START;

	my $raw = [qw(a b c d e f g h)];
	STORE "formatted", $raw, as => "SQL";
	OK "somehow we triggered the OK... STORE as => XML didnt fail...";
});

ok_plugin(0, "BADFMT OK - good", undef, "RETRIEVE handles malformed JSON/YAML", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "badfmt";
	START;

	STORE "bad", "{{well, this isn't json or YAML!";
	my $out = RETRIEVE "bad", as => "json";
	!$out or CRITICAL "got non-undef value from RETRIEVE as => json... $out";

	$out = RETRIEVE "bad", as => "yml";
	!$out or CRITICAL "got non-undef value from RETRIEVE as => yaml... $out";

	OK "good";
});

ok_plugin(0, "STOREBULK OK - good", undef,
	"STORE as data_archive: on_previous_data_missing ok suppresses alarm for missing data.",
	sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		$ENV{"MONITOR_STATE_FILE_DIR"} = "t/data/tmp";
		my $STORE_FILE = "store_bulk";
		PLUGIN name => 'storebulk';
		START;

		SET(on_previous_data_missing => 'ok');

		my $obj = { val1 => 1, val2 => 2 };
		STORE($STORE_FILE, $obj, as => 'data_archive');
		unlink STATE_FILE_PATH($STORE_FILE);

		OK "good";
	});

ok_plugin(1, "STOREBULK WARNING - No previous data found.", undef,
	"STORE as data_archive: default on_previous_data_missing returns a warning message.",
	sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		$ENV{"MONITOR_STATE_FILE_DIR"} = "t/data/tmp";
		my $STORE_FILE = "store_bulk";
		PLUGIN name => 'storebulk';
		START;
		CRITICAL("Test bad, $STORE_FILE still exists") if -f STATE_FILE_PATH($STORE_FILE);

		my $obj = { val1 => 1, val2 => 2 };
		STORE($STORE_FILE, $obj, as => 'data_archive');
		unlink STATE_FILE_PATH($STORE_FILE);

		OK "good";
	});

ok_plugin(3, "STOREBULK UNKNOWN - No previous data found.", undef,
	"STORE as data_archive: on_previous_data_missing behaves properly when set to non-'ok' value",
	sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		$ENV{"MONITOR_STATE_FILE_DIR"} = "t/data/tmp";
		my $STORE_FILE = "store_bulk";
		PLUGIN name => 'storebulk';
		START;
		CRITICAL("Test bad, $STORE_FILE still exists") if -f STATE_FILE_PATH($STORE_FILE);

		SET(on_previous_data_missing => 'unknown');

		my $obj = { val1 => 1, val2 => 2 };
		STORE($STORE_FILE, $obj, as => 'data_archive');
		unlink STATE_FILE_PATH($STORE_FILE);

		OK "good";
	});

open FILE, ">t/data/tmp/mon_store_bulk";
print FILE '{"'.(time - 1200).'":{"val2":0,"val1":0}}';
close FILE;

ok_plugin(0, "STOREBULK OK - good", undef,
	"STORE as data_archive trims old data and stores current properly",
	sub {
		use strict;
		use Synacor::SynaMon::Plugin qw(:easy);
		use Test::Deep::NoTest;
		use JSON;
		$ENV{"MONITOR_STATE_FILE_DIR"} = "t/data/tmp";
		my $STORE_FILE = "store_bulk";
		PLUGIN name => 'storebulk';
		START;
		SET delete_after => 600;
		my $obj = { val1 => 1, val2 => 2 };
		my $time = time;
		STORE($STORE_FILE, $obj, as => 'data_archive');

		sleep 2;

		my $newobj = { val1 => 2, val2 => 3};
		my $newtime = time;
		STORE($STORE_FILE, $newobj, as => 'data_archive');

		my $retr_obj = RETRIEVE($STORE_FILE, as => 'json');
		my $expected = { $time => $obj, $newtime => $newobj };
		CRITICAL("Stored object doesn't match expected for second datapoint."
			. " Got '".to_json($retr_obj)."'. Expected '".to_json($expected)."'")
			unless (eq_deeply($retr_obj, $expected));

		unlink STATE_FILE_PATH($STORE_FILE);

		OK "good";
	});

ok_plugin(0, "STATE_FILE_PATH OK", undef, "No special characters in path", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "state_file_path";
	START;
	my $should_be = "_hello_world_";
	my $input = '!@#$%^hello&*()|world$$$}{[]';
	my $output = STATE_FILE_PATH($input);
	$output =~ s/t\/data\/tmp\/mon_//;
	BAIL("CRITICAL","Gummed Up, expected: $should_be (".length($should_be)." ".length($input).") got: $output (".length($output).")") unless $should_be eq $output;
	OK;
	DONE;
	});

mkdir "/tmp/mpf-test" unless -d "/tmp/mpf-test";
unlink "/tmp/mpf-test/mon_altpath" if -f "/tmp/mpf-test/mon_altpath";
ok_plugin(0, "ALT_PATH OK", undef, "Alternate paths work", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "alt_path";
	START;

	delete $ENV{MONITOR_STATE_FILE_DIR};
	UNKNOWN "mon_altpath exists in /tmp/mpf-test (sanity check)" if -f "/tmp/mpf-test/mon_altpath";
	UNKNOWN "default mon_altpath exists (sanity check)" if -f STATE_FILE_PATH("altpath");

	STORE("altpath", "test data 4242", in => "/tmp/mpf-test");
	UNKNOWN "mon_altpath incorrectly created in default path" if -f STATE_FILE_PATH("altpath");
	UNKNOWN "mon_altpath not created in overridden /tmp/mpf-test path" unless -f "/tmp/mpf-test/mon_altpath";
	OK;
});

ok_plugin(3, "ALT_PATH UNKNOWN - Tried to STORE into /etc (Framework Violation)", undef,
	"Failed attempt to STORE into an unsafe directory", sub {

	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "alt_path";
	START default => "failed by succeeding";

	delete $ENV{MONITOR_STATE_FILE_DIR};
	STORE("test", "test data 4242", in => "/etc");
});
ok_plugin(3, "ALT_PATH UNKNOWN - Tried to RETRIEVE from /etc (Framework Violation)", undef,
	"Failed attempt to STORE into an unsafe directory", sub {

	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "alt_path";
	START default => "failed by succeeding";

	delete $ENV{MONITOR_STATE_FILE_DIR};
	RETRIEVE("test", in => "/etc");
});

ok_plugin(0, "NOOP OK", undef, "Noop shouldn't store to state files", sub {
	use strict;
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "NOOP";
	START;

	CRITICAL "--noop arg unrecognized" unless NOOP;

	unlink STATE_FILE_PATH("noop-file") if -f STATE_FILE_PATH("noop-file");
	STORE("noop-file", "that's wrong...");
	my $data = RETRIEVE("noop-file");

	CRITICAL "Retrieved '$data' somehow"
		if $data;
	OK;
}, ["--noop"]);

done_testing;
