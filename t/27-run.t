#!perl

use Test::More;
use Test::MockModule;
use Net::SSH::Perl;
require "t/common.pl";

package My::Protocol;

sub new
{
	my ($class) = @_;
	bless({}, $class);
}

package main;

ok_plugin(0, "RUN OK", undef, "simple run", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "ls t";
	OK;
	DONE;
});

ok_plugin(3, "RUN UNKNOWN - /usr/bin/notacommand: no such file", undef, "bad path run", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/usr/bin/notacommand";
	OK;
	DONE;
});

ok_plugin(3, "RUN UNKNOWN - /etc/issue: not executable", undef, "non-exec path run", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/etc/issue | test -f /etc/issue";
	OK;
	DONE;
});

ok_plugin(0, "RUN OK", undef, "exec path run", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/bin/echo 'message here'";
	OK;
	DONE;
});

ok_plugin(2, "RUN CRITICAL - Command './t/run/exit_code 2' exited with code 2.", undef, "command non-zero exit", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "./t/run/exit_code 2";
	OK "failure is OK";
	DONE;
});

ok_plugin(0, "RUN OK - failure is OK", undef, "failok", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "./t/run/exit_code 2", failok => 1;
	OK "failure is OK";
	DONE;
});

ok_plugin(0, "RUN OK - return list", undef, "list context for RUN call", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	my @lines = RUN q[/bin/sh -c 'echo "first"; echo "second"; echo "third"'];
	my $output = join("|", @lines);
	$output =~ s/\r?\n/~~NEWLINE~~/gm;

	$output eq "first|second|third" or CRITICAL "Got the wrong output: $output";
	OK "return list";
	DONE;
});

ok_plugin(3, "RUNVIA UNKNOWN - Unsupported RUN mechanism: 'My::Protocol'", undef, "run via unsupported type fails", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUNVIA";
	START;
	my $ssh = My::Protocol->new;
	RUN "ls", via => $ssh;
	OK "this should not have returned ok...";
	DONE;
});

# test running ssh command
{
	my $sshmodule = Test::MockModule->new("Net::SSH::Perl");
	$sshmodule->mock('new', sub {
			my $class = shift;
			bless { host => 'testhost'}, $class;
		});
	$sshmodule->mock('cmd', sub {
			my ($self, $cmd) = @_;
			if ($cmd eq "successful cmd") {
				return ("successful stdout\nline2", "", 0);
			} elsif ($cmd eq "stderr test") {
				return ("", "mystderr", 0);
			} elsif ($cmd eq "test dying cmd") {
				die "->cmd dying should be caught properly";
			} else {
				return ("command not found", "", 1);
			}
		});

	# bad command triggers crit
	ok_plugin(2,
		"SSHRUN CRITICAL - 'badcmd' did not execute successfully (rc: 1).",
		undef,
		"non-zero exit code triggers crit",
		sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SSHRUN";
			START;
			my $ssh = Net::SSH::Perl->new();
			RUN "badcmd", via => $ssh;
			OK "this should not have returned ok...";
			DONE;
		},
	);

	# bad command + failok doesn't trigger crit
	ok_plugin(0,
		"SSHRUN OK - this should have returned ok",
		undef,
		"non-zero exit code with 'failok' enabled",
		sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SSHRUN";
			START;
			my $ssh = Net::SSH::Perl->new();
			RUN "badcmd", via => $ssh, failok => 1;
			OK "this should have returned ok";
			DONE;
		},
	);

	# dies are caught + bail crit
	ok_plugin(2,
		"SSHRUN CRITICAL - Could not run 'test dying cmd' on testhost: ->cmd dying should be caught properly.",
		undef,
		"dies are caught/handled properly in run_via_ssh",
		sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SSHRUN";
			START;
			my $ssh = Net::SSH::Perl->new();
			RUN "test dying cmd", via => $ssh;
			OK "this should have returned ok";
			DONE;
		},
	);

	# everything is good in list context
	ok_plugin(0,
		"SSHRUN OK - got proper list output",
		undef,
		"list context for RUN returns properly formatted data",
		sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			use Test::Deep;
			PLUGIN name => "SSHRUN";
			START;
			my $ssh = Net::SSH::Perl->new();
			my @OUTPUT = RUN "successful cmd", via => $ssh;
			CRITICAL "AAH! Bad output response from RUN"
				unless eq_deeply(\@OUTPUT, ['successful stdout','line2']);
			OK "got proper list output";
			DONE;
		},
	);

	# everything is good in scalar context
	ok_plugin(0, "SSHRUN OK - got proper scalar output",
		undef,
		"scalar context for RUN returns raw output",
		sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			use Test::Deep;
			PLUGIN name => "SSHRUN";
			START;
			my $ssh = Net::SSH::Perl->new();
			my $OUTPUT = RUN "successful cmd", via => $ssh;
			CRITICAL "AAH! Bad output response from RUN"
				unless $OUTPUT eq "successful stdout\nline2\n";
			OK "got proper scalar output";
			DONE;
		},
	);
}
done_testing;
