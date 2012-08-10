#!perl

use Test::More;
do "t/common.pl";

###################################################################

ok_plugin(0, "TIMEOUT OK - no timeout", undef, "No Timeout", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 1, "timeout triggered";
	STOP_TIMEOUT;
	OK "no timeout";
	DONE;
});

ok_plugin(2, "Timed out after 1s: running check", undef, "Timeout / default stage", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 1;
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

ok_plugin(2, "Timed out after 1s: in first stage", undef, "Timeout / stage1", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 1, "in first stage";
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

ok_plugin(2, "Timed out after 2s: stage 2", undef, "Timeout / stage2", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	START_TIMEOUT 2, "stage 1";
	sleep 1;
	STAGE "stage 2";
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

done_testing;
