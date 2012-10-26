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


## STORE / RETRIEVE formats (raw, json, yaml/yml)
ok_plugin(0, "RETR OK - got formats", undef, "RETRIEVE as => <format> works", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => "retr";
	START;

	my ($raw, $out);

	$raw = <<EOF;
key1: value1
list:
  - a
  - b
  - c
EOF

	STORE "formatted", $raw;
	$out = RETRIEVE "formatted", as => "yaml";
	ref($out) or CRITICAL "YAML not a REF";
	$out->{key1}    eq "value1" or CRITICAL "YAML{key1} was wrong ($out->{key1})";
	$out->{list}[0] eq "a"      or CRITICAL "YAML{list}[0] was wrong ($out->{list}[0])";
	$out->{list}[1] eq "b"      or CRITICAL "YAML{list}[1] was wrong ($out->{list}[1])";
	$out->{list}[2] eq "c"      or CRITICAL "YAML{list}[2] was wrong ($out->{list}[2])";

	STORE "formatted", $out, as => "yAmL";
	$out = RETRIEVE "formatted", as => "YML";
	ref($out) or CRITICAL "YAML not a REF (as => yml)";
	$out->{key1}    eq "value1" or CRITICAL "YAML{key1} was wrong ($out->{key1}) (as => yml)";
	$out->{list}[0] eq "a"      or CRITICAL "YAML{list}[0] was wrong ($out->{list}[0]) (as => yml)";
	$out->{list}[1] eq "b"      or CRITICAL "YAML{list}[1] was wrong ($out->{list}[1]) (as => yml)";
	$out->{list}[2] eq "c"      or CRITICAL "YAML{list}[2] was wrong ($out->{list}[2]) (as => yml)";

	$raw = '{"key1":"value1","list":["a","b","c"]}';
	STORE "formatted", $raw;
	$out = RETRIEVE "formatted", as => "json";
	ref($out) or CRITICAL "JSON not a REF";
	$out->{key1}    eq "value1" or CRITICAL "JSON{key1} was wrong ($out->{key1})";
	$out->{list}[0] eq "a"      or CRITICAL "JSON{list}[0] was wrong ($out->{list}[0])";
	$out->{list}[1] eq "b"      or CRITICAL "JSON{list}[1] was wrong ($out->{list}[1])";
	$out->{list}[2] eq "c"      or CRITICAL "JSON{list}[2] was wrong ($out->{list}[2])";

	STORE "formatted", $out, as => "JsOn";
	$out = RETRIEVE "formatted", as => "rAW";
	!ref($out) or CRITICAL "RAW is a REF";
	$raw eq $out or CRITICAL "RAW read did not equal RAW write qr/$out/ != /$raw/";

	$raw = "this is raw";
	STORE "formatted", $raw, as => "RAW";
	$out = RETRIEVE "formatted";
	!ref($out) or CRITICAL "RAW is a REF";
	$raw eq $out or CRITICAL "RAW read did not equal RAW write qr/$out/ != /$raw/";

	OK "got formats";
});

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

done_testing;
