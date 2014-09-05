package Synacor::SynaMon::Plugin::Base;

use warnings;
use strict;

use Synacor::SynaMon::Plugin ();
use Nagios::Plugin qw();
use base qw(Nagios::Plugin);

use YAML::XS qw(LoadFile);
use JSON;
use Data::Dumper qw(Dumper);
use WWW::Mechanize;
use Net::SSH::Perl;
use POSIX qw/
	WEXITSTATUS WTERMSIG WIFEXITED WIFSIGNALED
	SIGALRM
	sigaction
	strftime
/;
use Fcntl qw(:flock);
use Time::HiRes qw(gettimeofday);
use File::Find;

# SNMP functionality is optional
eval 'use Net::SNMP';
eval 'use SNMP::MIB::Compiler';

# RRD functionality is optional
eval 'use RRDp';

use utf8;

use constant NAGIOS_OK       => 0;
use constant NAGIOS_WARNING  => 1;
use constant NAGIOS_CRITICAL => 2;
use constant NAGIOS_UNKNOWN  => 3;

use constant MESSAGE_TRUNCATED  => ' (alert truncated @4k)';
use constant MESSAGE_MAX_TOTAL  => 4000; # for some wiggle room
use constant MESSAGE_MAX_SINGLE => 500;

our %STATUS_NAMES = (
	OK       => "OK",
	WARNING  => "WARNING",
	WARN     => "WARNING",
	CRITICAL => "CRITICAL",
	CRIT     => "CRITICAL",
	UNKNOWN  => "UNKNOWN",

	0 => "OK",
	1 => "WARNING",
	2 => "CRITICAL",
	3 => "UNKNOWN",
);

our %STATUS_CODES = (
	OK       => NAGIOS_OK,
	WARN     => NAGIOS_WARNING,
	WARNING  => NAGIOS_WARNING,
	CRIT     => NAGIOS_CRITICAL,
	CRITICAL => NAGIOS_CRITICAL,
	UNKNOWN  => NAGIOS_UNKNOWN,

	UP       => NAGIOS_OK,
	DOWN     => NAGIOS_WARNING, # according to Nagios...

	0 => NAGIOS_OK,
	1 => NAGIOS_WARNING,
	2 => NAGIOS_CRITICAL,
	3 => NAGIOS_UNKNOWN,
);

our $TIMEOUT_MESSAGE = "Timed out";
our $TIMEOUT_STAGE = "running check";
our $ALL_DONE = 0;

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

sub new
{
	my ($class, %options) = @_;

	$ALL_DONE = 0;
	my $bin = do{my $n=$0;$n=~s|.*/||;$n};

	# Play nice with Nagios::Plugin
	($options{shortname} = uc($options{name} || $bin)) =~ s/^(CHECK|FETCH)_//;
	delete $options{name};

	if (exists $options{summary}) {
		$options{blurb} = $options{summary};
		delete $options{summary};
	}

	$options{usage} = "$options{shortname} [OPTIONS]";
	my $self = {
		contexts => {},
		name => $bin,
		shortname => $options{shortname},
		usage_list => [],
		options => {},
		pids => [],
		settings => {
			ignore_credstore_failures => 0,
			on_timeout                => NAGIOS_CRITICAL,
			missing_sar_data          => NAGIOS_WARNING,
			signals                   => 'perl',
			rrds                      => "/opt/synacor/monitor/rrd",
			rrdtool                   => "/usr/bin/rrdtool",
			rrdcached                 => "unix:/var/run/rrdcached/rrdcached.sock",
			on_rrd_failure            => NAGIOS_CRITICAL,
			bail_on_rrd_failure       => 1,
		},
		legacy => Nagios::Plugin->new(%options),
	};

	# HAHA! Take that Nagios::Plugin for trying to be helpful!
	# PEWPEWPEW! Options-be-gone!
	my @new_args;
	foreach my $arg (@{$self->{legacy}{opts}{_args}})
	{
		push (@new_args, $arg) if ($arg->{spec} !~ /(verbose|version|extra-opts)/);
	}
	$self->{legacy}{opts}{_args} = \@new_args;

	# ITM-2948 - reset global default timeout to 45s
	$self->{legacy}{opts}{timeout} = 45;

	bless($self, $class)->context('default');
}

sub context
{
	my ($self, $name) = @_;
	if (defined $name) {
		$self->{context} = $name;
		$self->{contexts}{$name} = {
				perfdata => [],
				messages => {
					UNKNOWN  => { len => 0, list => [], over => 0, count => 0 },
					OK       => { len => 0, list => [], over => 0, count => 0 },
					WARNING  => { len => 0, list => [], over => 0, count => 0 },
					CRITICAL => { len => 0, list => [], over => 0, count => 0 },
				},
			} unless exists $self->{contexts}{$name};

		$self->{perfdata} = $self->{contexts}{$name}{perfdata};
		$self->{messages} = $self->{contexts}{$name}{messages};
		$self;
	} else {
		$self->{context};
	}
}

sub mode
{
	$Synacor::SynaMon::Plugin::MODE;
}

sub set
{
	my ($self, %vars) = @_;
	for my $key (keys %vars) {
		my $value = $vars{$key};

		if ($key eq 'on_timeout' or $key eq 'missing_sar_data') {
			my $tmp_val = _nagios_code_for($value);
			if ($tmp_val) {
				$value = $tmp_val;
			}  else {
				$self->_bad_setting($key, $value, "(warning|critical|unknown)");
			}

		} elsif ($key eq 'signals') {
			if ($value !~ m/^perl|posix$/) {
				$self->_bad_setting($key, $value, "(perl|posix)");
			}

			if ($value ne $self->{settings}{$key}) {
				$self->debug("Signal handling style changed from $self->{settings}{$key} to $value",
				             "  Re-issuing signal handlers for active timeouts");

				# Set the value, so that start_timeout honors it...
				$self->{settings}{$key} = $value;
				# Forcibly re-issue the timeout, under new settings
				$self->start_timeout($self->stop_timeout);
			}
		} elsif ($key eq "on_previous_data_missing" ) {
			my $tmp_val = _nagios_code_for($value);
			if ($tmp_val) {
				$value = $tmp_val;
			} else {
				if ($value =~ /^ok/i) {
					$value = NAGIOS_OK;
				} else {
					$self->_bad_setting($key, $value, "(warning|critical|unknown|ok)");
				}
			}
		} elsif ($key eq "ssl_verify") {
			if ($value) {
				$self->debug("Enabling SSL hostname verification");
			} else {
				$self->debug("Disabling SSL hostname verification");
			}
			$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = $value ? 1 : 0;
		} elsif ($key eq "ignore_flock_failure") {
			if ($value) {
				$self->debug("Disabling flock failure detection");
			} else {
				$self->debug("Enabling flock failure detection");
			}

		}

		$self->{settings}{$key} = $value;
	}
}

sub _bad_setting
{
	my ($self, $key, $val, $allowed) = @_;
	$self->debug("CODE ISSUE: Bad value for `$key` settings",
		"  '$val' not one of $allowed");

	$self->bail(NAGIOS_UNKNOWN,
		"check plugin BUG detected: run again with --debug");
}

sub _nagios_code_for
{
	my ($str) = @_;
	if ($str =~ /^warn/i) {
		return NAGIOS_WARNING;
	} elsif ($str =~ /^crit/i) {
		return NAGIOS_CRITICAL;
	} elsif ($str =~ /^unk/i) {
		return NAGIOS_UNKNOWN;
	} else {
		return undef;
	}
}

sub _spec2usage
{
	my ($usage, $required) = @_;
	return unless $required;

	$usage =~ s/,\s+/|/;
	$usage;
}

my @percent_style_opts = ();
sub option
{
	my ($self, $spec, %opts) = @_;
	if ($spec) {
		if ($spec eq "timeout|t=i") {
			$self->{legacy}{opts}{timeout} = $opts{default} if $opts{default};
			return;
		}

		if (!exists($opts{framework})) {
			if ($spec =~ m/\busage\b/ || $spec =~ m/^\?/ || $spec =~ m/\|\?/) {
				$self->status('UNKNOWN', "Option spec $spec conflicts with built-in usage|? option");
			}
			for (qw/debug|D   noop   noperf   help|h/) {
				next unless $spec =~ m/\b($_)\b/;
				$self->status('UNKNOWN', "Option spec $spec conflicts with built-in $_ option");
			}
		}
		delete $opts{framework};

		if ($spec =~ /^(\S+?)(\|\S+)?=%$/) {
			push @percent_style_opts, $1;
			$spec =~ s/=%$/=s\@/;
		}

		if (exists $opts{usage}) {
			push @{$self->{usage_list}}, _spec2usage($opts{usage}, $opts{required});

			$opts{help} = $opts{usage} . (exists $opts{help} ? "\n   " . $opts{help} : "");
			delete $opts{usage};
		}

		if (exists $opts{default}) {
			$opts{help} .= " (default: $opts{default})";
		}

		return $self->{legacy}->add_arg(
			spec => $spec,
			%opts
		);
	} else {
		return $self->{legacy}->opts;
	}
}

sub usage
{
	my ($self) = @_;
	$self->{name} . " -h|--help\n". join(' ', $self->{name}, @{$self->{usage_list}});
}

sub track_value
{
	my ($self, $label, $value, %opts) = @_;
	return if $self->{noperf};

	for (qw/warning critical min max/) {
		$opts{$_} = '' unless defined $opts{$_};
	}

	my $s = sprintf("%s=%s;%s;%s;%s;%s", $label, $value,
		$opts{warning}, $opts{critical}, $opts{min}, $opts{max});
	$s =~ s/;;$//; # no min/max
	push @{$self->{perfdata}}, $s;
}

sub _reformat_hash_option
{
	my @instances = @_;
	my %opt = ();
	my $allowed_keys = '(warn|crit|perf)';

	foreach my $instance (@instances) {
		my ($name, $rest) = split(/:/, $instance, 2);
		my $values = { warn => undef, crit => undef, perf => $name};
		if ($rest) {
			my @vals = split(/,/, $rest);
			foreach my $val (@vals) {
				my ($key, $value) = split(/=/, $val);
				return "$name:$val\nSub-option keys must be one of '$allowed_keys'."
					unless $key =~ /^$allowed_keys$/;
				if ($key eq 'perf') {
					if (defined $value && ($value eq '0' || $value eq 'no')) {
						$value = 0;
					} else {
						$value = $value || $name;
					}
				}
				$values->{$key} = $value;
			}
		}
		$opt{$name} = $values;
	}
	return \%opt;
}
sub getopts
{
	my ($self) = @_;
	$self->option("debug|D+",
		usage => "--debug, -D",
		help  => "Turn on debug mode",
		framework => 1,
	);
	$self->option("noop",
		usage => "--noop",
		help  => "Dry-run mode",
		framework => 1,
	);
	$self->option("noperf",
		usage => "--noperf",
		help  => "Skip submission of performance data",
		framework => 1,
	);
	$self->{legacy}->opts->{_attr}{usage} = $self->usage;
	open OLDERR, ">&", \*STDERR;
	open STDERR, ">&STDOUT";
	$self->{legacy}->getopts;
	$self->{legacy}->opts->{_attr}{usage} = $self->usage ;
	foreach my $hash_opt (@percent_style_opts) {
		my $processed_opt = _reformat_hash_option(@{$self->{legacy}->opts->{$hash_opt}});
		if (ref($processed_opt) eq "HASH") {
			$self->{legacy}->opts->{$hash_opt} = $processed_opt;
		} else {
			$self->{legacy}->opts->_die("Invalid sub-option: --$hash_opt=$processed_opt\n". $self->usage. "\n");
		}
	}
	open STDERR, ">&", \*OLDERR;
}

sub status
{
	my ($self, $status, @message) = @_;
	my ($code, $name);
	if (defined $status && defined $STATUS_CODES{$status} && defined $STATUS_NAMES{$status}) {
		($code, $name) = ($STATUS_CODES{$status}, $STATUS_NAMES{$status});
	} else {
		($code, $name) = ($STATUS_CODES{"UNKNOWN"}, $STATUS_NAMES{"UNKNOWN"});
	}

	$status = "undef" unless defined $status;

	my $msg = join('', @message) || '';

	my $len = length($msg);
	if ($len > MESSAGE_MAX_SINGLE) {
		$len = MESSAGE_MAX_SINGLE;
		$msg = substr($msg, 0, $len);
	}

	$self->debug("Adding $name ($code) from [$status] message: $msg");

	$msg =~ s/&/%AMP%/g;
	$msg =~ s/~/%TILDE%/g;
	$msg =~ s/\$/%DOLLAR%/g;
	$msg =~ s/</%LT%/g;
	$msg =~ s/>/%GT%/g;
	$msg =~ s/"/%QUOT%/g;
	$msg =~ s/`/%BTIC%/g;
	$msg =~ s/\|/%PIPE%/g;
	$msg =~ s/[\r\n\x0b]//g;

	if ($code == NAGIOS_UNKNOWN && $self->{context} eq 'default') {
		$ALL_DONE = 1;
		$self->terminate(NAGIOS_UNKNOWN, $msg);
	} else {
		$self->{messages}{$name}{count}++;
		# store the message and update length
		push (@{$self->{messages}{$name}{list}}, $msg) if $msg;
		$self->{messages}{$name}{len} += $len + 1;

		# make sure we don't go over our 4k limit
		while ($self->{messages}{$name}{len} - 1  > MESSAGE_MAX_TOTAL) {
			$self->{messages}{$name}{over} = 1;

			my $drop = shift @{$self->{messages}{$name}{list}};
			$self->{messages}{$name}{len} -= length($drop) + 1;
		}
	}

	return $code, $msg;
}

sub check_status
{
	my ($self) = @_;
	my ($status, $msg) = (NAGIOS_UNKNOWN, "Check appears to be broken; no problems triggered");

	if ($self->{messages}{UNKNOWN}{count}) {
		$status = NAGIOS_UNKNOWN;
		$msg    = join(' ', @{$self->{messages}{UNKNOWN}{list}});
		$msg   .= MESSAGE_TRUNCATED if $self->{messages}{UNKNOWN}{over};

	} elsif ($self->{messages}{CRITICAL}{count}) {
		$status = NAGIOS_CRITICAL;
		$msg    = join(' ', @{$self->{messages}{CRITICAL}{list}});
		$msg   .= MESSAGE_TRUNCATED if $self->{messages}{CRITICAL}{over};

	} elsif ($self->{messages}{WARNING}{count}) {
		$status = NAGIOS_WARNING;
		$msg    = join(' ', @{$self->{messages}{WARNING}{list}});
		$msg   .= MESSAGE_TRUNCATED if $self->{messages}{WARNING}{over};

	} elsif ($self->{messages}{OK}{count}) {
		$status = NAGIOS_OK;
		$msg    = join(' ', @{$self->{messages}{OK}{list}});
		$msg   .= MESSAGE_TRUNCATED if $self->{messages}{OK}{over};
	}

	return ($status, $msg);
}

sub check_perfdata
{
	my ($self, $output) = @_;
	$output .= " |". join(' ', @{$self->{perfdata}}) if @{$self->{perfdata}};
	$output;
}

sub terminate
{
	my ($self, $status, $msg) = @_;
	if (!defined $status) {
		($status, $msg) = $self->check_status;
	}

	my $output = "$self->{shortname} $STATUS_NAMES{$status}";
	$output .= " - $msg" if $msg;
	$output = $self->check_perfdata($output);

	print "$output\n";
	exit $status;
}

sub bail
{
	my ($self, $status, $message) = @_;
	$ALL_DONE = 1;
	if (! defined $message) {
		$message = $status unless defined $message;
		$status = 'UNKNOWN';
	}
	(my $code, $message) = $self->status($status, $message);
	$self->debug("Bailing $status ($code) from message: $message");
	$self->terminate($code, $message);
}

sub evaluate
{
	my ($self, $status, @message) = @_;
	if (defined $status && defined $STATUS_NAMES{$status} && defined $STATUS_CODES{$status} ) {
		@message = () if $STATUS_CODES{$status} == NAGIOS_OK;
	}
	$self->status($status, @message);
}

sub OK
{
	my ($self, @message) = @_;
	$self->status(NAGIOS_OK, @message);
}

sub WARNING
{
	my ($self, @message) = @_;
	$self->status(NAGIOS_WARNING, @message);
}

sub CRITICAL
{
	my ($self, @message) = @_;
	$self->status(NAGIOS_CRITICAL, @message);
}

sub UNKNOWN
{
	my ($self, @message) = @_;
	$self->status(NAGIOS_UNKNOWN, @message);
}

sub start
{
	my ($self, %opts) = @_;

	$ALL_DONE = 1; # in case we bomb out in getopts
	$self->getopts;
	$ALL_DONE = 0;

	$self->{debug}  = $self->option->debug;
	$self->{noop}   = $self->option->noop;
	$self->{noperf} = $self->option->noperf;
	$self->debug("Starting ".$self->mode." execution");

	if (exists $opts{default}) {
		$self->debug("Setting default OK message");
		$self->OK($opts{default});
	}

	$self->start_timeout($self->option->{timeout}, $TIMEOUT_STAGE);
}

sub finalize
{
	my ($self, $via) = @_;
	return if $ALL_DONE;
	$ALL_DONE = 1;
	$self->debug("Finalizing ".$self->mode." execution via $via");
	$self->terminate();
}

sub done
{
	my ($self) = @_;
	$self->finalize("DONE call") unless $self->mode eq 'feeder';
}

sub analyze_thold
{
	my ($self, $value, $thresh) = @_;
	$self->debug("Comparing '$value' to threshold '$thresh'");

	$self->{legacy}->set_thresholds(warning => $thresh); # use warning to get a 1 rc for matches
	my $stat = $self->{legacy}->check_threshold($value);
	$self->debug($stat ? "Value matched requested threshold" : "Value still nominal");
	return $stat;
}

sub check_value
{
	my ($self, $value, $message, %thresh) = @_;
	$self->debug("Setting thresholds to:",
	             "    warning:  ".(defined $thresh{warning}  ? $thresh{warning}  : "(unspec)"),
	             "    critical: ".(defined $thresh{critical} ? $thresh{critical} : "(unspec)"));
	$self->{legacy}->set_thresholds(%thresh);

	my $skip_OK = undef;
	if (exists $thresh{skip_OK}) {
		$skip_OK = $thresh{skip_OK} ? 1 : undef;
		delete $thresh{skip_OK};

		$self->debug("skip_OK specified; will not register OK message");
	}

	$self->debug("Evaluating ($value) against thresholds");
	my $stat = $self->{legacy}->check_threshold($value);
	$self->debug("Threshold check yielded status $stat");
	return $stat, $message if $skip_OK && $stat == NAGIOS_OK;
	$self->status($stat, $message);
}

sub noop
{
	my ($self) = @_;
	return $self->{noop};
}

sub debug
{
	my ($self, @messages) = @_;
	return unless $self->{debug};
	for (@messages) {
		$_ = (defined($_) ? $_: "undef");
		s/\n+$//;
		s/\n/\nDEBUG> /g;
		print STDERR "DEBUG> $_\n";
	}
	print STDERR "\n";
}

sub dump
{
	my ($self, @vars) = @_;
	return unless $self->{debug};

	local $Data::Dumper::Pad = "DEBUG> ";
	local $Data::Dumper::Useqq = 1;
	print STDERR Dumper(@vars);
	print STDERR "\n";
}

sub trace
{
	my ($self, @messages) = @_;
	return unless $self->{debug} && $self->{debug} >= 3;
	for (@messages) {
		$_ = (defined($_) ? $_: "undef");
		s/\n+$//;
		s/\n/\nTRACE> /g;
		print STDERR "TRACE> $_\n";
	}
	print STDERR "\n";
}

sub trace_dump
{
	my ($self, @vars) = @_;
	return unless $self->{debug} && $self->{debug} >= 3;

	local $Data::Dumper::Pad = "TRACE> ";
	local $Data::Dumper::Useqq = 1;
	print STDERR Dumper(@vars);
	print STDERR "\n";
}

sub deprecated
{
	my ($self, $msg) = @_;
	if ($ENV{MONITOR_FAIL_ON_DEPRECATION}) {
		$self->UNKNOWN("DEPRECATION NOTICE: $msg");
	} else {
		print STDERR "DEPRECATION NOTICE: $msg\n";
	}
}

sub stage
{
	my ($self, $action) = @_;
	$self->debug("Entering stage '$action'");
	$self->{stage_started} = gettimeofday;
	$self->{plugin_started} = gettimeofday unless defined $self->{plugin_started};
	$TIMEOUT_STAGE = $action;
}

sub start_timeout
{
	my ($self, $seconds, $action) = @_;
	$TIMEOUT_MESSAGE = "Timed out after ${seconds}s";
	$self->debug("Setting timeout for ${seconds}s");
	$self->stage($action) if $action;

	my $handler = sub {
		$self->debug("SIGALRM received, trying to clean up + abort the check.");
		# Don't remove this! there are some processes *cough*cassandra-cli*cough*
		# That don't exit when perl exits and sends child processes a signal to exit
		kill(15, @{$self->{pids}});
		sleep 1;
		kill(9,  @{$self->{pids}});

		print "$TIMEOUT_MESSAGE: $TIMEOUT_STAGE\n";
		$ALL_DONE = 1;
		exit $self->{settings}{on_timeout};
	};

	if ($self->{settings}{signals} eq 'posix') {
		$self->debug("Using POSIX sigaction for SIGALRM handler");
		my $old  = POSIX::SigAction->new;
		my $new  = POSIX::SigAction->new($handler, POSIX::SigSet->new(SIGALRM));
		sigaction(SIGALRM, $new, $old);

	} else {
		$self->debug("Using Perl SIG{ALRM} for SIGALRM handler");
		$SIG{ALRM} = $handler;
	}
	alarm $seconds;

	$self->{timeout_for} = $seconds;
	$self->{timeout_started} = time;
}

sub stop_timeout
{
	my ($self) = @_;
	alarm(0);

	my $duration = time - $self->{timeout_started};
	delete $self->{timeout_started};

	my $remaining = $self->{timeout_for} - $duration;
	delete $self->{timeout_for};

	$self->debug("Stopped timeout after $duration seconds",
	             "  with $remaining seconds remaining");
	return $remaining;
}

sub stage_time
{
	my ($self) = @_;
	return gettimeofday - $self->{stage_started};
}

sub total_time
{
	my ($self) = @_;
	return gettimeofday - $self->{plugin_started};
}

sub slurp
{
	my ($self, $path) = @_;
	if ($ENV{TEST_PLUGINS} and $ENV{TEST_SLURP_FILE}) {
		$self->debug("TEST_PLUGINS and TEST_CHROOT are set; using file: $ENV{TEST_SLURP_FILE}");
		$path = "$ENV{TEST_SLURP_FILE}";
	} elsif ( $ENV{TEST_PLUGINS} and $ENV{TEST_CHROOT} and -d $ENV{TEST_CHROOT}) {
		$self->debug("TEST_PLUGINS and TEST_CHROOT are set; using files in $ENV{TEST_CHROOT}");
		$path = "$ENV{TEST_CHROOT}/$path";
	}
	return unless defined $path && -f $path && -r $path;
	open my $fh, '<', $path;

	my @lines = ();
	my $string;
	while (<$fh>) {
		my $line = $_;
		$string .= $line;
		chomp($line);
		push(@lines, $line);
	}

	close $fh;
	return wantarray ? @lines : $string;
}

sub state_file_path
{
	my ($self, $path, %options) = @_;
	my $dir    = $ENV{MONITOR_STATE_FILE_DIR} || $options{in} || "/var/tmp";
	my $prefix = $ENV{MONITOR_STATE_FILE_PREFIX} || "mon";
	$path =~ s|.*/||;
	$path =~ s/[!@#\$%\^&\*\(\)\|\}\{\[\]\/'"><\s\x0b]+/_/g;
	return "$dir/${prefix}_$path";
}

sub store
{
	my ($self, $path, $data, %options) = @_;
	return unless defined $data;

	# do this part before re-opening the state file (and losing all our previous data that _process_bulk_data will try to read in)
	my $archive_data;
	if ($options{as} && $options{as} =~ m/^data_archive$/i) {
		eval { $archive_data = JSON->new->allow_nonref->encode($self->_process_bulk_data($path, $data)); };
	}

	$self->bail(NAGIOS_UNKNOWN, "Tried to STORE into $options{in} (Framework Violation)")
		if $options{in} and $options{in} !~ m|^(/var)?/tmp(/.*)?$|;

	$path = $self->state_file_path($path, %options);

	if ($self->noop) {
		$self->debug("Running in NOOP mode; not writing to state files");
			return;
	}



	open my $fh, ">", "$path.tmp" or
		$self->bail(NAGIOS_UNKNOWN, "Could not open '$path.tmp' for writing");
	my $flock_fail = 0;
	flock $fh, LOCK_EX|LOCK_NB or $flock_fail = 1;
	$self->bail(NAGIOS_UNKNOWN, "Unable to obtain file lock on '$path.tmp'")
		if !$self->{settings}{ignore_flock_failure} && $flock_fail;

	if ($options{as} && $options{as} !~ m/^raw$/i) {
		if ($options{as} =~ m/^ya?ml$/i) {
			$data = YAML::XS::Dump $data;
		} elsif ($options{as} =~ m/^json$/i) {
			eval { $data = JSON->new->allow_nonref->encode($data); };
		} elsif ($options{as} =~ m/^data_archive$/i) {
			#keep this section so that
			$data = $archive_data;
		} else {
			$self->UNKNOWN("Unknown format for STORE: $options{as}");
		}
	} elsif (ref($data) eq "ARRAY") { # RAW lines...
		$self->deprecated("STORE(ref) is deprecated as of v1.20; use 'as => yaml' or 'as => json'");
		$data = join('', @$data);
	}
	print $fh $data;
	flock $fh, LOCK_UN unless $flock_fail;
	close $fh;
	rename "$path.tmp", $path;

	my (undef, undef, $uid, $gid) = getpwnam($ENV{MONITOR_STATE_FILE_OWNER} || 'nlma');
	chown $uid, $gid, $path;
}

sub _process_bulk_data
{
	my ($self, $path, $obj) = @_;
	my $status = defined $self->{settings}{on_previous_data_missing} ?
		$self->{settings}{on_previous_data_missing} : NAGIOS_WARNING;
	my $age_limit = defined $self->{settings}{delete_after} ?
		$self->{settings}{delete_after} : (24 * 60 * 60);

	my $data_history = $self->retrieve($path, as => 'json');
	$self->status($status, "No previous data found.") if ($status && ! defined $data_history);

	foreach my $time (sort keys %{$data_history}) {
		$self->debug("Testing $time against $age_limit");
		if ($time < time - $age_limit) {
			$self->debug("Deleting datapoint for $time. Too old. (>= $age_limit)");
			delete $data_history->{$time};
		} else {
			#optimization to skip processing if we're done deleting
			last;
		}
	}

	$data_history->{time()} = $obj;
	$self->debug("data_archive for $path is now:");
	$self->dump($data_history);
	return $data_history;
}

sub retrieve
{
	my ($self, $path, %options) = @_;

	$self->bail(NAGIOS_UNKNOWN, "Tried to RETRIEVE from $options{in} (Framework Violation)")
		if $options{in} and $options{in} !~ m|^(/var)?/tmp(/.*)?$|;

	$path = $self->state_file_path($path, %options);

	if ($options{touch} && -e $path) {
		utime(undef, undef, $path);
	}

	$self->debug("Using '$path' for retrieval");

	open my $fh, "<", $path or do {
		$self->debug("FAILED to open '$path' for reading: $!");
		return undef;
	};

	my $data = do { local $/; <$fh> };
	close $fh;

	if ($options{as} && $options{as} !~ m/^raw$/i) {
		$self->debug("Retrieved RAW data:");
		$self->dump($data);

		if ($options{as} =~ m/^ya?ml$/i) {
			return eval { YAML::XS::Load($data) };
		}

		if ($options{as} =~ m/^json$/i) {
			return eval { JSON->new->allow_nonref->decode($data) };
		}

		$self->UNKNOWN("Unknown format for RETRIEVE: $options{as}");
	}
	if (wantarray) {
		$self->deprecated("RETRIEVE in list context is deprecated");
		return map { "$_\n" } split /\n/, $data;
	}
	return $data;
}

sub _userdir
{
	my ($username) = @_;
	return undef unless $username;
	my @info = getpwnam($username);
	return @info ? $info[7] : undef;
}

sub _credstore_path
{
	my ($self) = @_;
	return $ENV{MONITOR_CRED_STORE} if exists $ENV{MONITOR_CRED_STORE};
	my $homedir = _userdir($ENV{SUDO_USER}) || _userdir(getpwuid($>));
	return "$homedir/.creds" if $homedir;
	"/home/nlma/.creds";
}

sub credentials
{
	my ($self, @keys) = @_;
	my $ignore = $self->{settings}{ignore_credstore_failures};

	my $filename = $self->_credstore_path;
	$self->debug("Retrieving credentials from $filename");

	unless (-f $filename) {
		$self->debug("Credstore '$filename' does not exist");
		return undef if $ignore;
		$self->bail(NAGIOS_UNKNOWN, "Could not find credentials file");
	}

	unless (-r $filename) {
		$self->debug("Credstore '$filename' exists but is not readable");
		return undef if $ignore;
		$self->bail(NAGIOS_UNKNOWN, "Could not read credentials file");
	}

	my @stat = stat($filename);
	if (!$ignore && (!@stat || ($stat[2] & 07777) != 0400)) {
		$self->bail(NAGIOS_UNKNOWN, sprintf("Insecure credentials file; mode is %04o (not 0400)",
				$stat[2] & 07777));
	}

	my $yaml = LoadFile($filename);
	unless (ref($yaml) eq "HASH") {
		$self->debug("Credstore '$filename' does not contain a YAML hashref");
		return undef if $ignore;
		$self->bail(NAGIOS_UNKNOWN, "Corrupted credentials file");
	}

	for my $name (@keys) {
		$self->debug("Checking credentials store for '$name'");

		if (exists $yaml->{$name}) {
			unless ($yaml->{$name}{username} || $yaml->{$name}{password}) {
				$self->debug("Corrupt credentials key $name");
				return undef if $ignore;
				$self->bail(NAGIOS_UNKNOWN, "Corrupt credentials key '$name'");
			}
			return ($yaml->{$name}{username}, $yaml->{$name}{password});
		}
	}

	return undef if $ignore;
	$self->bail(NAGIOS_UNKNOWN, "Credentials not found for '".join("', '", @keys)."'");
}

sub cred_keys
{
	my ($self, $type, $hostname) = @_;

	$self->debug("Generating candidate cred keys for $type/$hostname");

	my @keys;

	if ($hostname =~ /^\d+\.\d+\.\d+\.\d+$/) {
		@keys = ("$type/$hostname", $type); # $hostname is an IP here..
	} else {
		$hostname =~ m/^([a-z]+)[^\.]*\.(.*)/;
		my ($role, $cluster) = ($1, $2);
		$cluster =~ s/\.synacor\.com$//;

		@keys = (
			"$type/$hostname",       # host-specific
			"$type/$cluster/$role",  # cluster / role specific
			"$type/$cluster/*",      # cluster-global
			"$type/*/$role",         # role-global
			$type,                   # ...
		);
	}

	return @keys;
}

sub last_run_exit_reason
{
	my ($self) = @_;
	if (WIFEXITED($self->{last_rc})) {
		return "normal";
	} elsif (WIFSIGNALED($self->{last_rc})) {
		return "signal";
	}

	return "abnormal";
}

sub last_run_exited
{
	my ($self) = @_;
	if (WIFEXITED($self->{last_rc})) {
		return WEXITSTATUS($self->{last_rc});
	} elsif (WIFSIGNALED($self->{last_rc})) {
		return WTERMSIG($self->{last_rc});
	}

	return sprintf "0x%04x", $self->{last_rc};
}

sub run
{
	my ($self, $command, %opts) = @_;
	my $via = exists $opts{via} ? $opts{via} : "shell";
	if (ref $via) {
		if ($via->isa("Net::SSH::Perl")){
			$self->_run_via_ssh($via, $command, %opts);
		} else {
			$self->bail(NAGIOS_UNKNOWN, "Unsupported RUN mechanism: '".ref($via)."'");
		}
	} else {
		if ($via eq "shell") {
			$self->_run_via_shell($command, %opts);
		} elsif (defined $via) {
			$self->bail(NAGIOS_UNKNOWN, "Unsupported RUN mechanism: '$via'");
		} else {
			$self->bail(NAGIOS_UNKNOWN, "Undefined RUN mechanism explicitly requested!");
		}
	}
}

sub _run_via_shell
{
	my ($self, $command, %opts) = @_;
	$self->{last_rc} = undef;
	if ($ENV{TEST_PLUGINS} and $ENV{TEST_CHROOT} and -d $ENV{TEST_CHROOT}) {
		$self->debug("TEST_PLUGINS and TEST_CHROOT are set; using commands in $ENV{TEST_CHROOT}");
		$command = "$ENV{TEST_CHROOT}$command";
	}
	my $bin = $command;
	$bin =~ s/\s+.*//;

	# Command to run, minus volatile "|" character,
	# which has special meaning to Nagios.
	my $safe = $command;
	$safe =~ s/\s*\|.*/ .../;

	$self->debug("Running `$command`\nCommand is '$bin'");
	# If $bin is a path, check that it exists and is executable
	if ($bin =~ m|/|) {
		$self->bail(NAGIOS_UNKNOWN, "$bin: no such file")   unless -f $bin;
		$self->bail(NAGIOS_UNKNOWN, "$bin: not executable") unless -x $bin;
	}

	my $pid = open my $pipe, "$command|";
	if (!$pipe) {
		$self->bail(NAGIOS_UNKNOWN, "Failed to run $bin");
	}
	push @{$self->{pids}}, $pid;

	my @lines = <$pipe>;
	close $pipe;
	my $rc = $?;
	$self->{last_rc} = $rc;

	if ($rc != 0 && !$opts{failok}) { # caller expects command to exit 0
		# handle normal exit, signal death or unknown properly
		if (WIFEXITED($rc)) {
			$rc = WEXITSTATUS($rc);
			$self->CRITICAL("Command '$safe' exited with code $rc.");
		} elsif (WIFSIGNALED($rc)) {
			$rc = WTERMSIG($rc);
			$self->CRITICAL("Command '$safe' killed with signal $rc");
		} else {
			$rc = sprintf("0x%04x", $rc);
			$self->CRITICAL("Command '$safe' terminated abnormally with code ($rc)");
		}
	}

	return wantarray ? (map { chomp; $_ } @lines) : join('', @lines);
}

sub _run_via_ssh
{
	my ($self, $ssh, $cmd, %opts) = @_;
	$self->{last_rc} = undef;
	my ($stdout, $stderr, $rc);
	$self->debug("Executing: '$cmd'");
	eval {
		# Test if we're connected, dies if we aren't
		# This prevents $ssh->cmd from setting rc to 0 during transport failures
		$ssh->sock;

		($stdout, $stderr, $rc) = $ssh->cmd($cmd);
		$self->{last_rc} = $rc;
		$stdout = "" unless defined $stdout;
		$stderr = "" unless defined $stderr;
		if (! $opts{failok} && $rc != 0) {
			$self->CRITICAL("'$cmd' did not execute successfully (rc: $rc).");
		}
		$stdout =~ s/\r\n/\n/g;
		$stderr =~ s/\r\n/\n/g;
		print STDERR $stderr if $stderr;
		1;
	} or do {
		$self->debug("Exception caught: $@");
		$@ =~ s/ at \S+ line \d+//;
		$self->bail("CRITICAL", "Could not run '$cmd' on $ssh->{host}: $@");
	};

	return wantarray ? split(/\n/, $stdout) : ($stdout !~ /\n$/ ? $stdout .= "\n": $stdout);
}

sub ssh
{
	my ($self, $hostname, $user, $pass, $opts) = @_;

	$opts->{debug} = "1" if $self->{debug};
	if ($hostname =~ s/:(\d+)//) {
		$opts->{port} = $1;
	}

	my $failok = delete $opts->{failok};
	my $homedir = _userdir($ENV{SUDO_USER}) || _userdir(getpwuid($>));
	$opts->{identity_files} ||= [ "$homedir/.ssh/id_rsa", "$homedir/.ssh/id_dsa", "$homedir/.ssh/identity" ];
	$opts->{identity_files}   = [ $opts->{identity_files} ] if (ref($opts->{identity_files}) ne "ARRAY");

	my ($ssh, $error);
	eval {
		# Depending on the underlying mechanism pulling in user/password info, data
		# may be in utf8. Net::SSH::Perl handles this poorly, so decode it all just
		# in case before passing to Net::SSH::Perl.
		utf8::decode($user);
		utf8::decode($pass);
		$ssh = Net::SSH::Perl->new($hostname, %$opts)
			or do { $error = "Couldn't connect to $hostname"; };
		if ($ssh) {
			$ssh->login($user, $pass)
				or do { $error = "Could not log in to $hostname as $user"; };
		}
		1;
	} or do {
		$self->debug("Exception caught: $@");
		$@ =~ s/ at \S+ line \d+//;
		$error = "Could not ssh to $hostname as $user: $@";
	};

	if ($error) {
		if ($failok) {
			return undef;
		} else {
			$self->bail("CRITICAL", $error);
		}
	}

	return $ssh;
}

sub mech
{
	my ($self, $options) = @_;

	if (! $self->{mech} || $options->{recreate}) {
		my $mech = WWW::Mechanize->new(autocheck => 0);
		$mech->cookie_jar({});
		$mech->agent($options->{UA} || "SynacorMonitoring/$Synacor::SynaMon::Plugin::VERSION");
		$mech->timeout($options->{timeout} || $self->option->{timeout} || 15);
		$self->{mech} = $mech;
	}

	return $self->{mech};
}

sub http_request
{
	my ($self, $method, $uri, $data, $headers, $options) = @_;
	$method  = uc($method);
	$headers = $headers || {};
	$options = $options || {};

	$self->debug("Making HTTP Request: $method $uri");
	$self->dump($data) if $method eq "POST"
	                   or $method eq "PUT"
	                   or $method eq "DELETE";

	my $request = HTTP::Request->new($method => $uri);
	for my $h (keys %$headers) {
		$self->debug("   '$h: $headers->{$h}'");
		$request->header($h, $headers->{$h});
	}
	if (($method eq "POST" || $method eq "PUT" || $method eq "DELETE") and $data) {
		$request->content($data);
	}

	if (exists $options->{username} && exists $options->{password}) {
		$request->authorization_basic($options->{username}, $options->{password});
	}

	$options->{recreate} = 1
		if $options->{timeout} && $options->{timeout} != $self->mech->timeout;
	$self->mech($options);
	my $res = $self->mech->request($request);
	my $res_data = defined $res->decoded_content ? $res->decoded_content : $res->content;
	return wantarray ?
		($res, $res_data) :
		$res->is_success;
}

sub http_get
{
	my ($self, $uri, $headers, $options) = @_;
	$self->http_request(GET => $uri, undef, $headers, $options);
}

sub http_post
{
	my ($self, $uri, $data, $headers, $options) = @_;
	if (ref($data) && ref($data) ne 'SCALAR') {
		$self->UNKNOWN("HTTP_POST called incorrectly; \$data not a scalar reference");
	}
	$self->http_request(POST => $uri, $data, $headers, $options);
}

sub http_put
{
	my ($self, $uri, $data, $headers, $options) = @_;
	if (ref($data) && ref($data) ne 'SCALAR') {
		$self->UNKNOWN("HTTP_PUT called incorrectly; \$data not a scalar reference");
	}
	$self->http_request(PUT => $uri, $data, $headers, $options);
}

sub submit_form
{
	my ($self, @options) = @_;
	my $response;
	eval {
		$response = $self->mech->submit_form(@options);
	} or do {
		$self->CRITICAL("Form submission failed: $@") if $@;
	};

	return wantarray ?
		($response, $response->decoded_content) :
		$response->is_success;
}

sub json_decode
{
	my ($self, $data) = @_;
	my $obj;
	$data = $data || "";
	if ($data =~ /^[^\(]*\((.*)\);?$/) { # JSONP
		$data = $1;
	}
	eval { $obj = JSON->new->allow_nonref->decode($data); }
}

my @UNITS = qw/B KB MB GB TB PB EB YB ZB/;
sub parse_bytes
{
	my ($self, $s) = @_;
	return undef if !defined $s;
	return 0 if !$s;
	$s =~ m/^(\d+(?:\.\d+)?)([^\d]+)/i or return int($s);
	my ($num, $unit) = ($1, uc($2));
	for (@UNITS) {
		return $num if $unit eq $_ or "${unit}B" eq $_;
		$num *= 1024;
	}
	$self->UNKNOWN("Bad size spec: '$s'");
}

sub format_bytes
{
	my ($self, $b, $fmt) = @_;
	return '<undef>' if !defined $b;
	my $orig = $b+0;
	$fmt = '%0.2f%s' unless $fmt;
	for (@UNITS) {
		return sprintf($fmt, $b, $_) if $b < 1024;
		$b /= 1024.0;
	}
	$self->UNKNOWN("Size $orig is unfathomably large (>1ZB)");
}

sub parse_time
{
	my ($self, $s) = @_;
	return undef if !defined $s;
	my $t = 0;
	while ($s =~ m/\G\s*(\d+(?:\.\d+)?)\s*([a-zA-Z])?/g) {
		my $x = $1;
		$x *= 60      if $2 and $2 eq 'm';
		$x *= 3600    if $2 and $2 eq 'h';
		$x *= 86400   if $2 and $2 eq 'd';
		$x *= 7*86400 if $2 and $2 eq 'w';
		$t += $x;
	}
	$t;
}

sub format_time
{
	my ($self, $s, $fmt) = @_;
	return '<undef>' if !defined $s;
	$fmt = '%i%s' unless $fmt;

	my $u = 's';
	return sprintf($fmt, $s, $u) if $s < 120;
	$s /= 60; $u = 'm';

	return sprintf($fmt, $s, $u) if $s < 120;
	$s /= 60; $u = 'h';

	return sprintf($fmt, $s, $u) if $s < 36;
	$s /= 24; $u = 'd';

	return sprintf($fmt, $s, $u);
}

sub jolokia_connect
{
	my ($self, %params) = @_;
	my $ignore = $self->{settings}{ignore_jolokia_failures};

	if (!$params{host}) {
		$self->debug("No 'host' specified to JOLOKIA_CONNECT, bailing");
		return if $ignore;
		$self->bail(NAGIOS_CRITICAL, "No 'host' specified for Jolokia/JMX connection");
	}
	if (!$params{port}) {
		$self->debug("No 'port' specified to JOLOKIA_CONNECT, bailing");
		return if $ignore;
		$self->bail(NAGIOS_CRITICAL, "No 'port' specified for Jolokia/JMX connection");
	}

	$self->{_jolokia_target} = "$params{host}:$params{port}";

	my ($user, $pass) = $self->credentials($params{creds} || 'remote_jmx');
	$params{target} = {
		user     => $user,
		password => $pass,
		url      => "service:jmx:rmi:///jndi/rmi://$self->{_jolokia_target}/jmxrmi",
	};

	$params{proxy} = $ENV{MONITOR_JOLOKIA_PROXY} || "localhost:5080";
	$self->debug("Jolokia: using proxy '$params{proxy}'");
	$self->{jolokia} = \%params;
}

sub jolokia_request
{
	my ($self, $request) = @_;
	my $ignore = $self->{settings}{ignore_jolokia_failures};

	my $url = "http://$self->{jolokia}{proxy}/jolokia/";
	$self->debug("Making Jolokia request to $url with:");
	# add unused query params to make jolokia request log correlation easier
	$url .= "?syn_host=$self->{_jolokia_target}&syn_check_plugin=$self->{name}";

	$self->dump($request);

	my ($res, $json) = $self->http_post($url, JSON->new->allow_nonref->encode($request));
	$self->debug("Jolokia returned a ".$res->status_line." response");

	if (!$res->is_success) {
		return undef if $ignore;
		$self->bail(NAGIOS_CRITICAL, "Jolokia returned a ".$res->status_line." response");
	}

	# FIXME: trace returned JSON data!
	my $data = $self->json_decode($json) or do {
		$self->debug("Invalid JSON detected!");
		return undef if $ignore;
		$self->bail(NAGIOS_CRITICAL, "Jolokia returned invalid JSON: $@");
	};

	# FIXME: trace for JSON dump!
	$data = [$data] if ref($data) eq 'HASH';
	if (ref($data) ne 'ARRAY') {
		$self->debug("Returned JSON data is ".ref($data)."-formatted, not an ARRAY");
		return undef if $ignore;
		$self->bail(NAGIOS_CRITICAL, "Jolokia returned ".ref($data)."-formatted (wanted an ARRAY)");
	}

	my @list;
	my $n = 0;
	for my $r (@$data) {
		$n++;
		if (exists $r->{error}) {
			my $error = ($r->{request}{mbean} || "Jolokia/JMX Result #$n").
				" encountered an error: ".($r->{error} || '(unspecified error)');

			$self->debug($error);
			next if $ignore;
			$self->bail(NAGIOS_CRITICAL, $error);
		}
		push @list, $r;
	}

	return \@list;
}

sub jolokia_read
{
	my ($self, @beans) = @_;
	$self->UNKNOWN("Check appears to be broken; JOLOKIA_READ called before JOLOKIA_CONNECT")
		unless $self->{jolokia};

	my @reqs = ();
	return {} unless @beans;
	for my $mbean (@beans) {
		push @reqs, {
			target => $self->{jolokia}{target},
			type   => 'read',
			mbean  => $mbean,
		};
	}

	my $data = $self->jolokia_request(\@reqs)
		or return {};

	return { map { $_->{request}{mbean} => $_->{value} } @$data };
}

sub jolokia_search
{
	my ($self, $match) = @_;
	$self->UNKNOWN("Check appears to be broken; JOLOKIA_SEARCH called before JOLOKIA_CONNECT")
		unless $self->{jolokia};

	unless ($self->{_jolokia_beans}) {
		$self->{_jolokia_beans} = $self->jolokia_request({
			target => $self->{jolokia}{target},
			type   => 'search',
			mbean  => '*:*',
		}) or return wantarray ? () : {};
	}

	# See http://www.jolokia.org/reference/html/protocol.html#search
	my $data = $self->{_jolokia_beans}; $data = $data->[0]{value};

	my $total = 0;
	my $matched = 0;
	my $results = [];

	for my $bean (@$data) {
		$total++;
		$self->trace("Checking bean '$bean'\n".
		             "      against /$match/") if $match;
		next if $match && $bean !~ m/$match/i;
		$matched++;
		push @$results, $bean;
	}

	$self->debug("Matched $matched / $total beans") if $match;
	return wantarray ? @$results : $results;
}

sub _get_sar
{
	my ($self, $args, $file, $oldest, $data) = @_;
	return unless -f $file;

	if (!$self->{sar_version}) {
		$self->debug("Auto-detecting version of sysstat/sar installed");
		(local $_, undef) = qx(sar -V 2>&1); chomp;
		$self->debug("sar -V said '$_'");

		$self->{sar_version} = 0;
		$self->{sar_version} = $1 if m/^sysstat version (\d+)\./;
	}

	if (!$self->{sar_version}) {
		$self->debug("Failed to detect sysstat/sar version!");
	}

	my $command = "/usr/bin/sadf -- $args $file";
	   $command = "sar -h $args -f $file"           if $self->{sar_version} == 5;
	   $command = "/usr/bin/sadf -T -- $args $file" if $self->{sar_version} == 10;

	for ($self->run($command)) {
		# i.e: |vm01.jhunt  58      1390366861      lo      rxerr/s 0.00|
		next unless m/\S+\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)$/;
		my ($ival, $ts, $key, $attr, $val) = ($1, $2, $3, $4, $5, $6);
		next if $ts < $oldest;
		$data->{$ts}{$key}{$attr} = $val;
	}
}

sub sar
{
	my ($self, $args, %opts) = @_;
	$opts{slice}   ||= 60; # Synacor uses 1m sadc intervals
	$opts{samples} ||= 1;  # By default, only care about the last sample
	$opts{logs}    ||= "/var/log/sa";
	my $span = $opts{samples} * $opts{slice};
	if ($span > 86400) {
		$self->debug("NOTE - It is ill-advised to ask SAR for more than 24h of data,",
		             "       Truncating request for $span seconds of data down to 1d.");
		$span = 86400;
	}

	my $data = {};
	my $file;
	my $now = time;
	my $oldest   = $now - $span; $oldest -= ($oldest % $opts{slice});

	my @t = localtime($now); @t[0 .. 2] = (0,0,0);
	my $midnight = strftime("%s", @t);
	$self->debug("Ignoring any sar data older than $oldest (now:$now, midnight:$midnight)");

	if ($oldest < $midnight) {
		$self->debug("Detected midnight rollover; looking at yesterdays data");
		$file = sprintf("%s/sa%02d", $opts{logs}, (localtime($now - 86400))[3]);
		$self->_get_sar($args, $file, $oldest, $data);
	}
	$file = sprintf("%s/sa%02d", $opts{logs}, (localtime($now))[3]);
	$self->_get_sar($args, $file, $oldest, $data);

	my $n = 0;
	my $collapsed = {};
	for my $ts (reverse sort keys %$data) {
		if (!defined $ts or !exists $data->{$ts}) {
			$self->debug("Did not find ts '$ts' \@$n");
			next;
		}
		$self->trace("Found sample #$n \@$ts");
		last if $n == $opts{samples};
		$n++;
		for my $key (keys %{$data->{$ts}}) {
			for my $attr (keys %{$data->{$ts}{$key}}) {
				$collapsed->{$key}{$attr} += $data->{$ts}{$key}{$attr};
			}
		}
	}
	if ($n == 0) {
		$self->bail($self->{settings}{missing_sar_data}, "No sar data found for sar $args");
		return {};
	}
	if ($n > 1) {
		$self->debug("Collapsed $n SAR samples down to 1");
		for my $key (keys %$collapsed) {
			for my $attr (keys %{$collapsed->{$key}}) {
				$collapsed->{$key}{$attr} = $collapsed->{$key}{$attr} / $n;
			}
		}
	}
	$collapsed = $collapsed->{'-'}
		if keys %$collapsed == 1 and
		   exists $collapsed->{'-'};
	return $collapsed;
}

sub calculate_rate
{
	my ($self, %opts) = @_;
	if (!$opts{store}) {
		$self->WARNING("Need a store file to get previous data");
		return {};
	}
	if (!$opts{data}) {
		$self->WARNING("Need data to parse");
		return {};
	}
	$opts{want} = [keys %{$opts{data}}] if !$opts{want};
	$opts{want} = [ $opts{want} ] unless ref($opts{want}) eq "ARRAY";
	my $NOW = time;
	$opts{data}->{check} = $NOW;

	$opts{resolution} = $self->parse_time($opts{resolution} || 60);
	$opts{resolution} = 60 if $opts{resolution} <= 0;

	my $then = $self->retrieve($opts{store}, as => 'yaml');
	if (!$then) {
		$self->WARNING("No historic data found; rate calculation deferred");
		return {};
	}
	$self->debug("Calculating change for current data:");
	$self->dump($opts{data});

	$self->debug("Found historic state data:");
	$self->dump($then);

	my @fields;
	my $rollover = 0;
	for (@{$opts{want}}) {
		next unless exists $opts{data}->{$_} and exists $then->{$_};
		$rollover = 1 if $opts{data}->{$_} < $then->{$_};
		push @fields, $_;
	}

	if ($rollover) {
		$self->debug("Wraparound/rollover detected:\n".
		      join("\n", map { sprintf("  %-15s -> %s", $_, $then->{$_}, $opts{data}->{$_}) }
		        sort @fields));
		$self->WARNING("Service restart detected (values reset to near-zero)");
		return {};
	}

	my $span = $NOW - $then->{check};
	if ($span <= 0) {
		$self->debug("${span}s time span detected (data from $then->{check} vs $NOW)\n".
		      "Skipping rate-based checks altogether");
		return {};

	} elsif ($opts{stale} && $span > $self->parse_time($opts{stale})) {
		$self->WARNING("Stale data detected; last sample was ".$self->format_time($span)." ago");
		return {};
	}

	$self->debug("${span}s time span detected ($opts{resolution}s resolution)");
	$span /= $opts{resolution};
	my $data = { map { $_ => ($opts{data}->{$_} - $then->{$_}) / $span } @fields };

	$self->debug("Calculated per-minute rates:");
	$self->dump($data);

	return $data;
}

my %DEVNAME = ();
sub _devnames
{
	return if keys %DEVNAME;
	open my $fh, "<", "/proc/mounts" or return;
	while (<$fh>) {
		my ($dev, $mount) = split /\s+/;
		next unless $dev =~ m{^/dev/.};
		my @st = stat($dev) or next;
		my ($maj, $min) = (int($st[6] / 256), $st[6] % 256);
		$DEVNAME{"dev$maj-$min"} = $mount;
	}
	close $fh;
}

sub devname
{
	my ($self, @rest) = @_;
	_devnames;
	my @a = map { $DEVNAME{$_} } @rest;
	return wantarray ? @a : $a[0];
}

sub _snmp_check
{
	return if $INC{'SNMP/MIB/Compiler.pm'} and $INC{'Net/SNMP.pm'};
	shift->UNKNOWN("SNMP::MIB::Compiler not installed; SNMP functionality disabled")
		unless $INC{'SNMP/MIB/Compiler.pm'};
	shift->UNKNOWN("Net::SNMP not installed; SNMP functionality disabled")
		unless $INC{'Net/SNMP.pm'};
}

sub _snmp_init
{
	my ($self) = @_;
	$self->_snmp_check;
	return if $self->{mibc};
	$self->{mibc} = SNMP::MIB::Compiler->new;
	$self->{mibc}->{debug_lexer}     = 0;
	$self->{mibc}->{debug_recursive} = 0;
	$self->{mibc}->{make_dump}       = 1;
	$self->{mibc}->{use_dump}        = 1;
	$self->{mibc}->{do_imports}      = 1;

	my @paths = ();
	find(sub {
		return unless -d;
		push @paths, $File::Find::name;
	}, $ENV{MONITOR_MIBS} || '/opt/synacor/monitor/lib/snmp');
	$self->trace("Looking for SNMP MIBs in $_") for @paths;
	$self->{mibc}->add_path(@paths);
	$self->{mibc}->add_extension('', '.my', '.mib', '.txt');

	$self->{mibc_cache} = "/var/tmp/mibc.cache";
	$self->trace("caching compiled MIB definitions in $self->{mibc_cache}");
	mkdir $self->{mibc_cache};
	$self->{mibc}->repository($self->{mibc_cache});

	$self->snmp_mib('SNMPv2-MIB');
}

sub snmp_mib
{
	my ($self, @mibs) = @_;
	$self->_snmp_check;
	$self->_snmp_init;
	for (@mibs) {
		$self->debug("loading SNMP MIB $_");
		eval {
			$self->{mibc}->compile($_);
			$self->{mibc}->load($_);
		};
		if ($@) {
			$self->debug("Caught an exception: $@");
			$self->UNKNOWN("Unknown MIB: $_");
		}
	}
	return 1;
}

sub snmp_session
{
	my ($self, $endpoint, %opts) = @_;
	$self->_snmp_check;
	return $self->{snmp_session} if @_ == 1;

	$opts{port}      ||= 161;
	$opts{version}   ||= '2c';
	$opts{community} ||= 'public';
	$opts{timeout}   ||= 5;

	$self->{snmp_session} = Net::SNMP->session(
		-hostname  => $endpoint,
		-port      => $opts{port},
		-version   => $opts{version},
		-community => $opts{community},
		-timeout   => $opts{timeout},
	) or return undef;

	$self->{snmp_session}->get_request(-varbindlist => ['1.3.6.1.2.1.1.5'])
		or return undef;

	# some of the F5 VServer OIDs are too big for the default
	# maximum message size, so we raise it here
	$self->{snmp_session}->max_msg_size(65535);

	$self->debug("Connected to $endpoint UDP/$opts{port} v$opts{version} community $opts{community}");
	$self->debug("====[ SNMP IDENTITY ]=======================================",
	             "sysName:     ".$self->snmp_get('1.3.6.1.2.1.1.5.0'),
	             "sysContact:  ".$self->snmp_get('1.3.6.1.2.1.1.4.0'),
	             "sysLocation: ".$self->snmp_get('1.3.6.1.2.1.1.6.0'),
	             "sysObjectID: ".$self->snmp_get('1.3.6.1.2.1.1.2.0'),
	             "sysDescr:    ".$self->snmp_get('1.3.6.1.2.1.1.1.0'),
	             "============================================================");

	return 1;
}

sub snmp_get
{
	my ($self, @oids) = @_;
	$self->_snmp_check;
	my $r = $self->{snmp_session}->get_request(-varbindlist => $self->oids(@oids));
	($r) = (values %$r) if @oids == 1;
	return $r;
}

sub snmp_tree
{
	my ($self, $oid) = @_;
	$self->_snmp_check;
	$oid = $self->oid($oid);
	my $r = $self->{snmp_session}->get_table(-baseoid => $oid);

	my $h = {};
	for (keys %$r) {
		my $v = $r->{$_};
		s/^\Q$oid.\E//;
		$h->{$_} = $v;
	}
	return $h;
}

sub snmp_table
{
	my $self = shift;
	$self->_snmp_check;
	my %map = (ref($_[0]) ? %{$_[0]} : map { $_ => "[$_]" } @_);
	my $h = {};
	for my $key (keys %map) {
		my $r = $self->snmp_tree($map{$key});
		$h->{$_}{$key} = $r->{$_} for keys %$r;
	}
	return $h;
}

sub snmp_enum
{
	my ($self, $value, $type, $format) = @_;
	$self->_snmp_check;
	$self->_snmp_init;
	my $s = $format || "%s";
	my $name = $self->{mibc}{nodes}{$type}{syntax}{values}{$value} || "UNKNOWN";

	$s =~ s/%s/$name/g;
	$s =~ s/%i/$value/g;
	$s;
}

sub snmp_tc
{
	my ($self, $value, $type, $format) = @_;
	$self->_snmp_check;
	$self->_snmp_init;
	my $s = $format || "%s";
	my $name = $self->{mibc}{types}{$type}{syntax}{values}{$value} || "UNKNOWN";

	$s =~ s/%s/$name/g;
	$s =~ s/%i/$value/g;
	$s;
}

sub oid
{
	my ($self, $oid) = @_;
	$self->_snmp_check;
	$self->_snmp_init;
	$oid =~ s/\[([^\]]*)\]/$self->{mibc}->resolve_oid($1)/ge;
	return $oid;
}

sub oids
{
	my $self = shift;
	$self->_snmp_check;
	return [map { $self->oid($_) } split /\s+/, join(' ', @_)];
}

sub _rrd_check
{
	return 1 if $INC{'RRDp.pm'};

	shift->UNKNOWN("RRDp not installed; RRD functionality disabled");
	return undef;
}

sub _rrd_error
{
	my ($self, $msg) = @_;

	$msg =~ s/ at \S+ line \d+//;
	if ($self->{settings}{bail_on_rrd_failure}) {
		$self->bail($self->{settings}{on_rrd_failure}, $msg);
	} else {
		$self->status($self->{settings}{on_rrd_failure}, $msg);
	}
}

sub rrd
{
	my ($self, $cmd, $file, @args) = @_;

	$self->_rrd_check or return undef;;

	$ENV{RRDCACHED_ADDRESS} = $self->{settings}{rrdcached};

	unless ($self->{rrdp_running}) {
		RRDp::start($self->{settings}{rrdtool});
		$self->{rrdp_running} = 1;
	}

	my $path = $file =~ m|^/| ? $file : $self->{settings}{rrds} . "/$file";
	$path .= ".rrd" unless $path =~ /\.rrd$/;

	my $data;
	eval {
		RRDp::cmd($cmd, $path, @args);
		$data = RRDp::read();
		if ($RRDp::error) {
			$self->_rrd_error($RRDp::error);
		}
		1;
	} or do {
		$self->_rrd_error($@);
	};
	return $data;
}

1;

=head1 NAME

Synacor::SynaMon::Plugin::Base - Monitoring Plugin::Base Framework

=head1 DESCRIPTION

B<Synacor::SynaMon::Plugin::Base> defines a custom object layer that wraps the standard
B<Nagios::Plugin> library and exports some additional convenience methods.  Most of
the logic makes writing monitoring check plugins easier, more straightforward and
less error-prone.

=head1 METHODS

=head2 new

Create a new Plugin::Base object.

=head2 context([$name])

Mange plugin execution context.  If you don't know what this is, you don't need it.

With no arguments, the name of the current context is returned.

With a single argument, plugin execution will switch to that context.  Sufficient
context defaults will be set up if the context doesn't already exist.  Returns the
plugin object itself.

=head2 mode

Return a string representing the current execution mode.  This is used internally
to alter behavior for feeder plugins.

=head2 set

Set one or more behavior-modifying settings.  See Synacor::Synamon::Plugin(3)
for a full list of settings, legal values and their purpose.

=head2 option

The B<option> function supports two modes. Retrieval of option data, and defining
options. If no arguments are passed to the B<option> call, retrieval mode is invoked.
Otherwise, definition mode is invoked.

=over

=item Retrieval

B<option> also gives you access to the passed values, as a hash
reference, when called with no arguments:

  if ($plugin->option->mode == "mysql") {
    # do stuff specific to MySQL...
  }

=item Definition

Define a command-line argument for the check script. Based on two parts: spec,
and options.

  $plugin->option('dbname|n=s',
    usage => "--dbname, -n <table name>",
    help  => "Name of the database to connect to",
    required => 1
  );

=over

=item spec

The first argument is the GetOpt-style argument spec, with one exception.
Unlike GetOpt, plugins support a '=%' style specification, which is somewhat
similar to '=s@' specs, but with additional parsing, to turn a specifically
formatted parameter into a hashref of data related to the name specified. Format
is as follows:

  --parameter_name key1:opt1=val,opt2=val,...

Possible values for B<optN> names are B<warn>, B<crit>, and B<perf>. B<perf>
defaults to B<keyN>, and allows you to override it to '0' or 'no' to turn off
perfdata reporting, or with a custom value for use with custom perfdata
labelling. B<warn>/B<crit> default to undefined values. B<keyN>
values can be any you desire, and will be used as keys in the hashref returned
when this option is called in B<Retrieve> mode. Subsequent calls of
B<--parameter_name> would result in additional keys being added to the hashref
to be returned by this option.

See B<Synacor::SynaMon::Plugin> for extensive examples of how to use the specs.

'B<=%>' style option specs have been available since version 1.16.

=item options

The remainder of the arguments passed to the options() sub represent
contraints and extra information about this option.  The following keys are valid:

=over

=item usage

A short example of how the option can and should be called.

=item help

A description of what the option specified, or how it affects plugin behavior.

=item required

Whether or not the option is required.  If the plugin is run without specifying
all required options, the plugin usage will be shown and the script will terminate.

=item default

Supply a default value for this option, to be used if an alternate value is
not supplied.

=back

=back

=back

=head2 track_value

Track performance and trending data.

=head2 getopts

Process command-line options, populating the plugin object.

=head2 status

Trigger a check status, with an optional status message:

  $plugin->status(NAGIOS_WARNING, "Warning!  Bad things about to happen");

Execution continues on afterwards;  If you want to exit immediately,
look at B<bail>.

Valid status codes are:

=over

=item NAGIOS_CRITICAL

=item NAGIOS_UNKNOWN

=item NAGIOS_WARNING

=item NAGIOS_OK

=back

Shorthand methods exist that pass predetermined status codes:

=over

=item CRITICAL

=item UNKNOWN

=item WARNING

=item OK

=back

=head2 terminate([$status, $message])

Exit appropriately and print out the summary message and any performance
data we have collected so far.  If $status and $message are not given,
they will be determined by calling B<check_status>.

=head2 check_status()

Returns the status code and output / summary string, based on calls to
OK, WARNING, CRITICAL and UNKNOWN (if UNKNOWN didn't cause immediate
termination).

=head2 check_perfdata($msg)

Append performance data to $msg, and return it, if appropriate.

=head2 bail

Trigger a check status (with a status message) and exit immediately.
Works like B<status> except that it immediately causes the plugin to exit,
triggering the specified level.

=head2 evaluate

Trigger a check status (with a status message), but only if the status
code is not OK.

=head2 start

Start plugin execution and process command-line arguments.

=head2 done

Wrapper for B<finalize>, for explicitly ending execution of a plugin.

=head2 finalize($method)

Finalize plugin execution, and exit with the appropriate return code
and status message, formatted for Nagios.

B<finalize> should be called from END blocks, with an argument of
"END block".  It is called automatically by B<done>

=head2 analyze_thold

Compares a value against a given threshold, and returns a boolean
of whether the value matches/violates the threshold. A true value
is returned when the threshold was matched/violated. A false value
is returned when the value was not yet in violation of the threshold.

=head2 check_value

Checks a value against a set of thresholds, and triggering whatever
problem state is most appropriate

  $plugin->check_value($cpu,
      sprintf("CPU Usage is %0.2f%%", $cpu*100),
      warning => 0.8, critical => 0.9);

This call sets two thresholds that will trigger a WARNING at 80% or
higher, and a CRITICAL at 90% or higher, and then check $cpu against them.

=head2 debug

Print debugging statements, but only if the B<--debug> flag was
specified.  All debugging statements are prefixed with 'DEBUG> '
to set them apart from normal output (whether expected or not).

Several parts of the framework call B<debug> internally.  This way,
most check writers get a lot of useful debugging information for
free, and can focus on adding to that where it makes sense.

=head2 dump

Intelligently dump a list of objects, but only if the B<--debug>
flag was specified.

=head2 trace

Print trace-level debugging statements, which are intended for check plugin
authors, as a debugging aide.  Trace output should be reserved for verbose
things that most people won't care about (like the internals for the plugin
framework).

Unless B<--trace> and B<--debug> are enabled, trace-messages will be
skipped.

All trace output is prefixed with 'TRACE> ' to differentiate it from normal
output and debugging output.

=head2 trace_dump

Just like B<dump()>, but works at the same level as B<trace()>.

=head2 deprecated($message)

Handle deprecation of features.  This is an internal method that is
only intended to be used by other parts of this module, and not by
plugins written in the framework.

In normal mode, deprecation notices are printed directly to standard
error, for diagnostic purposes.

If the MONITOR_FAIL_ON_DEPRECATION environment value is set to a non-zero,
non-empty value, the plugin will exit immediately with an UNKNOWN status
when it encounters a call to this function.

=head2 noop

Helper function that returns true of the --noop argument was
specified.

=head2 stage

Sets the current stage of check plugin execution, which is used
to produce useful status messages when a timeout hits 0.

A call to B<start_timeout> will call B<stage> with its second
parameter; but check plugin writers are free to call stage multiple
times within a single timeout region:

  $plugin->start_timeout(45, "connecting to API");
  # connect to the API

  $plugin->stage("checking API response");
  # check API response...

  $plugin->stage("testing API re-request");
  # re-request something

  $plugin->stop_timeout;

Depending on when the timeout expires, the appropriate status
message will be used.

=head2 start_timeout

Starts a timeout timeout.

  $plugin->start_timeout(30, "requesting HTTP");
  # do something that could take a while
  $plugin->stop_timeout;

In this example, a 30 second timeout will be enforced.  If the
execution of everything up to the B<stop_timeout> call takes longer
than this, the entire check will fail with a CRITICAL status code
and a status message along the lines of "Timed out after 30s:
requesting HTTP".

=head2 stop_timeout

Clears the currently active timeout timeout.

=head2 stage_time

Returns the (HiRes) number of seconds since the current stage began.

=head2 total_time

Returns the (HiRes) number of seconds since the first stage began.

=head2 slurp

Takes a string file path and returns the contents as a scalar or as an array
of the lines in the file.

The scalar output will include new line characters.

If called as an array each element in the output will correspond to a line
in the slurped file, there will be no newline characters in this output.

=head2 state_file_path

Generate the absolute path to a state file, based on package configuration,
environment variables and a path fragment.

For example:

  my $state = $plugin->state_file_path("save.state");

May generate a file path like I</var/tmp/mon_save.state>.

This function also handles the C<in> option that B<store> and B<retrieve>
support, for determining where the state file should exist on the filesystem:

  my $state = $plugin->state_file_path("save.state", in => "/tmp/other");

Will generate the path I</tmp/other/mon_save.state>.

=head2 store

Stores a value in a state file.

  $plugin->store("check_logs.seek", $seek_pos, %options);

The created state file will be modified so that its permissions are correct
and its uid/gid ownership is sane.

If the store operation cannot be carried out, either because of permissions
or intervening directories, the framework will trigger an UNKNOWN problem with
a suitable message for debugging.

Supported keys for B<%options>:

=over

=item B<as>

Defines formatter type to store the data as.

Supported formatters: (case insensitive)

=over

=item B<yaml>

Stores data in YAML format.

=item B<yml>

Alias to the B<yaml> storage format.

=item B<json>

Stores data in json format.

=item B<raw>

Stores the data without any additional processing. If you pass data as an arrayref, ensure
that you include newline characters at the end of each line, if you care about having newlines.

=item B<data_archive>

Used by 'fetch' style scripts. This method allows for data to be gathered in one swoop,
and stored for individual check plugins to retrieve and use on their own. It will
gather and save data in a json hash keyed  by timestamp of the data gathering.

The behavior of this setting can be modified by customizing the following settings:

=over

=item B<delete_after>

Sets the retention policy for bulk data. B<store_bulk_data> will auto-delete datapoints
older than B<delete_after>. Defaults to 876400 (one day). This value is set in seconds.

=item B<on_previous_data_missing>

Sets the behavior of the message generated when the store file did not previously exist.
Possible values are 'warning', 'critical', 'unknown', and 'ok. Defaults to 'warning'. If
'ok' is specified, no message will be generated.

=back

=back

=back

=head2 retrieve

Retrieves the contents of a state file (see B<SAVING STATE>).

  my $seek = $plugin->retrieve("check_logs.seek");

The full path to the state file will be determined by the configuration
of the package; the check plugin does not need to know anything specific.

If the file does not exist, B<undef> will be returned, but no error
condition or problem will be triggered.

=head2 credentials

Extract a username and password from a secure credentials store.
Each set of credentials is associated with a unique key.  The store
is a single YAML file that must be readable by the uid runing the
check, and be chmod'ed 0400 (i.e. only readable, only by the owner).

  my ($user,$pass) = $plugin->credentials('database');

You can also pass in multiple credential keys, and the framework
will search for each key in order, returning the first match:

  my ($user,$pass) = $plugin->credentials('$host/db', 'mysqldb', 'db');

By default, check execution is halted immediately with an UNKNOWN
status if any of the following problems are encountered:

=over

=item 1. File does not exist

=item 2. File is not readable

=item 3. File does not contain a YAMLized hash

=item 4. None of the keys given exist in the YAML

=item 5. Value in YAML does not contain either username or password

=back

=head2 cred_keys($type, $hostname)

Generate a list of credstore keys, based on the $type and $hostname
given.  These keys will become increasingly more generic.  For example,
the following list will be generated for md01.atl.synacor.com, type POP:

=over 8

=item POP/md01.atl.synacor.com

=item POP/atl/md

=item POP/atl/*

=item POP/*/md

=item POP

=back

Alternatively, if you send an IP address to cred_keys, rather than hostname,
it will return back a list of keys like this:

=over 8

=item POP/10.10.10.10

=item POP

=back

This list can be passed to the B<credentials> function, activating its
susbsequent search mechanism for keys.

=head2 run

Dispatches commands based on how they were called. Depending on the value
of 'via', B<run> will dispatch to a supported transport mechanism. Transport
mechanisms must all conform to the following specifications:

=over

=item * Accepts minimally the command to run, and %opts hash

=item * Must support $opts{failok} to allow alert suppression ONLY when
the command executed has a non-zero return code.

=item * Must return output depending on context: list mode returns an array
of STDOUT that has been split on newlines; scalar mode returns all output
(with newlines), as a single string that ends with a newline character.

=item * All '\r\n' character sequences are replaced with simply '\n'.

=item * STDERR from commands must be forwarded to the STDERR of the executing
plugin.

=back

=head3 transport mechanisms

In default context (no 'via' option), commands are dispatched to run via
the shell (see B<_run_via_shell>). Alternatively, you can pass the string
'shell' to the 'via' option, and run commands via the shell.

  # run a regular command
  $plugin->run("ls /");

If 'via' is set to a Net::SSH::Perl object, the command will be executed
against that ssh session (see B<_run_via_ssh>).

  # run via ssh
  my $ssh = $plugin->ssh($host, $user, $pass);
  $plugin->run("ls /", via => $ssh);

No other 'via' mechanisms are currently supported aside from Net::SSH::Perl.

=head2 _run_via_shell

Run a command (or a command pipeline) and retrieve the output.  Some
internal sanity tests will be performed on the command to be runned.

Output will be returned as a list of lines (without the trailing '\n')
in list context, or a string containing newline-separated lines in
scalar context.  The scalar context string will also have a single
newline tacked onto the end.

  my $scalar = $plugin->run("echo 'test'");
  # value returned will be "test\n"

  my @list = $plugin->run("echo 'test'");
  # value returned will be ("test")

  my ($line) = $plugin->run("echo 'test'");
  # $line will be just 'test', without the newline.

Depending on how the command is given, the framework will perform
some sanity checks on it.  If the command is an absolute path to
an executable or script, the framework will check that the file
exists and is actually executable.  If these tests fail, the whole
check will be aborted as an UNKNOWN.

=head2 _run_via_ssh

Run a command (or commmand pipeline) and retrieve the output via an
ssh session.

Output will be returned as a list of lines (without the traiing '\n')
if called in list context, or a string containing newline-separated lines
in scalar context. This behavior is very similar to run_via_shell's behavior.

=head2 ssh($hostname, $user, $passwd, $opts)

Creates a Net::SSH::Perl object for use with the run($cmd, via => $obj)
function. Accepts hostname, username, password, and Net::SSH::Perl options.

Arguments:

=over

=item B<hostname>

This is the hostname to connect to. If port is specified as '<hostname>:<port>'
in this argument, it will override any port manually specified in the
$opts hashref passed to Net::SSH::Perl.

  # All three invocations have the same results:
  my $ssh = $plugin->ssh('myhost:21', $user, $pass. { port => 22 });
  my $ssh = $plugin->ssh('myhost:21', $user, $pass);
  my $ssh = $plugin->ssh('myhost', $user, $pass, { port => 21 });

=item B<user>

Username to initiate the ssh connection as. If left undefined, uses the
effective UID of the process.

=item B<passwd>

Password to provide when prompted for password based authentication. If using
key-based authentication, specify this as undefined.

=item B<opts>

This should be a hashref containing options which will be passed to
Net::SSH::Perl directly, as it's I<%opts> argument. Things you may
want to specify here are B<protocol>, B<identity_files>, B<use_pty>,
and B<options>.

There is one non-Net::SSH::Perl option that can be sepecified to affect
how B<ssh()> behaves. This is the B<failok> option, and it works like this:

Unless the 'failok' option is passed, this will add CRITs upon errors to
instantiate the ssh object, and on errors logging in.

If using an ssh key, use the appropriate ssh options for Net::SSH::Perl to pass
in the identity files to be used.

  # create new SSH object passing in port 22 to Net::SSH::Perl
  my $ssh = $plugin->ssh($hostname, $user, $pass, { port => 22 });

  # auto-determine port from hostname
  my $ssh = $plugin->ssh("myhost:22", $user, $pass, {});

  # don't bail on failures:
  my $ssh = $plugin->ssh('myhost:22', $user, $pass, { failok => 1 });

=back

=head2 last_run_exited

Returns the return code of the last command executed via run().
If no command has ever been run, that value will be undef. Otherwise,
it will be the return code reported by the run command.

If possible, the exit code will be translated based on exit type
(normal, signal, other), prior to returning a value.

=head2 last_run_exit_reason

Returns a string indicating the way the last command executed via run()
terminated. This will be one of "normal", "signaled", or "abnormal",
depending on whether the command exited normally, exited as a result of
a signal, or some other reason.

For remote commands, this data may not be available, and would appear
to return as a "normal" exit.

=head2 mech

This method is used to access the plugin's WWW::Mechanize object.
There will ony be one WWW::Mechanize object in use at a time. If
you need to generate a new one, specify the B<recreate> option in
your mech() call, anda new object will be created. If no
current mech exists, it will be created using the options passed
in.

  my $mech = $plugin->mech(
               recreate => 1,
               UA       => "my special User Agent",
               timeout  => 1);

Parameters:

=over

=item recreate

Force creation of a new WWW::Mechanize object.

=item UA

User Agent string to use when connecting to web servers.
Defaults to C<SynacorMonitoring/$Synacor::SynaMon::Plugin::VERSION>

=item timeout

Timeout for HTTP requests. If not specified, defaults to the plugin
timeout (-t flag to the check), or if that is not present, 15.

=back

=head2 http_request

Issue an HTTP request, using WWW::Mechanize.  This is the general
form of the function.  For most applications, specific aliases like
B<http_get>, B<http_post>, et al. are much more suitable.

If called in scalar context, returns a boolean value if the request
succeeded, but provides no other details.

In list context, B<http_request> returns the HTTP response object,
and the decoded content of the response:

  if ($plugin->http_request(get => $url)) {
    # request succeeded, do something else
  }

  my ($res, $data) = $plugin->http_request(get => $url);
  if ($res->is_success) {
    # now we can do something with the $data
  }

The following parameters can be specified, in order:

=over

=item $method

One of GET, PUT, or POST.

=item $url

=item $data

Data for a PUT / POST request.  This should be pre-encoded.

=item $headers

A hashref of additional headers to submit along with the request.

=item $options

Additional options, including username / password, timeout and
User-Agent string.

=back

=head2 http_get

Helper method for making HTTP GET requests using B<http_request>.
Accepts all of the parameters of B<http_request>, except for $data.

=head2 http_put

Helper method for making HTTP PUT requests.

=head2 http_post

Helper method for making HTTP POST requests.

=head2 submit_form

Helper method for form submission via WWW::Mechanize. Calls $mech->submit_form()
with all provided parameters.

=head2 json_decode

Decode JSON serialized data safely.  If an exception is thrown during
the decode operation, undef will be returned.  Otherwise, the
de-serialized object will be returned.

=head2 parse_bytes($str)

Parse a string representing a size (like '15M' or '67.8 kb'), and return the
number of bytes.

=head2 format_bytes($bytes, [$format])

Format a number of bytes into a more manageable, human readable format.  This
is the reverse operation of B<parse_bytes>.

=head2 parse_time($str)

Parse a string representing an amount of time (like '6m' or 3.5h') and return
the number of seconds.

=head2 format_time($seconds, [$format])

Format a number of seconds into a more manageable, human readable format.
This is the reverse operation of B<parse_time>.

=head2 jolokia_connect(%params)

Sets up the current plugin context for connecting to the specified Jolokia
proxy and target remote host.  The %params hash must contain the following
keys:

=over

=item B<creds>

Key for the credentials (as stored in the credentials store) for accessing
the Jolokia proxy service API.

=item B<host>

The FQDN or IP address of the target remote-JMX endpoint (i.e. B<not> the
Jolokia proxy itself).

=item B<port>

The TCP port of the target remote-JMX endpoint.

=back

Which Jolokia proxy is used is governed by the B<MONITOR_JOLOKIA_PROXY>
environment variable.  If that isn't set, the default literal value of
C<localhost:5080> will be used.

=head2 jolokia_request($request)

Requests data from the Jolokia proxy.  This is an internal method that
should only be called by Plugin::Base, not by plugins.

This method handles the JSON packing of the request payload, submission of
the request to the proper REST endpoint, and decoding of the result.

=head2 jolokia_read(@beans)

Reads MBean data for the named beans.  Data will be returned as a hashref,
with the following structure:

    {
       "{domain}:{mbean name}" => $value,
       ...
    }

It is an error to call B<jolokia_read> before calling B<jolokia_connect>,
and the plugin will bail out with an UNKNOWN.

=head2 jolokia_search($regex)

Search for MBeans whose names match the given Perl-compatible regular
expression.  An undefined $regex parameter is taken as a request for all
defined MBeans.

This function is aware of its calling context, and will return a list of
MBeans in list context, and a hashref in scalar context.  This allows the
following idiomatic practice:

    for my $bean (JOLOKIA_SEARCH(m/com.synacor./)) {
        # do something with the beans
    }

    # and

    my $data = JOLOKIA_READ( JOLOKIA_SEARCH( m/com.synacor./ ) );

It is an error to call B<jolokia_search> before calling B<jolokia_connect>,
and the plugin will bail out with an UNKNOWN.

=head2 sar($args, %opts)

Gather SAR data, either via sadf (if available) or sar -h (if not).  You can
set the number of samples you want; they will be averaged down into one
sample.

The B<$args> parameter should contain the arguments that sar needs to
extract and report the desired data.  For example, to see device throughput
statistics, use C<-d>, for network errors, use C<-n EDEV>.

The following options are supported:

=over

=item B<slice>

The number of seconds in a given timeslice.  Defaults to 60s.

=item B<samples>

The number of samples to take and average together.  Defaults to 1.

=back

=head2 devname(@devs)

Turns a series of device names (as returned from SAR) into their
corresponding filesystem paths, under /dev (based on major and minor
numbers).

Called in list mode, it will return a list of device paths.  In scalar mode,
returns only the first, which allows these usage parameters:

    my @devs = DEVNAME @lst;

    # and

    for (@lst) {
        my $dev = DEVNAME $_;
        # ...
    }

=head2 calculate_rate(%opts)

This function was added and tested to help transform data that is a counter,
ie an ever increase value into a gauge, ie a rate.

All parameters are in hash format, data and store are required parameters,
and the plugin will warn if they are not present.

=over

=item data

A key value set representing your current data values

=item store

The object store to get the last data set from

=item want

The data items you want to calculate over, can be an array or a single value

=item stale

The time staleness to warn over

=back

Usage:

my $calculated = calculate_rate(
	stale => 1800,
	store => "check_mAh_datah",
	want  => [ "data1", "data2" ],
	data  => {
		data1 => 300,
		data2 = 400,
		},
);

=head2 snmp_mib(@mib_names)

Compile and load an SNMP MIB into memory, so that it can be queried with utility functions
like B<oid> and B<oids>.  You must compile/load all the MIBs you need before you can call
other B<snmp_*> functions with OID arguments like '[sysName].0'

=head2 snmp_session($endpoint, \%options)

Connect to B<$endpoint> over SNMP.  The following options are supported:

=head2 snmp_session()

Returns the current Net::SNMP handle, instead of connecting.

=over

=item B<port>

The UDP port to connect to.  The default (B<161>) is usually correct.

=item B<version>

What SNMP version to speak with the endpoint.  Defaults to B<2c>.

=item B<community>

What community string to use when querying the endpoint.

=item B<timeout>

Timeout for communicating with the SNMP agent.  Defaults to B<5>.

=back

Currently, the SNMP implementation does B<not> support v3 / USM authentication.

=head2 snmp_get(@oids)

Retrieve one or more values from the SNMP endpoint.  @oids will be run through the
B<OIDS> function first, so you can use shortcut names like '[sysName].0' (assuming you
loaded the MIB beforehand).

You must call B<snmp_session> prior to calling this function.

=head2 snmp_tree($oid)

Retrieve an entire subtree of the OID hierarchy, starting at $oid.  The OID value will
be passed through the B<OID> function first, so you can use shortcut names like
'[sysLocation].0' (assuming you loaded the MIB beforehand).

You must call B<snmp_session> prior to calling this function.

=head2 snmp_table(@names)

=head2 snmp_table(\%map)

Retrieve an inter-related collection of OIDs, indexed properly in a Perl hash.  In the first
invocation, you pass in the bare shortcut names, like so:

    my $table = SNMP_TABLE(qw/ ifMtu ifSpeed /);
    for my $index (keys %$table) {
      printf "%s: %s/%s\n", $idx,
        $table->{$idx}{ifMtu},       # values are indexed by table index, and
        $table->{$idx}{ifSpeed};     # the short names given above
    }

In the second invocation, you can pass a single hashref that will do the mapping / rename
the way you desire:

    my $table = SNMP_TABLE({ mtu => '[ifMtu]', speed => '[ifSpeed]' });
    for my $index (keys %$table) {
      printf "%s: %s/%s\n", $idx,
        $table->{$idx}{mtu},       # values are indexed by table index, and
        $table->{$idx}{speed};     # the map keys (instead of the short names)
    }

You must call B<snmp_session> prior to calling this function.

=head2 snmp_enum($type, $numeric, [$format = "%s"])

Look up the display name for an enumerated value.  For example, the enum value 1, of
type ifAdminStatus, is "up".  The optional B<$format> parameter will be interpreted as
a printf-style format string.  The format specifier B<%s> will be replaced with the
display name, and B<%i> will be replaced with the numeric value.

=head2 snmp_tc($type, $numeric, [$format = "%s"])

Look up the display name for a textual convention.  For example, the TC value 6, of
type IANAifType, is "ethernetCsmacd".  The optional B<$format> parameter will be
interpreted as a printf-style format string.  The format specifier B<%s> will be
replaced with the display name, and B<%i> will be replaced with the numeric value.

=head2 oid($name)

With B<oid()>, you can refer to the long OID strings (1.3.6.1.2.1...) by the short names
that are defined in their MIB, assuming you compiled/loaded that mib with B<SNMP_MIB> first.

This makes code interacting with SNMP agents easier to read, since the numbers are looked up
at runtime and the names are all that you have to deal with.

Compare:

    SNMP_GET '[sysContact].0';         # OID() is called implicitly

and

    SNMP_GET '1.3.6.1.2.1.1.4.0';

The MIB definitions clearly state the B<sysContact> is the 1.3.6.1.2.1.1.4 subtree, but being
able to read that directly in the code is well worth it.

B<OID()> will only expand shortcut names that are surrounded with square brackets.  This means
that you can pass raw OIDs (i.e. if you got them as a value from a previous query, or you
really I<like> number strings) and they will be passed back untouched.

=head2 oids(@names)

Call OID() on all of its arguments, returning the result as a list.

=head2 rrd($command, $file, @args)

Allows you to run arbitrary RRD commands through RRDp, with built-in error
handling/alerting. Can be used for retrieving or updating RRDs directly, though
this should not be used to replace the traditional perfdata gathering mechanisms,
rather to provide introspection on the historical RRD data gathered.

Arguments:

=over

=item B<$command>

Determines the rrdtool command to be run. Should be a command that rrdtool supports
(I<fetch>, I<info>, I<update>, ...).

=item B<$file>

RRD File to manipulate. For ease of use, it detects relative paths (anything not
starting with '/'), and prepends the B<rrds> setting to the path. Any RRD
name not ending in '.rrd' will also have it appended.

=item B<@args>

Additional arguments to pass to rrdtool (must be passed similarly to exec @args),
each flag + option must be its own item in the array.

=back

=head1 AUTHOR

James Hunt, C<< <jhunt at synacor.com> >>

=cut
