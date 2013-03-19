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
use POSIX qw/
	WEXITSTATUS WTERMSIG WIFEXITED WIFSIGNALED
	SIGALRM
	sigaction
/;
use Time::HiRes qw(gettimeofday);
$Data::Dumper::Pad = "DEBUG> ";

use constant NAGIOS_OK       => 0;
use constant NAGIOS_WARNING  => 1;
use constant NAGIOS_CRITICAL => 2;
use constant NAGIOS_UNKNOWN  => 3;

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

sub new
{
	my ($class, %options) = @_;

	$ALL_DONE = 0;
	my $bin = do{my $n=$0;$n=~s|.*/||;$n};

	# Play nice with Nagios::Plugin
	$options{shortname} = uc($options{name} || $bin);
	delete $options{name};

	if (exists $options{summary}) {
		$options{blurb} = $options{summary};
		delete $options{summary};
	}

	$options{usage} = "$options{shortname} [OPTIONS]";

	my $self = {
		messages => {
			NAGIOS_OK       => [],
			NAGIOS_WARNING  => [],
			NAGIOS_CRITICAL => [],
			NAGIOS_UNKNOWN  => [],
		},
		name => $bin,
		bin  => $bin, # name may change drop the 'check_' prefix...
		usage_list => [],
		did_stuff => 0, # ticked for every STATUS message
		options => {},
		pids => [],
		settings => {
			ignore_credstore_failures => 0,
			on_timeout => NAGIOS_CRITICAL,
			signals => 'perl',
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

	bless($self, $class);
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

		if ($key eq 'on_timeout') {
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
	my ($self, $label, $value, @data) = @_;
	$self->{legacy}->add_perfdata(
		label => $label,
		value => $value,
		@data);
}

sub _reformat_hash_option
{
	my @instances = @_;
	my %opt = ();
	my $allowed_keys = '(warn|crit|perf)';

	foreach my $instance (@instances) {
		my ($name, $rest) = split(/:/, $instance, 2);
		my $values = { warn => undef, crit => undef, perf => 1};
		my @vals = split(/,/, $rest);
		foreach my $val (@vals) {
			my ($key, $value) = split(/=/, $val);
			return "$name:$val\nSub-option keys must be one of '$allowed_keys'."
				unless $key =~ /^$allowed_keys$/;
			if ($key eq 'perf') {
				if (defined $value && ($value eq '0' || $value eq 'no')) {
					$value = 0;
				} else {
					$value = 1;
				}
			}
			$values->{$key} = $value;
		}
		$opt{$name} = $values;
	}
	return \%opt;
}
sub getopts
{
	my ($self) = @_;
	$self->option("debug|D",
		usage => "--debug, -D",
		help  => "Turn on debug mode"
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
	$self->{did_stuff}++;
	my ($code, $name);
	if (defined $status && defined $STATUS_CODES{$status} && defined $STATUS_NAMES{$status}) {
		($code, $name) = ($STATUS_CODES{$status}, $STATUS_NAMES{$status});
	} else {
		($code, $name) = ($STATUS_CODES{"UNKNOWN"}, $STATUS_NAMES{"UNKNOWN"});
	}

	$status = "undef" unless defined $status;

	my $msg = join('', @message);
	$self->debug("Adding $name ($code) from [$status] message: $msg");

	push @{$self->{messages}{$code}}, $msg;
	if ($code == NAGIOS_UNKNOWN) {
		$ALL_DONE = 1;
		$self->{legacy}->nagios_exit(NAGIOS_UNKNOWN, $msg);
	} else {
		$self->{legacy}->add_message($code, $msg);
	}

	return $code, $msg;
}

sub bail
{
	my ($self, $status, $message) = @_;
	$ALL_DONE = 1;
	if (! defined $message) {
		$message = $status unless defined $message;
	}
	my $code = $STATUS_CODES{$status} || $STATUS_CODES{"UNKNOWN"};
	$self->debug("Bailing $status ($code) from message: $message");
	$self->{legacy}->nagios_exit($code, $message);
}

sub evaluate
{
	my ($self, $status, @message) = @_;
	$self->{did_stuff}++;
	if ( defined $status && defined $STATUS_NAMES{$status} && defined $STATUS_CODES{$status} ) {
		return if $STATUS_CODES{$status} == NAGIOS_OK;
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

	$self->{debug} = $self->option->debug;
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
	if (!$self->{did_stuff}) {
		$self->UNKNOWN("Check appears to be broken; no problems triggered");
	}
	$self->{legacy}->nagios_exit($self->{legacy}->check_messages);
}

sub done
{
	my ($self) = @_;
	$self->finalize("DONE call") unless $self->mode eq 'feeder';
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

sub debug
{
	my ($self, @messages) = @_;
	return unless $self->{debug};
	for (@messages) {
		$_ = (defined($_) ? $_: "undef");
		s/\n+$//;
		print STDERR "DEBUG> $_\n";
	}
	print STDERR "\n";
}

sub dump
{
	my ($self, @vars) = @_;
	return unless $self->{debug};
	print STDERR Dumper(@vars);
	print STDERR "\n";
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
	my ($self, $path) = @_;
	my $dir    = $ENV{MONITOR_STATE_FILE_DIR}    || "/var/tmp";
	my $prefix = $ENV{MONITOR_STATE_FILE_PREFIX} || "mon";
	$path =~ s|.*/||;
	"$dir/${prefix}_$path";
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

	$path = $self->state_file_path($path);

	open my $fh, ">", $path or
		$self->bail(NAGIOS_UNKNOWN, "Could not open '$path' for writing");

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
		$data = join('', @$data);
	}
	print $fh $data;
	close $fh;

	my (undef, undef, $uid, $gid) = getpwnam($ENV{MONITOR_STATE_FILE_OWNER} || 'nagios');
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
	$path = $self->state_file_path($path);

	if ($options{touch} && -e $path) {
		utime(undef, undef, $path);
	}

	$self->debug("Using '$path' for retrieval");

	open my $fh, "<", $path or do {
		$self->debug("FAILED to open '$path' for reading: $!");
		return undef;
	};

	my @lines = <$fh>;
	close $fh;

	if ($options{as} && $options{as} !~ m/^raw$/i) {
		my $data = join('', @lines);
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
	wantarray ? @lines : join('', @lines);
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
	"/usr/local/groundwork/users/nagios/.creds"; # evil default
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
	$hostname =~ m/^([a-z]+)[^\.]*\.(.*)/;
	my ($role, $cluster) = ($1, $2);
	$cluster =~ s/\.synacor\.com$//;

	return (
		"$type/$hostname",       # host-specific
		"$type/$cluster/$role",  # cluster / role specific
		"$type/$cluster/*",      # cluster-global
		"$type/*/$role",         # role-global
		$type,                   # ...
	);
}

sub run
{
	my ($self, $command, %opts) = @_;
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
	$method = uc($method);
	$headers = $headers || {};
	$options = $options || {};

	$self->debug("Making HTTP Request: $method $uri");
	$self->dump($data) if $method eq "POST";

	my $request = HTTP::Request->new($method => $uri);
	for my $h (keys %$headers) {
		$self->debug("   '$h: $headers->{$h}'");
		$request->header($h, $headers->{$h});
	}
	if (($method eq "POST" || $method eq "PUT") and $data) {
		$request->content($data);
	}

	if (exists $options->{username} && exists $options->{password}) {
		$request->authorization_basic($options->{username}, $options->{password});
	};

	my $response = $self->mech->request($request);
	return wantarray ?
		($response, $response->decoded_content) :
		$response->is_success;
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
	if ($data =~ /^[^\(]*\((.*)\)$/) { # JSONP
		$data = $1;
	}
	eval { $obj = JSON->new->allow_nonref->decode($data); }
}

"YAY!";

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
defaults to true, and B<warn>/B<crit> default to undefined values. B<keyN> values
can be any you desire, and will be used as keys in the hashref returned when this option
is called in B<Retrieve> mode. Subsequent calls of B<--parameter_name> would result
in additional keys being added to the hashref to be returned by this option.

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

This list can be passed to the B<credentials> function, activating its
susbsequent search mechanism for keys.

=back

=head2 run

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

=head1 AUTHOR

James Hunt, C<< <jhunt at synacor.com> >>

=cut
