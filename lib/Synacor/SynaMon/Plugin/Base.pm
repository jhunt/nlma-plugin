package Synacor::SynaMon::Plugin::Base;

use warnings;
use strict;

use Nagios::Plugin qw();
use base qw(Nagios::Plugin);

use YAML::XS qw(LoadFile);
use JSON;
use Data::Dumper qw(Dumper);
use LWP::UserAgent;
use POSIX qw(WEXITSTATUS WTERMSIG WIFEXITED WIFSIGNALED);
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
		usage_list => [],
		did_stuff => 0, # ticked for every STATUS message
		options => {},
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

sub _spec2usage
{
	my ($usage, $required) = @_;
	return unless $required;

	$usage =~ s/,\s+/|/;
	$usage;
}

sub option
{
	my ($self, $spec, %opts) = @_;
	if ($spec) {
		if ($spec eq "timeout|t=i") {
			$self->{legacy}{opts}{timeout} = $opts{default} if $opts{default};
			return;
		}
		if (exists $opts{usage}) {
			push @{$self->{usage_list}}, _spec2usage($opts{usage}, $opts{required});

			$opts{help} = $opts{usage} . (exists $opts{help} ? "\n   " . $opts{help} : "");
			if (exists $opts{default}) {
				$opts{help} .= " (default: $opts{default})";
			}
			delete $opts{usage};
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
	open STDERR, ">&", \*OLDERR;
}

sub status
{
	my ($self, $status, @message) = @_;
	$self->{did_stuff}++;
	my ($code, $name) = ($STATUS_CODES{$status}, $STATUS_NAMES{$status});

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
	$status = $STATUS_CODES{$status};
	$self->{legacy}->nagios_exit($status, $message);
}

sub evaluate
{
	my ($self, $status, @message) = @_;
	return unless defined $status;
	my $code = $STATUS_CODES{$status};

	return unless defined $code;
	$self->{did_stuff}++;
	return if $code == NAGIOS_OK;

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
	$self->debug("Starting plugin execution");

	if (exists $opts{default}) {
		$self->debug("Setting default OK message");
		$self->OK($opts{default});
	}

	$self->start_timeout($self->option->{timeout}, $TIMEOUT_STAGE);
}

sub done
{
	my ($self) = @_;
	$ALL_DONE = 1;
	if (!$self->{did_stuff}) {
		$self->UNKNOWN("Check appears to be broken; no problems triggered");
	}
	$self->{legacy}->nagios_exit($self->{legacy}->check_messages);
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

	alarm $seconds;
	$SIG{ALRM} = sub {
		print "$TIMEOUT_MESSAGE: $TIMEOUT_STAGE\n";
		$ALL_DONE = 1;
		exit NAGIOS_CRITICAL;
	};

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

	$path = $self->state_file_path($path);

	open my $fh, ">", $path or
		$self->bail(NAGIOS_UNKNOWN, "Could not open '$path' for writing");

	if ($options{as} && $options{as} !~ m/^raw$/i) {
		if ($options{as} =~ m/^ya?ml$/i) {
			$data = YAML::XS::Dump $data;
		} elsif ($options{as} =~ m/^json$/i) {
			eval { $data = JSON->new->allow_nonref->encode($data); };
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

sub retrieve
{
	my ($self, $path, %options) = @_;
	$path = $self->state_file_path($path);

	if ($options{touch} && -e $path) {
		utime(undef, undef, $path);
	}

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

sub credentials
{
	my ($self, $name, $fail_silently) = @_;

	my $filename = $ENV{MONITOR_CRED_STORE} || "/usr/local/groundwork/users/nagios/.creds";
	$self->debug("Retrieving '$name' credentials from $filename");

	unless (-f $filename) {
		return undef if $fail_silently;
		$self->bail(NAGIOS_UNKNOWN, "Could not find credentials file");
	}

	unless (-r $filename) {
		return undef if $fail_silently;
		$self->bail(NAGIOS_UNKNOWN, "Could not read credentials file");
	}

	my @stat = stat($filename);
	if (!$fail_silently && (!@stat || ($stat[2] & 07777) != 0400)) {
		$self->bail(NAGIOS_UNKNOWN, sprintf("Insecure credentials file; mode is %04o (not 0400)",
				$stat[2] & 07777));
	}

	my $yaml = LoadFile($filename);
	unless (ref($yaml) eq "HASH") {
		return undef if $fail_silently;
		$self->bail(NAGIOS_UNKNOWN, "Corrupted credentials file");
	}

	unless (exists $yaml->{$name}) {
		return undef if $fail_silently;
		$self->bail(NAGIOS_UNKNOWN, "Credentials key '$name' not found");
	}

	unless ($yaml->{$name}{username} || $yaml->{$name}{password}) {
		return undef if $fail_silently;
		$self->bail(NAGIOS_UNKNOWN, "Corrupt credentials key '$name'");
	}

	return ($yaml->{$name}{username}, $yaml->{$name}{password});
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

	open my $pipe, "$command|";
	if (!$pipe) {
		$self->bail(NAGIOS_UNKNOWN, "Failed to run $bin");
	}

	my @lines = <$pipe>;
	close $pipe;
	my $rc = $?;

	if ($rc != 0 && !$opts{failok}) { # caller expects command to exit 0
		# handle normal exit, signal death or unknown properly
		if (WIFEXITED($rc)) {
			$rc = WEXITSTATUS($rc);
			$self->CRITICAL("Command $safe exited $rc");
		} elsif (WIFSIGNALED($rc)) {
			$rc = WTERMSIG($rc);
			$self->CRITICAL("Command $safe killed with signal $rc");
		} else {
			$rc = sprintf("0x%04x", $rc);
			$self->CRITICAL("Command $safe terminated abnormally ($rc)");
		}
	}

	return wantarray ? (map { chomp; $_ } @lines) : join('', @lines);
}

sub http_request
{
	my ($self, $method, $uri, $data, $headers, $options) = @_;
	$method = uc($method);
	$headers = $headers || {};
	$options = $options || {};

	$self->debug("Making HTTP Request: $method $uri");
	$self->dump($data) if $method eq "POST";

	my $ua = LWP::UserAgent->new;
	$ua->agent($options->{UA} || "SynacorMonitoring/$Synacor::SynaMon::Plugin::VERSION");
	$ua->timeout($options->{timeout} || $self->option->{timeout} || 15);

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

	my $response = $ua->request($request);
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

=head2 option

Define a command-line argument for the check script.

  $plugin->option('dbname|n=s',
    usage => "--dbname, -n <table name>",
    help  => "Name of the database to connect to",
    required => 1
  );

The first argument is the GetOpt-style argument spec.

The remainder of the arguments represent contraints and extra information
about this option.  The following keys are valid:

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

B<option> also gives you access to the passed values, as a hash
reference, when called with no arguments:

  if ($plugin->option->mode == "mysql") {
    # do stuff specific to MySQL...
  }

=head2 track_value

Track performance and trending data.

=head2 getopts

Process command-line options, populating the plugin object.

=head2 status

Trigger a check status, with an optional status message:

  $plugin->status(NAGIOS_WARN, "Warning!  Bad things about to happen");

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

Finalize plugin execution, and exit with the appropriate return code
and status message, formatted for Nagios.

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

=head2 state_file_path

Generate the absolute path to a state file, based on package configuration,
environment variables and a path fragment.

For example:

  my $state = $plugin->state_file_path("save.state");

May generate a file path like I</var/tmp/mon_save.state>.

=head2 store

Stores a value in a state file.

  $plugin->store("check_logs.seek", $seek_pos);

The created state file will be modified so that its permissions are correct
and its uid/gid ownership is sane.

If the store operation cannot be carried out, either because of permissions
or intervening directories, the framework will trigger an UNKNOWN problem with
a suitable message for debugging.

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

By default, check execution is halted immediately with an UNKNOWN
status if any of the following problems are encountered:

=over

=item 1. File does not exist

=item 2. File is not readable

=item 3. File does not contain a YAMLized hash

=item 4. Specified key does not exist in YAML

=item 5. Value in YAML does not contain either username or password

=back

You can pass in a second argument to avoid this and instead return
undef:

  my ($user,$pass) = $plugin->credentials("$host-ldap", 'silent');
  if (!$user) {
    ($user, $pass) = $plugin->credentials('DEFAULT-ldap');
  }

In this example, the check looks for credentials specific to this
$host, and if that fails, looks for the defaults.  Since the second
call does not specify the I<fail silently> argument, the plugin
will either retrieve credentials or trigger an UNKNOWN.

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

=head2 http_request

Issue an HTTP request, using LWP::UserAgent.  This is the general
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

=head2 json_decode

Decode JSON serialized data safely.  If an exception is thrown during
the decode operation, undef will be returned.  Otherwise, the
de-serialized object will be returned.

=head1 AUTHOR

James Hunt, C<< <jhunt at synacor.com> >>

=cut
