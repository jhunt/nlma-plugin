#!perl

use Test::More;
require "t/common.pl";

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

ok_plugin(2, "Timed out after 1s: init", undef, "Timeout / start_timeout keeps stage name", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	STAGE "init";
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

ok_plugin(1, "Timed out after 1s: warning!", undef, "Timeout / warnings", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	SET on_timeout => "WARN";
	STAGE "warning!";
	START_TIMEOUT 1;
	sleep 2;
	DONE;
});

ok_plugin(3, "Timed out after 1s: unknown!", undef, "Timeout / unknowns", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	SET on_timeout => "unknowledgeableitdoesntmatterwhatgoesafterUNK...";
	STAGE "unknown!";
	START_TIMEOUT 1;
	sleep 2;
	DONE;
});

ok_plugin(2, "Timed out after 1s: re-CRIT!", undef, "Timeout / successive SET calls", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	SET on_timeout => "unknown";
	SET on_timeout => "warning";
	SET on_timeout => "CRIT!";
	STAGE "re-CRIT!";
	START_TIMEOUT 1;
	sleep 2;
	DONE;
});

###################################################################

ok_plugin(0, "TIMEOUT OK - no timeout", undef, "POSIX: No Timeout", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	SET signals => 'posix';
	START_TIMEOUT 1, "timeout triggered";
	STOP_TIMEOUT;
	OK "no timeout";
	DONE;
});

ok_plugin(2, "Timed out after 1s: running check", undef, "POSIX: Timeout", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	SET signals => 'posix';
	START_TIMEOUT 1;
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

ok_plugin(2, "Timed out after 1s: init", undef, "POSIX: Timeout / start_timeout keeps stage name", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	SET signals => 'posix';
	STAGE "init";
	START_TIMEOUT 1;
	sleep 2;
	STOP_TIMEOUT;
	DONE;
});

ok_plugin(1, "Timed out after 1s: warning!", undef, "POSIX: Timeout / warnings", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "timeout";
	START;
	SET signals => 'posix';
	SET on_timeout => "WARN";
	STAGE "warning!";
	START_TIMEOUT 1;
	sleep 2;
	DONE;
});

###################################################################

sub within
{
	my ($a, $b, $eps, $msg) = @_;

	my $delt = abs($a-$b);
	return ($delt < $eps);
}

ok_plugin(0, "TIME OK - all good", undef, "Timers / STAGE_TIME vs TOTAL_TIME", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "time";
	START;
	sleep 1;
	my ($total, $stage) = (TOTAL_TIME, STAGE_TIME);
	if (!within($total, $stage, 0.001)) {
		CRITICAL "Total $total != Stage $stage";
	}

	STAGE "second stage";
	($total, $stage) = (TOTAL_TIME, STAGE_TIME);
	if (within($total, $stage, 0.001)) {
		CRITICAL "second stage STAGE_TIME ($stage) should be much less than TOTAL_TIME ($total)";
	}

	OK "all good";
	DONE;
});

ok_plugin(0, "TIME OK - all good", undef, "Timers / start_timeout should reset STAGE_TIME", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "time";
	START;
	sleep 1;
	START_TIMEOUT 4; # no stage name = STAGE_TIME does *not* get reset
	my ($total, $stage) = (TOTAL_TIME, STAGE_TIME);
	if (!within($total, $stage, 0.001)) {
		CRITICAL "Total $total != Stage $stage";
	}

	START_TIMEOUT 4, "stage 2";
	($total, $stage) = (TOTAL_TIME, STAGE_TIME);
	if (within($total, $stage, 0.001)) {
		CRITICAL "second stage STAGE_TIME ($stage) should be much less than TOTAL_TIME ($total)";
	}

	OK "all good";
	DONE;
});

# test that we kill child processes that don't respond to usual interrupts, after timing out
ok_plugin(2,
	"Timed out after 1s: Running a command that ignores all signals like cassandra-cli",
	undef,
	"Time out kills child processes",
	sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN name => "RUN";
		START;
		START_TIMEOUT 1;
		STAGE "Running a command that ignores all signals like cassandra-cli";
		RUN "t/bin/dontdie";
		OK "Exited before a timeout occurred (that's bad for this test)";
	});

done_testing;
