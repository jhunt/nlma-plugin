#!perl

use Test::More;
do "t/common.pl";

###################################################################
# DEBUG support

ok_plugin(0, "DEBUG OK - no debugging", undef, "debug off by default", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "no debugging";
	DEBUG "debug output found!";
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
