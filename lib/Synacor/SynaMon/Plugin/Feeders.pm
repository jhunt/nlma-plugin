package Synacor::SynaMon::Plugin::Feeders;

use Synacor::SynaMon::Plugin::Easy;
use POSIX qw/WEXITSTATUS WTERMSIG WIFEXITED WIFSIGNALED/;

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

our @EXPORT = qw/
	CONFIG_NSCA
	SEND_NSCA

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

sub CONFIG_NSCA
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

END {
	DEBUG "Initiating Feeder Shutdown";
	DEBUG "Closing send_nsca pipe" unless $NSCA{noop};
	_close_pipe;
}

1;
