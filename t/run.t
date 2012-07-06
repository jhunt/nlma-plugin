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

done_testing;
