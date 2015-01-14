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
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "ls t";
	OK;
	DONE;
});

ok_plugin(3, "RUN UNKNOWN - /usr/bin/notacommand: no such file", undef, "bad path run", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/usr/bin/notacommand";
	OK;
	DONE;
});

ok_plugin(3, "RUN UNKNOWN - /etc/issue: not executable", undef, "non-exec path run", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/etc/issue | test -f /etc/issue";
	OK;
	DONE;
});

ok_plugin(0, "RUN OK", undef, "exec path run", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/bin/echo 'message here'";
	OK;
	DONE;
});

ok_plugin(2, "RUN CRITICAL - Command './t/run/exit_code 2' exited with code 2.", undef, "command non-zero exit", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "./t/run/exit_code 2";
	OK "failure is OK";
	DONE;
});

$ENV{TEST_PLUGINS} = 1;
$ENV{TEST_CHROOT}  = "./t/run";
ok_plugin(2, "RUN CRITICAL - Command './t/run/exit_code 2' exited with code 2.", undef, "TEST_PLUGINS + TEST_CHROOT", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/exit_code 2";
	OK "failure is OK";
	DONE;
});
delete $ENV{TEST_PLUGINS};
ok_plugin(3, "RUN UNKNOWN - /exit_code: no such file", undef, "TEST_CHROOT without TEST_PLUGINS", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/exit_code 0";
	OK;
	DONE;
});
delete $ENV{TEST_PLUGINS};
delete $ENV{TEST_CHROOT};

ok_plugin(0, "RUN OK - failure is OK", undef, "failok", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "./t/run/exit_code 2", failok => 1;
	OK "failure is OK";
	DONE;
});

ok_plugin(0, "RUN OK - return list", undef, "list context for RUN call", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	my @lines = RUN q[/bin/sh -c 'echo "first"; echo "second"; echo "third"'];
	my $output = join("|", @lines);
	$output =~ s/\r?\n/~~NEWLINE~~/gm;

	$output eq "first|second|third" or CRITICAL "Got the wrong output: $output";
	OK "return list";
	DONE;
});

# test unsported object as transport mechanism
ok_plugin(3,
	"RUNVIA UNKNOWN - Unsupported RUN mechanism: 'My::Protocol'",
	undef,
	"run via unsupported type fails",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "RUNVIA";
		START;
		my $ssh = My::Protocol->new;
		RUN "ls", via => $ssh;
		OK "this should not have returned ok...";
		DONE;
});

# test unsupported scalar as transport mechanism
ok_plugin(3,
	"RUNVIA UNKNOWN - Unsupported RUN mechanism: 'testing'",
	undef,
	"run via unsupported scalar fails",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => 'RUNVIA';
		START;
		RUN "ls", via => 'testing';
		OK "this should not have returned ok...";
		DONE;
});

# test RUN's default transport mechanism
ok_plugin(0, "RUNVIA OK - ls worked", undef, "test default transport mechanism for RUN", sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => 'RUNVIA';
		START;
		RUN "ls";
		OK "ls worked";
		DONE;
});

# test explicit setting of default transport mechanism
ok_plugin(0, "RUNVIA OK - explicit ls worked", undef, "test explicit 'shell' transport mechanism for RUN", sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => 'RUNVIA';
		START;
		RUN "ls", via => 'shell';
		OK "explicit ls worked";
		DONE;
});

# test that _run_via_shell sets last_rc
ok_plugin(0, "RUNVIA OK - last exit 1", undef, "ensure run_via_shell sets last_rc properly", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "RUNVIA";
		START;
		RUN "test -f thisisanonexistentfilethatshouldntexistduringtestingormynameisgeoffthedumbass", failok => 1;
		OK "last exit 1" if LAST_RUN_EXITED == 1;
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
			use NLMA::Plugin qw(:easy);
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
			use NLMA::Plugin qw(:easy);
			PLUGIN name => "SSHRUN";
			START;
			my $ssh = Net::SSH::Perl->new();
			RUN "badcmd", via => $ssh, failok => 1;
			OK "this should have returned ok";
			DONE;
		},
	);

	# bad command + failok - verify last_rc has been set
	ok_plugin(0,
		"SSHRUN OK - last exited 1",
		undef,
		"_run_via_ssh sets last_rc after running commands",
		sub {
			use NLMA::Plugin qw/:easy/;
			PLUGIN name => "SSHRUN";
			START;
			my $ssh = Net::SSH::Perl->new();
			RUN "badcmd", via => $ssh, failok => 1;
			CRITICAL "last_rc was set to " . LAST_RUN_EXITED unless LAST_RUN_EXITED == 1;
			OK "last exited 1";
			DONE;
		},
	);

	# dies are caught + bail crit
	ok_plugin(2,
		"SSHRUN CRITICAL - Could not run 'test dying cmd' on testhost: -%GT%cmd dying should be caught properly.",
		undef,
		"dies are caught/handled properly in run_via_ssh",
		sub {
			use NLMA::Plugin qw(:easy);
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
			use NLMA::Plugin qw(:easy);
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
			use NLMA::Plugin qw(:easy);
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
