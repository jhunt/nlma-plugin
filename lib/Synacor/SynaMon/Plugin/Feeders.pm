package Synacor::SynaMon::Plugin::Feeders;

use Synacor::SynaMon::Plugin::Base;
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
	$args{status} = $Synacor::SynaMon::Plugin::Base::STATUS_CODES{$args{status}} || 3;

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

=head1 NAME

Synacor::SynaMon::Plugin::Feeders - Framework for Feeder Plugins

=head1 DESCRIPTION

Feeder plugins are a special breed of monitoring plugin that only run on the
Hammer Throw core servers, and feed results for all hosts monitored by that
node.

=head1 FUNCTIONS

=head2 SEND_NSCA %details

Submit a single result via the send_nsca utility.  The framework will
keep a running send_nsca process around for bulk operations (which is
what feeders do).

The B<%details> hash should contain the following keys:

=over

=item B<host>

=item B<service> (optional)

=item B<status>

=item B<output>

=back

B<NOTE:> check status can be specified as an integer between 0 and 3,
or as human-readable names like "CRITICAL" and "WARNING".  Unknown
values are treated as 3/UNKNOWN.

=head2 LOG

Retrieve a Log::Log4perl object for sending messages to the logging
subsystem.  The logger object returned will be properly memoized and
configured for the executing feeder / environment / debug flags.

=head2 SET_NSCA %settings

Configure the SEND_NSCA function, by specifying the following values:

=over

=item B<bin>

Absolute path to the send_nsca binary.

Defaults to I</usr/bin/send_nsca>

=item B<host>

Hostname or IP address of the host to submit feeder results to.

Defaults to I<localhost>

=item B<config>

Path to the send_nsca configuration file.

Defaults to I</etc/icinga/send_nsca.cfg>

=item B<port>

Port number to connect to.

Defaults to I<5667>

=item B<args>

Extra arguments to pass to send_nsca.

=item B<max>

Maximum number of results to send to a send_nsca process before
re-execing a new one.  This is to work around a bug in either send_nsca
or the NSCA daemon.

Defaults to I<700>.

=item B<noop>

Don't actually send results via send_nsca.  Useful for debugging.

Defaults to I<0> (i.e. not in noop mode).

=back

=head1 AUTHOR

Written by James Hunt <jhunt@synacor.com>

=cut
