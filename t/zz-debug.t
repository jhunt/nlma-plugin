#!perl

use Test::More;
do "t/common.pl";

###################################################################
# DEBUG support

ok_plugin(0, "DEBUG OK - good", undef, "Debugging / Dumping", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "debug";
	START;
	DEBUG("this is a debug statement");
	DUMP(qw(and this is a dumped array));
	OK "good";
	DONE;
});

close STDERR;
ok_plugin(0, "DEBUG> test debugging", undef, "debug processing", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "done";

	open STDERR, ">&STDOUT";
	DEBUG "test debugging";

	DONE;
}, ["-D"]);

done_testing;
