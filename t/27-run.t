#!perl

use Test::More;
do "t/common.pl";

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

ok_plugin(0, "RUN OK - failure is OK", undef, "ok_failure test", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "RUN";
	START;
	RUN "/bin/ls /path/to/no/file", failok => 1;
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

done_testing;
