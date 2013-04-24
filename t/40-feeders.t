#!perl

use Test::More;
require "t/common.pl";
use Test::LongString;

use constant TEST_SEND_NSCA => "t/bin/send_nsca";
use constant TEST_NSCA_OUT  => "t/tmp/nsca.out";
use constant TEST_LOG_FILE  => "t/tmp/feeders";

sub slurp
{
	my ($file) = @_;
	open my $fh, "<", $file
		or BAIL_OUT "slurp($file) failed: $!";
	my $actual = do { local $/; <$fh> };
	close $fh;
	return $actual;
}

###################################################################
# feeder plugins

ok_plugin(0, "FEEDER OK - good", undef, "Basic Feeder Plugin", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	OK "good";
});

###################################################################
# send_nsca - bad exec

ok_plugin(3, "FEEDER UNKNOWN - t/bin/enoent: No such file or directory", undef, "SEND_NSCA / bad exec", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA bin => "t/bin/enoent";
	SET_NSCA chunk => "t/bin/chunk";
	SEND_NSCA host     => "a-host",
	          service  => "cpu",
	          status   => "WARNING",
	          output   => "Kinda High...";

	OK "sent";
});

###################################################################
# send_nsca - one chunk

unlink TEST_NSCA_OUT;
ok_plugin(0, "FEEDER OK - sent", undef, "SEND_NSCA a few times", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";
	SET_NSCA bin    => TEST_SEND_NSCA,
	         BOGUS  => "this is a bogus option",
	         config => TEST_NSCA_OUT;

	SEND_NSCA host     => "b-host",
	          status   => "UP",
	          output   => "its up!";

	SEND_NSCA host     => "a-host",
	          status   => "DOWN",
	          output   => "its broke!";

	SEND_NSCA host     => "a-host",
	          service  => "cpu",
	          status   => "CRITICAL",
	          output   => "Kinda High...";

	OK "sent";
});
is_string_nows(slurp(TEST_NSCA_OUT),
	"b-host\t0\tits up!\n".
	"a-host\t1\tits broke!\n".
	"a-host\tcpu\t2\tKinda High...\n",
		"send_nsca output is correct");

###################################################################
# send_nsca - bad status vals

unlink TEST_NSCA_OUT;
ok_plugin(0, "FEEDER OK - sent", undef, "SEND_NSCA / bad status", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";
	SET_NSCA bin    => TEST_SEND_NSCA,
	         BOGUS  => "this is a bogus option",
	         config => TEST_NSCA_OUT;

	SEND_NSCA host     => "host",
	          service  => "service",
	          status   => "REALLY-BAD",
	          output   => "its broke!";

	SEND_NSCA host     => "host",
	          service  => "service",
	          status   => "TERRIBLE",
	          output   => "its broke!";

	SEND_NSCA host     => "host",
	          service  => "service",
	          status   => 6,
	          output   => "its broke!";

	OK "sent";
});
is_string_nows(slurp(TEST_NSCA_OUT),
	"host\tservice\t3\tits broke!\n".
	"host\tservice\t3\tits broke!\n".
	"host\tservice\t3\tits broke!\n",
		"send_nsca output is correct");

###################################################################
# send_nsca - noop

unlink TEST_NSCA_OUT;
system("touch ".TEST_NSCA_OUT);
ok_plugin(0, "FEEDER OK - sent", undef, "SEND_NSCA noop", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";
	SET_NSCA bin    => TEST_SEND_NSCA,
	         config => TEST_NSCA_OUT,
	         noop   => "yes";

	SEND_NSCA host     => "a-host",
	          service  => "a-service",
	          status   => "CRITICAL",
	          output   => "its broke!";

	OK "sent";
});
is_string_nows(slurp(TEST_NSCA_OUT), "",
		"send_nsca output is correct");

###################################################################
# send_nsca - bad exit subchild

ok_plugin(2, "FEEDER CRITICAL - sub-process exited with code 4", undef, "SEND_NSCA bin exits non-zero", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";
	SET_NSCA bin  => "t/bin/die",
	         args => "--exit 4";

	SEND_NSCA host     => "a-host",
	          service  => "cpu",
	          status   => "WARNING",
	          output   => "Kinda High...";

	OK "good";
});

ok_plugin(2, "FEEDER CRITICAL - sub-process exited with code 4", undef, "SEND_NSCA bin exits non-zero (with DONE)", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";
	SET_NSCA bin  => "t/bin/die",
	         args => "--exit 4";

	SEND_NSCA host     => "a-host",
	          service  => "cpu",
	          status   => "WARNING",
	          output   => "Kinda High...";

	OK "good";
	DONE;
}, ['-D']);

ok_plugin(2, "FEEDER CRITICAL - sub-process killed by signal 15", undef, "SEND_NSCA bin killed", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";
	SET_NSCA bin  => "t/bin/die",
	         args => "--signal TERM";

	SEND_NSCA host     => "a-host",
	          service  => "cpu",
	          status   => "WARNING",
	          output   => "Kinda High...";

	OK "good";
});

###################################################################
# send_nsca - bail after 1 line of input

ok_plugin(2, "FEEDER CRITICAL - sub-process exited with code 2", undef, "SEND_NSCA / delayed broken pipe", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";
	SET_NSCA bin   => "t/bin/eat1"; # exits 2 after reading a single line

	SEND_NSCA host     => "a-host",
	          service  => "cpu",
	          status   => "WARNING",
	          output   => "Kinda High...";

	# By now, eat1 has closed STDIN
	# This call to SEND_NSCA should then SIGPIPE
	SEND_NSCA host     => "a-host",
	          service  => "cpu",
	          status   => "WARNING",
	          output   => "Kinda High...";

	OK "good";
});

###################################################################
# LOGGING

$ENV{HT_LOG_CONFIG} = "t/data/feederlog.conf";

unlink TEST_LOG_FILE;
ok_plugin(0, "FEEDER OK - logged", undef, "Feeder Logs", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";

	LOG->trace("this is a trace message");
	LOG->debug("this is a debug message");
	LOG->info("this is an info message");
	LOG->warn("this is a warning message");
	LOG->error("this is an error message");
	LOG->fatal("this is a fatal message");
	OK "logged";
});
is_string_nows(slurp(TEST_LOG_FILE),
	"WARN: this is a warning message\n".
	"ERROR: this is an error message\n".
	"FATAL: this is a fatal message\n",
		"log messages logged");

unlink TEST_LOG_FILE;
ok_plugin(0, "FEEDER OK - logged", undef, "Feeder Logs -D", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";

	LOG->trace("this is a trace message");
	LOG->debug("this is a debug message");
	LOG->info("this is an info message");
	LOG->warn("this is a warning message");
	LOG->error("this is an error message");
	LOG->fatal("this is a fatal message");
	OK "logged";
}, ['-D']);
unlike(slurp(TEST_LOG_FILE), qr/^TRACE:/m, "no trace messages in logs");
like(slurp(TEST_LOG_FILE), qr/^DEBUG:/m, "found debugging in logs");
like(slurp(TEST_LOG_FILE), qr/via --debug/m, "found evidence of --debug debugging in logs");

unlink TEST_LOG_FILE;
$ENV{HT_DEBUG} = 1;
ok_plugin(0, "FEEDER OK - logged", undef, "Feeder Logs -D", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";

	LOG->trace("this is a trace message");
	LOG->debug("this is a debug message");
	LOG->info("this is an info message");
	LOG->warn("this is a warning message");
	LOG->error("this is an error message");
	LOG->fatal("this is a fatal message");
	OK "logged";
});
unlike(slurp(TEST_LOG_FILE), qr/^TRACE:/m, "no trace messages in logs");
like(slurp(TEST_LOG_FILE), qr/^DEBUG:/m, "found debugging in logs");
like(slurp(TEST_LOG_FILE), qr/via HT_DEBUG/m, "found evidence of env var debugging in logs");
delete $ENV{HT_DEBUG};

unlink TEST_LOG_FILE;
$ENV{HT_TRACE} = 1;
ok_plugin(0, "FEEDER OK - logged", undef, "Feeder Logs -D", sub {
	use Synacor::SynaMon::Plugin qw(:feeder);
	open STDERR, ">", "/dev/null";
	PLUGIN name => "feeder";
	START;
	SET_NSCA chunk => "t/bin/chunk";

	LOG->trace("this is a trace message");
	LOG->debug("this is a debug message");
	LOG->info("this is an info message");
	LOG->warn("this is a warning message");
	LOG->error("this is an error message");
	LOG->fatal("this is a fatal message");
	OK "logged";
});
like(slurp(TEST_LOG_FILE), qr/^TRACE:/m, "found trace messages in logs");
like(slurp(TEST_LOG_FILE), qr/^DEBUG:/m, "found debugging in logs");
like(slurp(TEST_LOG_FILE), qr/via HT_TRACE/m, "found evidence of env var debugging in logs");
delete $ENV{HT_TRACE};

###################################################################
# cleanup

unlink TEST_LOG_FILE;
unlink TEST_NSCA_OUT;
done_testing;
