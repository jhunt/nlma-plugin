package Synacor::SynaMon::Plugin::Feeders;

use Synacor::SynaMon::Plugin::Easy;
use POSIX qw/WEXITSTATUS WTERMSIG WIFEXITED WIFSIGNALED/;

use Log::Log4perl;

use Exporter;
use base qw(Exporter);

my %NSCA = (
	bin    => "/usr/bin/send_nsca",
	host   => "localhost",
	config => "/etc/icinga/send_nsca.cfg",
	port   => "5667",
	args   => "",
	max    => 700,
	noop   => 0,
);

my $PIPE;
my $N = -1;

my $LOG;
use constant HT_LOG_CONFIG => "/opt/synacor/monitor/etc/htlog.conf";

our @EXPORT = qw/
	SET_NSCA
	SEND_NSCA

	LOG
/;

$SIG{PIPE} = sub
{
	BAIL(CRITICAL "broken pipe: check send_nsca command");
};

sub _close_pipe
{
	return unless $PIPE;

	close $PIPE;
	$rc = $?;
	return if $rc == 0;
	if (WIFEXITED($rc)) {
		$rc = WEXITSTATUS($rc);
		CRITICAL "$NSCA{bin} exited with code $rc";
	} elsif (WIFSIGNALED($rc)) {
		$rc = WTERMSIG($rc);
		CRITICAL "$NSCA{bin} filled with signal $rc";
	} else {
		$rc = sprintf("0x%04x", $rc);
		CRITICAL "$NSCA{bin} terminated abnormally with code ($rc)";
	}
}

sub _exec_receiver
{
	_close_pipe;
	$N = 0;

	my $cmd = "$NSCA{bin} -H $NSCA{host} -c $NSCA{config} -p $NSCA{port} $NSCA{args}";
	if ($NSCA{noop}) {
		DEBUG "NOOP `$cmd`";
	} else {
		DEBUG "Executing `$cmd`";
		open $PIPE, "|-", $cmd
			or UNKNOWN "Failed to exec $NSCA{bin}: $!";
	}
}

sub SET_NSCA
{
	my (%C) = @_;
	for (keys %C) {
		next unless exists $NSCA{$_};
		$NSCA{$_} = $C{$_};
	}
}

sub SEND_NSCA
{
	my (%args) = @_;

	my $s;
	if (exists $args{service}) {
		$s = "$args{host}\t$args{service}\t$args{status}\t$args{output}";
	} else {
		$s = "$args{host}\t$args{status}\t$args{output}";
	}
	_exec_receiver if $N < 0 or $N >= $NSCA{max};
	$N++;
	DEBUG "SEND_NSCA $N/$NSCA{max}:\n'$s'";
	unless ($NSCA{noop}) {
		print $PIPE "$s\n\x17"
			or BAIL "SEND_NSCA failed: $!";
	}
}

sub LOG
{
	return $LOG if $LOG;

	if (OPTION->debug) {
		$ENV{HT_DEBUG} = "DEBUG";
	}

	my $service = $Synacor::SynaMon::Plugin::Easy::plugin->{bin};
	DEBUG "Setting up Log4perl for $service";

	if (exists $ENV{HT_TRACE} and $ENV{HT_TRACE}) {
		$ENV{HT_DEBUG} = "TRACE";
	}

	my $config = $ENV{HT_LOG_CONFIG} || HT_LOG_CONFIG;
	if (-f $config) {
		Log::Log4perl::init_and_watch($config, 'HUP');
	} else {
		my $literal = q|
			log4perl.rootLogger = WARN, DEFAULT
			log4perl.appender.DEFAULT = Log::Log4perl::Appender::Screen
			log4perl.appender.DEFAULT.layout = Log::Log4perl::Layout::PatternLayout
			log4perl.appender.DEFAULT.layout.ConversionPattern = :: [%P] %p: %m%n
		|;
		Log::Log4perl::init(\$literal);
	}
	$LOG = Log::Log4perl->get_logger($service);

	if (OPTION->debug) {
		$LOG->level("DEBUG");
		$LOG->debug("DEBUG logging initiated by user '$ENV{USER}' via --debug flag");
	} elsif ($ENV{HT_DEBUG}) {
		$LOG->level("DEBUG");
		$LOG->debug("DEBUG logging initiated by user '$ENV{USER}' via HT_DEBUG environment variable");
	}

	$LOG->info("Logger subsystem initialized from $config");
	return $LOG;
}

END {
	DEBUG "Initiating Feeder Shutdown";
	DEBUG "Closing send_nsca pipe" unless $NSCA{noop};
	_close_pipe;
}

1;
