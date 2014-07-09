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

ok_plugin(0, "DEBUG> test debugging", undef, "debug processing", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "done";

	open STDERR, ">&STDOUT";
	DEBUG "test debugging";

	DONE;
}, ["-D"]);

my $debug = <<EOF;
DEBUG> line1
DEBUG> line2

DEBUG> Finalizing plugin execution via DONE call

DEBUG OK - done
EOF
ok_plugin(0, $debug, undef, "multiline debug output", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "done";

	open STDERR, ">&", STDOUT;
	DEBUG "line1\nline2";

	DONE;
}, ["-D"], output => 'all');

ok_plugin(0, "DEBUG> undef", undef, "debug undef handling", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "done";

	open STDERR, ">&", STDOUT;
	DEBUG undef, "line 2";

	DONE;
}, ["-D"]);

ok_plugin(0, 'DEBUG> $VAR1 = "test";', undef, "object dump", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "done";

	open STDERR, ">&", STDOUT;
	DUMP "test";

	DONE;
}, ["-D"]);

ok_plugin(0, "DEBUG OK", undef, "no trace without -D", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START;

	open STDERR, ">&", STDOUT;
	TRACE "trace output";

	OK;
	DONE;
}, [""]);

ok_plugin(0, "DEBUG> debug output", undef, "no trace with just -D", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START;

	open STDERR, ">&", STDOUT;
	TRACE "trace output";
	DEBUG "debug output";

	OK;
	DONE;
}, ["-D"]);

ok_plugin(0, "DEBUG> debug output", undef, "no trace with just -DD", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START;

	open STDERR, ">&", STDOUT;
	TRACE "trace output";
	DEBUG "debug output";

	OK;
	DONE;
}, ["-DD"]);

ok_plugin(0, "TRACE> trace output", undef, "start TRACE-ing at -DDD", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START;

	open STDERR, ">&", STDOUT;
	TRACE "trace output";

	OK;
	DONE;
}, ["-D", "-D", "-D"]);

ok_plugin(0, "TRACE> trace output", undef, "keep TRACE-ing past -DDDD", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START;

	open STDERR, ">&", STDOUT;
	TRACE "trace output";

	OK;
	DONE;
}, ["-DDDDDDDD"]);

ok_plugin(0, 'TRACE> $VAR1 = "test";', undef, "object trace dump", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "done";

	open STDERR, ">&", STDOUT;
	TDUMP "test";

	DONE;
}, ["-DDDD"]);

$debug = <<EOF;
DEBUG> \$VAR1 = {
DEBUG>           "text" => "plain",
DEBUG>           "binary" => "\\32n\\204\\3\\0\\1\\0\\0\\0\\1\\0\\0\\5"
DEBUG>         };

DEBUG> Finalizing plugin execution via DONE call

DEBUG OK - done
EOF
ok_plugin(0, $debug, undef, "binary dumps", sub {
	# Temporarily redirect STDERR to /dev/null, since we don't want
	# any of the debug messages that START prints.
	open STDERR, ">", "/dev/null";

	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "DEBUG";
	START default => "done";

	open STDERR, ">&", STDOUT;
	DUMP { text => "plain", binary => "\32n\204\3\0\1\0\0\0\1\0\0\5" };

	DONE;
}, ["-D"], output => 'all');


done_testing;
