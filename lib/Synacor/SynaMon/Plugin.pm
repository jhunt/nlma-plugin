package Synacor::SynaMon::Plugin;

use strict;
use warnings;
use Synacor::SynaMon::Plugin::Base;

our $VERSION = "1.32";

use Exporter;
use base qw(Exporter);

our $MODE = 'plugin';

sub import {
	my $class = shift;

	warnings->import;
	strict->import;

	my %tags = map { $_ => 1 } @_;
	if (exists $tags{':feeder'}) {
		delete $tags{':feeder'};
		$MODE = "feeder";

		use Synacor::SynaMon::Plugin::Feeders;
		Synacor::SynaMon::Plugin::Feeders->export_to_level(1);

		use Synacor::SynaMon::Plugin::Easy;
		Synacor::SynaMon::Plugin::Easy->export_to_level(1);

	} elsif (exists $tags{':easy'}) {
		delete $tags{':easy'};
		$MODE = "plugin";

		use Synacor::SynaMon::Plugin::Easy;
		Synacor::SynaMon::Plugin::Easy->export_to_level(1);
	}

	my @vcheck = grep { $_ =~ m/^\d+(.\d+)?$/ } @_;
	my $v = pop @vcheck;
	if ($v && $VERSION+0 < $v) {
		print "UNKNOWN - Incorrect framework version $v+ (installed: $VERSION)\n";
		exit 3;
	}
}

1;

=head1 NAME

Synacor::SynaMon::Plugin - Check Plugin Framework

=head1 DESCRIPTION

Almost all check plugins (at least the ones worth writing) do a lot of the same
things for set up, teardown and status reporting.  Rather than force check writers
to constantly re-invent or re-discover these idioms, B<Synacor::SynaMon::Plugin>
abstracts these common idioms away.

By using the framework, check writers can get working monitoring checks faster
with less effort, without sacrificing supportability, clarity or robustness.

All check plugins should include B<Synacor::SynaMon::Plugin> to get access
to the framework.

To access the OO interface:

  #!/usr/bin/perl
  use Synacor::SynaMon::Plugin;

To use the procedural (B<easy>) interface:

  #!/usr/bin/perl
  use Synacor::SynaMon::Plugin qw(:easy);

=head1 VERSIONING

The plugin framework will be backwards compatible at all costs.

If you want to make sure that you get the correct version of the framework, i.e.
so you can use a function that was added in a later release, add the minimum
required version number to the list of things to import in your 'use' call.

For example, to require framework version 1.56 or later:

  #!/usr/bin/perl
  use Synacor::SynaMon::Plugin qw(:easy 1.56)

This documentation should define, for each function, what version of the framework
that function first appeared in.

=head1 DEPRECATION OF FEATURES

Sometimes, we just can't help it, and we make mistakes in designing APIs and
implementing functionality.  For that reason, and to avoid headache and unnecessary
breakage, the framework features a system of deprecating features.

If you use a deprecated feature or behavior, the framework will (by default) print
a deprecation notice to standard error, like this one:

    DEPRECATION NOTICE: The FOOBAR feature is deprecated as of v1.25

The plugin will then soldier on, doing what you asked it to.

If you are a plugin developer, and want to make sure that your plugin doesn't rely
on deprecated features, you can set the B<MONITOR_FAIL_ON_DEPRECATION> environment
variable.  At that point, plugins will bail when they trigger deprecation notices.

For a list of things that have been deprecated, and when, see the section
B<DEPRECATED FEATURES LIST>, at the end of this document.

=head1 AN EXAMPLE PLUGIN

To get started, let's look at an example plugin that checks the age of a file:

  #!/usr/bin/perl
  use Synacor::SynaMon::Plugin qw(:easy)

  PLUGIN name => 'check_file_age';

  OPTION "file|f=s",
    usage    => "--file, -f /path/to/file",
    help     => "Path to the file to monitor",
    required => 1;

  START;

  my $file = OPTION->file;

  if (!-f $file) {
    BAIL CRITICAL("File '$file' not found");
  }

  # stat() the file and get the mtime (field 9)
  my @stat = stat $file;
  if (!@stat) {
    BAIL CRITICAL("stat($file) failed: $!");
  }

  CHECK_VALUE $age, "$file is ${age}s old",
              warning  => 1800,
              critical => 3600;
  TRACK_VALUE "age" => $age;

  DONE;

This check plugin is pretty straightforward; given the path to a file
(specified by the -f option), see how long ago it was last modified,
and issue either a warning, critical or ok as appropriate.

We'll get into the specifics later, the most important thing to take
away from this example is that the framework should let you do what you
need to and stay out of the way as much as possible.  While this
check could use a bit more flexibility (the thresholds are hard-coded),
it is a completely serviceable check, that even tracks performance
trending data for graphing purposes!

The following sections introduce and illustrate the different functions
that the framework provides, what they do, and how to use them.  They
are grouped based on their purpose.

For developers who wish to understand the framework at a lower level,
take a look at B<Synacor::SynaMon::Plugin::Base> and
B<Synacor::SynaMon::Plugin::Easy>.

=head1 PLUGIN SETUP AND OPTIONS

The preamble of every check plugin has to do three things, in order:

=over

=item 1. Identify the plugin

=item 2. Define command-line arguments

=item 3. Start execution

=back

=head2 PLUGIN

Available since framework version 1.0.

The B<PLUGIN> function identifies the check plugin and sets up some
basic information that the framework needs about it, including its
name and a summary of what it does.

  PLUGIN name    => "check_something",
         summary => "Monitor that Something is going on"
         version => "1.0"

B<PLUGIN> understands the following options:

=over

=item name

The name of the plugin, if different from the script name.

=item version

=item summary

A short description of what the plugin checks, e.g.
"Monitor A RESTful HTTP web service"

=back

=head2 OPTION

Available since framework version 1.0.
('B<=%>' style specs have been available to OPTION since version 1.16)

To make check plugins more flexible, you can set up command-line
arguments and flags to defer configuration until the plugin is run.

  OPTION "debug|D",
    usage => "--debug, -D",
    help  => "Enables check plugin debugging statements"

  OPTION "environment|e=s",
    usage => "--environment, -e (prod|preprod|dev)",
    help  => "What environment to run against",
    default => "dev"

Here we have defined two command-line options, one to enable debug
messages and the other to specify an environment to run against.

The first argument to an B<OPTION> call should be the option spec,
a string in GetOpt style format ("<long>|<short>[=<type>]").  For flags that
are either on or off (like --debug), the "=<type>" part should be
omitted.  For arguments, the B<<type>> identifies the type of data to
be expected with that argument. Valid type values are anything GetOpt
supports, with the addition of '=%', which will enable an array of
calls to the argument, which then get processed into a hashref for specifying
multiple thresholds inside the plugin.

Given the following specs:

   warning|w=s
   debug
   check|c=%

And the following check arguments:

   -w 5 --debug --check 'cpu:warn=10,crit=20', \
   --check 'io_in:warn=:10,crit=20:,perf=asdf' \
   -C 'io_out:warn=10,crit=20:30,perf=0' \
   -C 'mem:warn=10,crit=~:20,perf=no' \
   -C 'perf:warn,crit,perf'

You can access the B<option>s like so:

   OPTION->warning;  # Returns '5'
   OPTION->debug;    # Returns 1 (true)
   OPTION->check;    # Returns hashref of below syntax
   # {
   #  cpu    => { warn => '10',  crit => '2',     perf => 'cpu' },  # default
   #  io_in  => { warn => '10',  crit => '20',    perf => 'asdf' }, # perf=asdf
   #  io_out => { warn => '10',  crit => '20:30', perf => '0' },    # perf=no
   #  mem    => { warn => '10',  crit => '~:20',  perf => '0' },    # perf=0
   #  perf   => { warn => undef, crit => undef,   perf => 'perf' }, # perf
   # }

Remaining arguments either provide more information about the option,
or influence its behavior.

=over

=item usage

A general example of how the argument should be specified.  This will
show up in the usage text printed by B<--help>.  For options that take
values (like --environment, above), it is best practice to either list
the possible values, or describe the general nature of the option
value (e.g. "--file /path/to/file" or "--interval <SECONDS>").

=item help

A brief explanation of what the option is used for.  This will also
show up in the --help usage text.

=item default

Supply a default value for the option.

=item required

If true, the option must be specified when the plugin is run, or an
error will result.

=back

Later, during execution, we can call B<OPTION> with no arguments to
get a hash containing all defined options, and their final values.

=head2 START

Once all the options are defined, the B<START> function should be
called to kick off plugin execution.  This is where command-line
arguments get processed.

=head1 SETTINGS

The framework exists to make the life of a plugin writer easier.
To that end, it relies on a set of conventions that hold for 95% of
all plugins.  For example, it always assumes that if a timeout occurs,
that should be treated as a critical problem.

Sometimes, however, plugin writers need to bend the system and do
things in unconventional manners.  For example, for some situations,
timeouts may be too frequent to be treated as critical problems, and
should be dealt with as warnings instead.

B<SET> to the rescue!  B<SET> is a way to reach into the inner workings
of the framework and re-tune / re-focus its behavior.

To implement the timeout-as-a-warning example:

  SET on_timeout => "warn";

Here is a list of settings, their legal values, and what they do:

=over 8

=item B<ignore_credstore_failures>

If set to a non-zero value, issues encountered while retrieving
credentials are ignored.  If the error is recoverable (e.g. insecure
file permissions) it will be ignored outright.  For 'fatal' errors,
(e.g. not finding the key you asked for), B<undef> will be returned.

=item B<on_timeout>

What type of problem to trigger when a timeout occurs.  Valid values
are B<warn>, B<critical>, and B<unknown>.  The default is B<critical>.

=item B<signals>

How to install signal handlers for things like timeout (SIGALRM).  Valid
values are B<posix> and (the default) B<perl>.  For B<posix>, POSIX::SigAction
will be used.  Otherwise, the Perl %SIG hash is used.

=item B<on_previous_data_missing>

Determines what status level alarm should be generated if no previous data
was found for a given STORE($path, $obj, as => 'data_archive') call. Similar to
B<on_timeout>, this accepts values of B<warn>, B<critical>, B<unknown>, and B<ok>.
The default is B<warn>. If B<ok> is specified, no message will be generated for
cases where the previous datafile was missing.

This datapoint only affects the B<data_archive> B<STORE AND RETREIVE FORMATS>.

See B<FETCH SCRIPTS> and B<STORE AND RETRIEVE FORMATS> or more information.

=item B<delete_after>

Affects how long data is retained for in STORE($path, $Obj, as => 'data_archive') call.
This defaults to 86400 seconds (24 hours).

This datapoint only affects the B<data_archive> B<STORE AND RETREIVE FORMATS>.

See B<FETCH SCRIPTS> and B<STORE AND RETRIEVE FORMATS> or more information.

=item B<ignore_jolokia_failures>

Normally, when the JOLOKIA_* methods are called, they will BAIL at the first
sign of trouble.  Often, this is exactly what we want; if we get a bad
request from the Jolokia proxy, chances are we can't continue, and should
alert someone that something is wrong.  When it isn't what you want, flip
this on and you'll get empty results from failed Jolokia/JMX operations.

=item B<ssl_verify>

Turn on or off, SSL certificate checking by setting the appropriate LWP
environment viariable. Certificate checking is accomplished by verify
that a cert is not self signed, and the cert name matches the hostname.
As of version 1.29 SSL hostname verifaction is off by default, and
must be explicitly turned on.

=back

B<SET> has been available since version 1.10

=head1 TRIGGERING PROBLEMS

Check plugins are supposed to trigger problems based on what they find.  A CPU
check, for example, may need to trigger either a WARNING or a CRITICAL problem
if CPU usage is above or below specific thresholds.  An LDAP check may want
to trigger a CRITICAL problem if it can't connect to the directory server.

Sometimes, checks just want to report something useful, but not cause any alerts.
The CPU check from above may want to report current usage, regardless of whether
or not it falls within normal operational parameters.

In the plugin framework, this is done via the B<OK>, B<WARNING>, B<CRITICAL>
and B<UNKNOWN> methods.  Each of these methods takes a single argument; a message
to be associated with the problem.

Here are a few examples:

  # Check connection to a web server
  if (connect_to($web_server, port => 80)) {
    OK("Connected to $web_server on port 80");

  } else {
    CRITICAL("Could not connect to $web_server on port 80");
  }

These methods can be called any number of times during a single check run:

  my $file = "/var/lock/test.file"
  WARNING("$file is empty")         unless -s $file;

  my $perms = lookup_mode($file);
  WARNING("$file has mode $perms")  unless $perms =~ "0\d\d0";

  CRITICAL("$file is not readable") unless -r $file;
  OK("$file looks good");

This example triggers warnings and criticals depending on the characteristics
of the file being checked.  If the file is empty, and not readable, both a
warning and a critical problem have been identified.

To illustrate how the framework handles multiple problem states, consider
an even simpler code snippet:

  WARNING("first warning");
  WARNING("and another warning");

  CRITICAL("oh no");
  CRITICAL("its really broken");

At the end plugin execution, the framework analyzes all triggered problems,
chooses the most severe, and combines those messages into one.  In this
example, the plugin will exit CRITICAL, with a status message of
"oh no.  its really broken".
example, if the file is empty and not readable, the plugin will print out

The hierarchy of problem types, from most severe to least, is:

=over

=item UNKNOWN

=item CRITICAL

=item WARNING

=item OK

=back

A single status message can only be up to 500 characters long.  Overall, the
total number of characters that any plugin will output is limited to around 4000.
These limits are set to protect other parts of the monitoring system, and are
high enough to accommodate normal, sane usage.

UNKNOWN, CRITICAL, WARNING and OK have been available since version 1.0.

=head1 RUNNING EXTERNAL COMMANDS

Sometimes a check plugin needs to use an outside command to perform its validation.
For that, we have provided RUN(). In the most basic use, RUN() will take a command
argument, and options to determine how it is run. RUN returns the output of a command
either in scalar or list context. Return codes are automatically checked, and STDERR
is forwarded to the check plugin's STDERR to be caught by the calling program.

One of RUN()'s options is the 'via' option, which lets the caller run commands over
different transport mechanisms. If no 'via' option is specified, it defaults to running
locally via a shell. The following transport mechanisms are currently supported:

=over

=item shell

The default transport mechanism is to run via a local shell. You may omit the
'via' option to RUN to run via a local shell, or you may explicitly pass in the
string 'shell' for the same results.

  # Run a command locally in list context
  my @output = RUN("ls -1");
  # Returns: ('myfile', 'myfile2', 'myfile3')

  # Run a command locally in scalar context
  my $output = RUN("ls -1");
  # Returns: 'myfile\nmyfile1\nmyfile3\n'

  # Run command in shell specifying 'via'
  my $output = RUN("ls -l", via => 'shell');
  # Returns: 'myfile\nmyfile1\nmyfile3\n'

RUN will fail in shell mode under the following circumstances:

=over

=item * If the command does not exist as a file, or is not executable

=item * If the command could not be run

=item * If the command exited non-zero (through normal operations, a kill signal, oranabnormal exit)

=back

=item Net::SSH::Perl

Provide a Net::SSH::Perl object to 'via' when calling RUN to execute the command
over the SSH session. Takes hostname, username, password, and a hashref of ssh_options
to be passed to Net::SSH::Perl.

NOTE: If the port is specified in the hostname parameter, it will override any value
set in the ssh_options parameter.

  # Run a command via an ssh session in list context
  my $ssh = SSH($host, $user, $pass, { ssh_option => 'ssh_opt_value' });
  my @output = RUN("ls -1", via => $ssh);
  # Returns: ('remotefile', 'remotefile2', 'remotefile3')

  # Run a command via an ssh session in scalar context
  my $output = RUN("ls -1", via => $ssh);
  # Returns 'remotefile\nremotefile2\nremotefile3\n'

NOTE: Net::SSH::Perl doesn't support running commands on the same channel, ie:
you will need to chain your commands in the run call.

  # Chain commands
  my $ssh = SSH($host, $user, $pass, { ssh_option => 'ssh_opt_value' });
  my @output = RUN("sudo su thanks ; /bin/win_an_emmy", via => $ssh);

RUN will fail in Net::SSH::Perl mode under the following circumstances:

=over

=item * If the command could not be run on the remote host

=item * If the command exited non-zero when run on the remote host

=back

=back

RUN($cmd, via => $obj) has been available since version 1.22.
Net::SSH::Perl support for RUN has been available since version 1.22.

=head2 LAST_RUN_EXITED

If you are using RUN in combination with 'failok', to suppress the built-in
return code checking, you may at some point want to manually look at the return
code ofthe command executed via RUN (for example, you want to run B<test -f myfile>
and ensure that it returns 1). The LAST_RUN_EXITED call will return this value to you.
Where applicable it will translate the return code into a human readable exit number, or
signal number (See LAST_RUN_EXIT_REASON), or if unable to determine the cause
of the command's exit, it will return a hex value representing the abnormal
exit code.

LAST_RUN_EXITED was added in version 1.32.

=head2 LAST_RUN_EXIT_REASON

When using the LAST_RUN_EXIT call to get an exit code, you may wish to see
how the program exited (normally, due to receiving a signal, or abnormally).
The LAST_RUN_EXIT_REASON call gets this done for you. It will return any of
'normal', 'signaled', or 'abnormal', depending on how the last command executed
actually returned.

LAST_RUN_EXIT_REASON was added in version 1.32.

=head2 SSH

In order to obtain an SSH connection with standard error checking/alerting
on connection issues, use the SSH call. This was implemented for use with the
RUN call, to allow for running external commands via SSH.

  my $ssh = SSH($host, $user, $pass, { ssh_option => 'value' });

CRITICAL alerts will be generated if there are errors connecting to $host,
if the credentials were invalid, or if for some reason perl was unable to
instantiate the Net::SSH::Perl object.

SSH has been available since version 1.22.

=head1 SAR DATA

The framework has baked-in support for parsing system activity data via the
sar(1) and sadf(1) facilities.  Using the B<SAR> function, you can ask for
specific statistics, averaged across the last X samples:

    # get network statistics from sar
    my $sar = SAR "-n DEV";
    for my $dev (keys %$sar) {
        next unless $dev =~ m/^eth/; # only Ethernet ifaces
        OK "Transmitting $dev->{'txpck/s'} packets/s";
    }

The first argument (C<-n DEV>, in the example above) is a set of flags to
send to sar(1)/sadf(1), and it controls what statistics you get back.

By default, the last sample will be used.  If you want multiple samples, use
the B<samples> and optional B<slice> parameters:

    my $sar = SAR "-n DEV", samples => 10;

    # the same, more explicit
    my $sar = SAR "-n DEV", samples => 10, slice => 60;

The B<slice> parameter indicates how many seconds each sample covers.  At
Synacor, this is currently 60s, which is the default value.  You should only
override this value if you know what you are doing and why.

The framework does not currently allow you to analyze more than a 24-hour
period, but it will handle the midnight boundary, when sadc(1) switches from
one file to the next, transparently.

Here are some possible values for the B<SAR> flags argument:

    SAR "-u -P ALL"; # aggregate CPU stats

    SAR "-v";        # inode/file table usage
    SAR "-d";        # block device activity
    SAR "-b";        # I/O read/write

    SAR "-n DEV";    # network I/O stats
    SAR "-n EDEV";   # network interface errors

    SAR "-q";        # process scheduling stats

    SAR "-B";        # kernel MMU paging stats
    SAR "-r";        # memory/swap utilization
    SAR "-R";        # memory paging stats
    SAR "-W";        # swapping stats

For full details, check the sar(1) man page.

If B<SAR> is unable to gather the requested samples, it will issue a WARNING
to that effect.  This is designed to ensure that we don't continue to try to
analyze data that we couldn't get.  You can escalate this to a CRITICAL or
an UNKNOWN by setting the B<missing_sar_data> setting:

    SET missing_sar_data => 'CRITICAL';
    my $sar = SAR "-d", samples => 60;

There is currently no way to ignore a failure in SAR data collection.

SAR has been available since version 1.27.

=head2 Translating Device Names

The B<DEVNAME> function lets you translate one or more block device names,
coming from sar(1), into absolute device paths.  For example, dev8-1 might
actually be /dev/sda1 on one system, in which case, the following:

    print DEVNAME "dev8-1"; # prints '/dev/sda1'

This can be useful specifically with the C<-d> flag to use more
human-friendly device names in output messages:

    my $sar = SAR "-d";
    for (keys %$sar) {
        my $dev = DEVNAME $_;
        OK "something for $dev";
    }

DEVNAME has been available since version 1.27.

=head1 CHECKING THRESHOLDS

Check plugins often need to selectively trigger a problem based on a range
or acceptable values.  A disk check may want to cause a WARNING if 80% of
the partition is in use, but escalate to a CRITICAL it 90% or above.

This is done with the B<CHECK_VALUE> function:

  $used = get_percent_used($disk);

  CHECK_VALUE $used, sprintf("$disk is %0.2f%% used", $used*100.0);
              warning  => 0.8,
              critical => 0.9;

This is logically equivalent to

  $used = get_percent_used($disk);
  if ($used > 0.9) {
    CRITICAL sprintf("$disk is %0.2f%% used", $used*100.0);
  } else {
    WARNING sprintf("$disk is %0.2f%% used", $used*100.0);
  } else {
    OK sprintf("$disk is %0.2f%% used", $used*100.0);
  }

If either threshold is not specified, that type of problem will
not be triggerable.

B<CHECK_VALUE> also accepts a B<skip_OK> key, whose presence will prevent
the framework from registering OK messages if neither threshold is
triggered.  This can be useful to keep OK check output manageable:

  for my $f (@files) {
    CHECK_VALUE -s $file, "$file is too big!",
      warning  => $size_warn,
      critical => $size_crit;
  }
  OK "Files look great!";

In this example, the OK message will be just "Files look great!"

CHECK_VALUE has been available since version 1.0.

=head1 TRACKING PERFORMANCE DATA

Performance data is what the monitoring system uses to generate trending
graphs.  This data is collected by check plugins, via B<TRACK_VALUE>.

For each data point, the plugin must specify a label and the value:

  TRACK_VALUE "loadSys",  $load_sys;
  TRACK_VALUE "loadUser", $load_user;

A plugin can track as many data points as it wants, within reason.

The global option B<--noperf> renders all B<TRACK_VALUE> calls as noops,
preventing them from actually working.  This is handy when you need to run
a plugin for its threshold analysis, but are already tracking the
performance data elsewhere.

TRACK_VALUE has been available since version 1.0.

=head1 CALCULATING RATES

Sometimes, data gathered is in an absolute, ever-increasing counter, like
the number of processes created by the kernel since boot.  Usually, you want
this kind of data to be graphed and thresholded as a gauge, or rate of
change per unit time.

This is what B<CALC_RATE> was built for.

To use B<CALC_RATE>, you'll need to pass in a hashref of counter values,
an arrayref of keys that should be rate-calculated (optional), a store file
and a staleness threshold.  For example:

    my %data;
    $data{processes} = get_processes_since_boot();
    $data{contextsw} = get_context_switches_since_boot();

    my $rates = CALC_RATE(data       => \%data,
                          want       => ['processes', 'contextsw'],
                          store      => 'sysproc',   # /var/tmp/mon_sysproc
                          resolution => '60s',       # default
                          stale      => '5m');

    # don't forget to STORE the data!
    STORE 'sysproc', \%data, as => 'yaml';

The five options, I<data>, I<want>, I<store>, I<stale> and I<resolution>
are all that B<CALC_RATE> recognizes.  Other keys are ignored.

I<store> uses the STORE/RETRIEVE convention of storing in /var/tmp with the
mon_ prefix.  This is B<required>.

I<data> contains the counter values and is also required.

I<want> is a single value or array of keys to calculate the rate over.
If not specified, all keys will be rate-calculated.

I<stale> is the staleness threshold (in seconds) for doing rate
calculations.  If the store file is found to be older than this threshold,
rate calculation will be skipped, a new state file will be written (with
current data) and a WARNING will be issued.

I<resolution> is the period resolution for the rate.  It defaults to 60s,
but can be overridden to make per-second calculations (as '1s').  The rate
resolution B<must be> less than the check interval.  If the check runs every
5 minutes, a 10m resolution makes no sense.

B<CALC_RATE> handles wraparound by detecting when counter values regress
(i.e. are less than they were last time).  This can sometimes represent
integer overflow, but usually indicates that the process doing the counting
has been restarted.  On wrap-around, B<CALC_RATE> will skip the rate
calculations, to avoid ending up with large negative rates and skewing
graphs.

CALC_RATE has been available since version 1.28

=head1 TIMERS and TIMEOUTS

Check plugins usually have to deal with external factors: other programs,
remote servers, etc.  Considering that the monitoring system has to perform
best when everything else is broken or down, plugins need to be written
defensively, protecting themselves from misbehavior.

One tactic for defensive plugin development is timeouts.  If a check plugin
needs to connect to a web server, there is a chance that the connection will
hang indefinitely.  If that happens, the plugin will eventually be killed,
but no useful output will be gathered.

Using timeouts, the plugin can control how long it is willing to wait for
an external factor to run before giving up:

  START_TIMEOUT 45, "Connecting to $host:8080";
  connect_to($host, 8080);
  STOP_TIMEOUT

If the I<connect_to> call takes longer than 45 seconds, the check plugin
will exit, triggering a critical problem of "Timed out after 45s: Connecting
to $host:8080".

Using the B<STAGE> function, a plugin can change the message given when
the timeout expires:

  START_TIMEOUT 30, "doing the first thing";
  task1();

  STAGE "doing the second thing";
  task2();

  STOP_TIMEOUT

If the timeout expires during the execution of task2, the critical problem
will be "Timed out after 30s: doing the second thing".

Timeouts cannot be nested; calling B<START_TIMEOUT> inside of another timeout
will cause odd and undefined behavior.

B<Note:> Timeouts and Perl's B<sleep> function do not interfere; plugins
can use both without issue.

Closely related to timeouts are timers.  Each plugin maintains two timers, a
B<total> timer that tracks how long the plugin has been running, and a B<stage>
timer for tracking run time in the current stage.  The B<stage> timer is reset
every time you call either B<STAGE> or B<START_TIMEOUT> (with a 'stage'
parameter).

To get the value of either timer, call B<TOTAL_TIME> or B<STAGE_TIME>:

  STAGE "connecting to port";
  do_connect();
  TRACK_VALUE "connTime" => STAGE_TIME;

  STAGE "running query";
  run_query();
  TRACK_VALUE "queryTime" => STAGE_TIME;

  cleanup();
  TRACK_VALUE "totalTime" => TOTAL_TIME;

START_TIMEOUT, STAGE and STOP_TIMEOUT have been available since version 1.0.

TOTAL_TIME and STAGE_TIME have been available since version 1.08.

=head1 SAVING STATE

Check plugins may need to save some data between runs.  This could be anything
from the last value it sampled to the seek offset in a log file.  The framework
makes this easy and standardized through the B<STORE> and B<RETRIEVE> functions:

  my $seek = RETRIEVE("log.seek");
  # do something with $seek
  STORE("log.seek", $seek);

All state files managed through this interface will be:

=over

=item Stored in the same place (usually /var/tmp)

=item Owned by the correct user (usually nagios)

=back

If the file does not exist, B<RETRIEVE> will return I<undef>.  If the file
cannot be written to during a B<STORE> call, the plugin will exit immediately,
triggering an UNKNOWN problem.

By default, B<RETRIEVE> will behave much the like the UNIX B<cat> utility; the
file will be opened read-only, and the mtime will not be changed.  This can
cause problems for checks that do not write to the file if a problem is detected
(i.e. the amount of memory present does not match the amount of memory from the
last run).  Filesystem cleanup scripts like tmpwatch have been known to erase
these state files when such problems persist for too long.

To handle this, B<RETRIEVE> can be told to touch the file before accessing it:

  my $state = RETRIEVE("state", touch => 1);

If the file does not exist, there is no change in behavior.  If it does exist,
its mtime will be updated to the current epoch time stamp.

Starting with version 1.11 of the framework, STORE and RETRIEVE accept an
optional format for serialization / deserialization.

  my $state = { is => "ok", last_checked => time };
  STORE "state", $state, as => "YAML";

  my $state = RETRIEVE "state", as => "YAML";

See B<STORE AND RETRIEVE FORMATS> for more information on values for the 'as' key.

Starting with version 1.18, STORE and RETRIEVE (and by extension, STATE_FILE_PATH)
accept an C<in> option that can specify a path under either /tmp or /var/tmp,
where the state file should exist (for RETRIEVE) or be created (for STORE).

Note that if you specify a directory structure underneath /tmp or /var/tmp, all
intervening directories will need to be created beforehand for STORE or
RETRIEVE to work.

STORE and RETRIEVE have been available since version 1.0.

Formats using the C<as> keyword have been available since 1.11.

=head1 STORE AND RETRIEVE FORMATS

B<STORE> and  B<RETRIEVE> provide shortcuts for saving/retreiving data in different
formats. These are specified by passing the 'as' key to the %options argument of
those functions. The values are case insensitive, and are limited to the following
formats:

=over 8

=item B<yaml>

Stores data in multi-line YAML format.

=item B<yml>

Alias to the B<yaml> format

=item B<json>

Formats data as JSON.

=item B<raw>

Stores raw data into a file.  Non-scalar values (including hash- and array-refs)
are no longer permitted by STORE (they were until v1.21).  If you need to handle
complicated data structures, consider using the B<yaml> or B<json> formats.

=item B<data_archive>

Formats the data as JSON using a hashref of datasets keyed by storage time. This
is primarily used by fetch_* scripts. See B<FETCH SCRIPTS> under the B<ADVANCED
FUNCTIONS> section for more details.

=back

=head1 CREDENTIALS MANAGEMENT

Often, check plugins require a username / password combination in order to
access authenticated services.  It is best not to hard-code these values into
the check code.  The difficulty lies in balancing flexibility with security.

The framework provides a solution via its internal Credentials Store, or
I<credstore>.  The credstore is a YAML file with secure ownership and
permissions, that stores credentials by key.  The B<CREDENTIALS> function allows
check plugins to extract username/password pairs.

For example, credentials for accessing the test account on the corporate email
account might be stored under the I<email> key.

  my ($user, $pass) = CREDENTIALS('email');

You can pass as many keys as you want to B<CREDENTIALS>; it will try each key
in turn and return the first set of credentials that match.  This allows you
to specify specific keys first, and fall back to more generic keys as needed:

  my $host = "host.example.com";
  my ($user, $pass) = CREDENTIALS("$host/email", "email");

In this case, if the 'host.example.com/email' key is not found in the credstore,
try the more generic 'email' key.

Another function, B<CRED_KEYS> makes it easy to generate a list of credentials
keys that can be overridden at the server role level, cluster level and host
level:

  my $host = "role01.atl.synacor.com";
  my ($u, $p) = CREDENTIALS( CRED_KEYS("LDAP", $host) );

This code searches for the following keys in the credstore:

=over 8

=item LDAP/role01.atl.synacor.com

=item LDAP/atl/role

=item LDAP/atl/*

=item LDAP/*/role

=item LDAP

=back

As of version 1.23, B<CRED_KEYS> also supports an IP address instead of hostname.
It can be used like this:

  my $ip = "10.10.10.10";
  my ($u, $p) = CREDENTIALS( CRED_KEYS("MYTEST", $ip) );

This returns the following keys:

=over 8

=item MYTEST/10.10.10.10

=item MYTEST

=back

If the framework encounters any problems extracting the I<email> key from the
credstore, it will immediately halt the plugin and trigger an UNKNOWN alert with
an appropriate description.  Failure scenarios are:

=over 8

=item 1. The credstore does not exist or is not readable

=item 2. The credstore file has insecure permissions (not 0400)

=item 3. Corruption in the credstore (bad YAML)

=item 4. Requested credentials not found (under any key)

=item 5. Malformed credentials key (no username and/or no password)

=back

You can B<SET> the I<ignore_credstore_failures> setting to avoid this
behavior:

  SET ignore_credstore_failures => 1;
  my ($user,$pass) = CREDENTIALS "$host-ldap";
  if (!$user) {
    ($user, $pass) = CREDENTIALS "DEFAULT-ldap";
  }

In this example, the check looks for credentials specific to this
$host, and if that fails, looks for the defaults.

=head2 The credstore file format

The credstore is a YAML file that looks like this:

  mysql: # the lookup key
    username: db_readonly
    password: secret
  router:
    username: admin
    password: password

The names of the top-level keys are up to the discretion of check
plugin writers.  Each key must have a username and password subkey,
and no other keys or subkeys.

=head2 Where is the credstore file?

The framework tries to determine the correct path to the credentials
file, based on its running environment.  The following algorithm is used:

=over 8

=item 1. Use the environment variable MONITOR_CRED_STORE, if it exists.

=item 2. If run under sudo, use .creds in the I<original> user's home

=item 3. Otherwise, use .creds in the current user's home

=back

To illustrate, suppose that the user jdoe runs a check plugin as herself.
The plugin will access the credstore /home/jdoe/.creds.  If she runs it as
the icinga user, under sudo, it will still use /home/jdoe.creds.  This
is specifically aimed at testing, and 'sudo as root' scenarios.

=head1 ADVANCED FUNCTIONS

This section details some of the more specialized functions that the framework
provides.  If you have a suggestion for something you see multiple times in
different check plugins, please suggest to the monitoring team that it be added
to the framework.

=head2 HTTP Requests

The plugin framework provides primitives for interacting with HTTP web servers.
These functions provide proper User Agent identification to the remote
endpoint, and take care of some of the drudgery of dealing with LWP.

The primary functions B<HTTP_REQUEST>, although in most applications, the
alternate helper functions, like B<HTTP_GET> are much more useful.

=over

=item HTTP_GET $url, \%headers, \%options

=item HTTP_PUT $url, $data, \%headers, \%options

=item HTTP_POST $url, $data, \%headers, \%options

=back

When called in scalar context, these functions return a simple boolean value
reflecting the success or failure of the request:

  if (HTTP_GET $url) {
    # success!
  }

In list context, they return two objects: the HTTP::Response object itself,
and the decoded content of the response.

  my ($res, $data) = HTTP_GET $url;
  if ($res->is_success) {
    # success!  do something with $data
  }

The HTTP_* functions are available as of version 1.03.

The following options can be passed to any of these functions (as the
final hashref argument) to influence how the request is made:

=over

=item UA

User Agent string to set for the outgoing request.  Defaults to
"SynacorMonitoring/$VERSION".

=item timeout

Timeout value (in seconds) for making the request.  Defaults to the
global I<--timeout> parameter value.  If you are making multiple
requests, you should probably set this to something lower.

=item username

=item password

If username and password are both set, HTTP authentication will be
requested, using these credentials.

=back

=head2 DECODE_JSON

Sometimes, HTTP requests give back JSON or JSONP results, that need to be
deserialized into Perl hashes and arrays.  The B<DECODE_JSON> function makes
this easy:

    my ($res, $data) = HTTP_GET $url;
    if ($res->is_success) {

        my $payload = JSON_DECODE $data;
        OK "Found 'title' in JSON data"
            if $payload->{title};

    }

The padding function call will automatically be removed from a JSONP
request, so the response 'jsonp("{...}")' will be treated as if the server
had responded with just '{...}'.  The framework will automatically detect
whether or not it needs to do JSONP unpacking.

If there are any problems parsing the JSON/JSONP response, the undef value
will be returned:

    JSON_DECODE $raw_data
       or CRITICAL "JSON response not understood";

Technically speaking, the above code would also alert if the JSON response
was '~', a literal null / undefined value.  If you truly need to
differentiate this state from an error state, feel free to use Perl's JSON
module directly, and please carefully re-think the API design.

=head2 SLURP

SLURP provides the simple ability to read in a file and grab all
of its contents. This is something we do often in various check plugins,
so has been frameworked to provide a common codebase. This feature has
been available since 1.15.

=head2 JOLOKIA / REMOTE JMX

For monitoring our Java platforms, we have settled on the Java Management
eXtensions, or JMX, to expose and collect data.  To access JMX data from
Perl, the monitoring team maintains a proxying / gateway service that wraps
Remote JMX up in a RESTful, HTTP API.  This proxy is called B<Jolokia>.

To use JMX, your plugin will need to call B<JOLOKIA_CONNECT> with the proper
target host and port:

    JOLOKIA_CONNECT host => "mq01.appfoo.synacor.com",
                    port => 1105;

You can optionally sepcify a B<creds> parameter to JOLOKIA_CONNECT for
determine what credentials should be used to talk to the Jolokia proxy;
usually, however, the default (C<remote_jmx>) is sufficient.

Once connected, you can ask for specific MBeans by their fully-qualified
names (i.e. "$domain:$name") using the B<JOLOKIA_READ> function:

    my $data = JOLOKIA_READ 'java.lang:type=Memory';
    my $usage = $data->{'java.lang:type=Memory'}{HeapMemoryUsed};
    CHECK_VALUE $usage, "JVM Heap Usage is $usage",
                warning  => 80,
                critical => 90;

JOLOKIA_READ returns a hashref of all the MBeans you asked for (and you
B<can> ask for multiple).  The second level of the hashref contains the
attributes of each MBean (in this case, I<HeapMemoryUsed> is an attribute of
the I<type=Memory> MBean in the I<java.lang> domain).

You can also dynamically lookup beans based on Perl-compatible regular
expression, by way of B<JOLOKIA_SEARCH>:

   my @beans

   # get *ALL* the beans!
   @beans = JOLOKIA_SEARCH;

   # or, just get the ones for com.synacor.*
   @beans = JOLOKIA_SEARCH '^com.synacor.';

These two functions are designed to work together seamlessly, so that you
can do this:

    my $data = JOLOKIA_READ(JOLOKIA_SEARCH m/type=Memory$/);

That is, read all MBeans that have 'type=Memory' in their name, across any
and all domains.

B<JOLOKIA_CONNECT>, B<JOLOKIA_READ> and B<JOLOKIA_SEARCH>
have been available since v1.26.

=head2 SNMP INTEGRATION

SNMP, Simple Network Management Protocol, is an official standard for remote
management, monitoring and device introspection.  Several platforms are only
reachable via SNMP, chief among them network devices like firewalls, routers
and core switches.

The plugin framework provides a set of primitives that make writing plugins
based on SNMP interactions easy and painless.  These functions are divided
into two groups: MIB Management and Agent Interaction.

MIBs (Management Information Bases) are kind of like schema definitions for
SNMP trees.  They define the semantics of different parts of the hierarchy,
enforcing syntax and providing meaning that is otherwise very difficult to
determine.

For example, the OID (Object Identifier) 1.3.6.1.2.1.1.5 contains the name
of the system, per the agent configuration.  The B<SNMPv2-MIB> contains this
definition, and also names 1.3.6.1.2.1.1 as I<system> and 1.3.6.1.2.1 as
I<mib-2>.  Since these symbolic names are so handy, all SNMP framework
functions will transparently perform name -> OID resolution behind the
scenes.

The B<OID> and B<OIDS> functions can be used explicitly to perform this
resolution.

All of the B<SNMP_*> functions comprise the Agent Interaction side of the
house.  To ease into this, let's consider an example:

    SNMP_MIB "ENTITY-MIB";
    SNMP_MIB "IF-MIB";

    SNMP_SESSION OPTION->host,
      port      => 161,             # this is the default
      version   => '2c',            # so is this
      timeout   => 5,               # ... as is this
      community => 'MyCommunity'
        OR BAIL(CRITICAL "Failed to connect to SNMP!");

    my $name = SNMP_GET '[sysName].0';
    DEBUG "Got sysName = $name";
    OK "Connected to SNMP";

For such a small plugin, it covers all of the important aspects of SNMP.

First up, we have to calls to B<SNMP_MIB>.  This function compiles and loads
named MIBs into memory, so that they can be consulted for OID resolution.

Next, the B<SNMP_SESSION> call initiates the connection to the remote SNMP
agent.  You can pass the B<port>, B<version>, B<community> and B<timeout>
options to influence how the connection is made, but for most use cases you
will only need B<community>.  Note that B<SNMP_SESSION> returns a false
value if the remote agent cannot be contacted.

In the last part of the example, we call B<SNMP_GET> to retrieve the value
of a single OID.  The string '[sysName].0' is in a format recognizable to
the framework, and will instruct B<SNMP_GET> to replace '[sysName]' with the
resolved numeric OID for the sysName subtree from the SNMPv2-MIB, before
making the query request.

In addition to B<SNMP_GET>, you have to other retrieval functions to choose
from: B<SNMP_TREE> and B<SNMP_TABLE>.  The former will return the requested
OID value, and all other OIDs underneath it (i.e. the value of all OIDs who
share the given OID as a prefix).  This is not nearly as useful as
B<SNMP_TABLE>, which deserves its own example:

    my $r = SNMP_TABLE qw/entPhysicalName
                          cpmCPUTotal5min/;

    for (sort keys %$r) {
        next unless exists $r->{$_}{cpmCPUTotal5min};

        my $cpu  = $r->{$_}{entPhysicalName};
        my $perf = $r->{$_}{cpmCPUTotal5min};

        CHECK_VALUE $perf, sprintf("CPU %s is %0.1f%% used", $cpu, $perf),
            warning  => OPTION->warning,
            critical => OPTION->critical;
    }

Here, we are stitching together disparate tables that share an indexing
strategy (namely, the physical index).  This allows us to easily associate a
processor name (entPhysicalName) with the 5-minute usage rate, inside of a
Cisco ASA device.

If we were to walk these two OIDs outside of the framework, we might see a
tree that looks like this:

    $ snmpwalk ... 1.3.6.1.2.1.47.1.1.1.1.7
    .1.3.6.1.2.1.47.1.1.1.1.7.1 = STRING: "WS-C6504-E"
    .1.3.6.1.2.1.47.1.1.1.1.7.2 = STRING: "Physical Slot 1"
    .1.3.6.1.2.1.47.1.1.1.1.7.3 = STRING: "Physical Slot 2"

(1.3.6.1.2.1.1.47.1.1.1.1.7 is entPhysicalName)

    $ snmpwalk ... 1.3.6.1.4.1.9.9.109.1.1.1.1.5
    .1.3.6.1.4.1.9.9.109.1.1.1.1.5.1 = Gauge32: 6
    .1.3.6.1.4.1.9.9.109.1.1.1.1.5.2 = Gauge32: 10
    .1.3.6.1.4.1.9.9.109.1.1.1.1.5.3 = Gauge32: 1

(1.3.6.1.4.1.9.9.109.1.1.1.1.5 is cpmCPUTotal5min)

What B<SNMP_TABLE> does is look at these sets of trees, remove the base OID
from each (so both sets of indices are reduced to [1,2,3]), and then merges
it all together.  With the above data, the following code:

    DUMP SNMP_TABLE qw/entPhysicalName cpmCPUTotal5min/;

would print out the following:

    DEBUG> $VAR1 => {
                      '1' => {
                                entPhysicalName => "WS-C6504-E",
                                cpmCPUTotal5min => 6,
                             },
                      '2' => {
                                entPhysicalName => "Physical Slot 1",
                                cpmCPUTotal5min => 10,
                             },
                      '3' => {
                                entPhysicalName => "Physical Slot 2",
                                cpmCPUTotal5min => 1,
                             }
                    }

And the following code (which supplies explicit keys):

    DUMP SNMP_TABLE { name  => 'entPhysicalName',
                      usage => 'cpmCPUTotal5min' };

would print out the following:

    DEBUG> $VAR1 => {
                      '1' => {
                                name  => "WS-C6504-E",
                                usage => 6,
                             },
                      '2' => {
                                name  => "Physical Slot 1",
                                usage => 10,
                             },
                      '3' => {
                                name  => "Physical Slot 2",
                                usage => 1,
                             }
                    }

B<SNMP_TABLE> can make your life quite a bit easier, especially if you are
dealing with contiguous trees (like all of the B<if*> values for host
interfaces).

SNMP MIBs can define TEXTUAL CONVENTIONS and ENUMERATIONS that map numeric
values to more human-friendly names.  The B<SNMP_TC> amd B<SNMP_ENUM>
functions exist to look up these friendly names, given the type and a value.

For example, B<IF-MIB> provides the B<ifOperStatus> field, which is defined
as an enumeration.  If you want to see the friendly name for a given value,
you should use B<SNMP_ENUM>:

    SNMP_MIB 'IF-MIB';

    # ... connect ...

    my $status = SNMP_GET '[ifOperStatus].0';
    DEBUG "interface 0 is " . SNMP_ENUM($status, 'ifOperStatus');

Each function takes an optional third parameter that lets you control the
format of the returned string.  Any B<%s> sequences will be replaced with
the display name of the TC/enum, and B<%i> will be replaced with the numeric
value.  For example:

    OK "eth0 is " . SNMP_ENUM($status, 'ifOperStatus', '%s(%i)');

Will give you messages like "eth0 is up(1)" and "eth0 is testing(3)".

All of this information is compiled from the local MIB cache, so you need to
load the MIBs that define these enumerations and textual conventions via
B<SNMP_MIB>.

NOTE: SNMP support depends on the Perl SNMP::MIB::Compiler module (in the
perl-SNMP-MIB-Compiler RPM package).  If that is not installed, any calls
to SNMP functions will result in an UNKNOWN alert.

B<SNMP_*>, B<OID> and B<OIDS> have been available since v1.30.

=head2 FETCH SCRIPTS

Fetch scripts are designed to pull bulk performance data from an application
via one command, and store them for processing by multiple checks. This
is currently necessary due to the limitation we have of associating a single
graph to a single check. We don't necessarily want to build graphs
with every possible datapoint (of vastly differing scales and scope)
for an application. Additionally, we wish to reduce the monitoring overhead
on an application by retrieving data as little as possible.

As a result, B<fetch_*> were born. Their purpose is to connect to
an application (mongo, redis, jmx-based data via jolokia, etc.), and retrieve
a large amount of data to be stored locally. Some of the data may need
to reference older data, so the data is stored via the B<data_archive> STORE
format (see B<STORE AND RETRIEVE FORMATS>), which handles the grunt work of
handling data retention, keying datasets based on storage time, and storing
into local temp files.

Once this is done, B<check_*> scripts can be used to retrieve specific datapoints
from the stored data, and calculate thresholds/perfdata as appropriate for the
specific datapoint (COUNTER vs GAUGE vs rolling AVG). These checks should then
be dependent on the corresponding fetch_* script in nagios, such that a problem
retrieving data will not result in mass-alerts for all the datapoint checks.

Lifecycle of fetch_* plugins:

1. Connect to application

2. Gather all data we're interested in measuring in as bulk a fashion as possible

3. Store the data:

   STORE($path, $data, as => 'data_archive');

4. Alarm if there were issues retrieving/parsing data from the application, or
errors storing the data.

While asynchronously, related check_* plugins will do the following:

1. Grab latest N datapoints (1, 2, 3, ... depending on how many are needed for the
current calculation)

2. Calculate the metric we wish to display (e.g. [current - last] / [now - then]
for count/min)

3. Apply any thresholds, generate perfdata, and alarm appropriately.

By DEFAULT, if no previous data was found for a fetch_* script, a WARNING message
will be generated. This is configurable via the B<on_previous_data_missing> setting:

    SET on_previous_data_missing => 'unknown';

Data Retention for B<fetch_*> scripts defaults to deleting datapoints that are older
than 24 hours. To alter this behavior, use the B<delete_after> setting (set in seconds);

    SET delete_after => 120;               # delete after 2 minutes
    SET delete_after => 60 * 60 * 24 * 30; # delete after 30 days

See the B<SETTINGS> section for more details on how B<delete_after> and
B<on_previous_data_missing> behave.

=head1 DEBUGGING

Debugging output explains a check plugin is doing, and proves to be a
useful tool for understanding why problems are being triggered, and why
a plugin doesn't work.

By default, debugging is disabled.  The B<--debug> and B<-D> flags will
turn it on.  Plugins don't have to specify this option; it comes with
every plugin for free.

All debugging output is prefixed with 'DEBUG> ', to separate it from
output from commands, other Perl modules, etc.

The B<DEBUG> function prints messages to the screen.

  DEBUG("The thing is now $state_of_thing");

The B<DUMP> function dumps out a formatted representation of one or more
variables, using Data::Dumper:

  DUMP($http_headers, $json_response);

=head1 DRY-RUN MODE

When debugging checks, it can be useful to run the check plugin in such a way
that the live running system (i.e. state files) is not affected.

For this use case, the globally defined B<--noop> flag will turn on a mode
where calls to B<STORE> perform no real work.  Note that B<RETRIEVE> still
works in noop mode, since reading is free.

To alter your plugin's behavior based on whether or not dry-run mode is active,
use the B<NOOP> function (and don't forget to B<DEBUG>!):

  if (NOOP) {
      DEBUG "Running in NOOP mode; skipping destructive action!";

  } else {
      run_destructive_action;
  }

=head1 DEPRECATED FEATURES LIST

=head2 STORE/RETRIEVE of scalar values (v1.21)

Prior to 1.21, B<STORE> and B<RETRIEVE> would transparently handle Perl array
references and calling context for raw format read/writes.  When STORE was
given an array reference, and no explicit format, it would join the array items
together (without a delimiter).  If RETRIEVE was called in list context, it
split the lines out of the state file and returned those as a list.

This behavior predates storage formats like YAML and JSON.  Storage formats are
also superior, and provide more readability to people trying to troubleshoot
check plugin state files.

=head1 AUTHOR

James Hunt C<< jhunt@synacor.com >>

=cut
