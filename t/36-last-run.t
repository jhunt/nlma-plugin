#!perl

use Test::More;
use Test::MockModule;
use Net::SSH::Perl;
require "t/common.pl";

ok_plugin(0, "LAST_RUN_EXITED OK", undef, "normal exit code", sub {
	use Synacor::SynaMon::Plugin qw/:easy/;
	PLUGIN name => "LAST_RUN_EXITED";
	RUN "ls t";
	CRITICAL "LAST_RUN_EXITED: " . LAST_RUN_EXITED unless LAST_RUN_EXITED == 0;
	OK;
});

ok_plugin(0, "LAST_RUN_EXIT_REASON OK", undef, "normal exit reason", sub {
	use Synacor::SynaMon::Plugin qw/:easy/;
	PLUGIN name => "LAST_RUN_EXIT_REASON";
	RUN "ls t";
	CRITICAL "LAST_RUN_EXIT_REASON: " . LAST_RUN_EXIT_REASON
		unless LAST_RUN_EXIT_REASON eq "normal";
	OK;
});

done_testing;
