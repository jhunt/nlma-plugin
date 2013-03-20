package Synacor::SynaMon::Plugin;

use strict;
use warnings;
use Synacor::SynaMon::Plugin::Base;

our $VERSION = "1.16";

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

"Make your time...";

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
   #    cpu    => { warn => '10',  crit => '2',     perf => '1' }, # default
   #    io_in  => { warn => '10',  crit => '20',    perf => '1' }, # perf=asdf
   #    io_out => { warn => '10',  crit => '20:30', perf => '0' }, # perf=no
   #    mem    => { warn => '10',  crit => '~:20',  perf => '0' }, # perf=0
   #    perf   => { warn => undef, crit => undef,   perf => '1' }, # perf
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

UNKNOWN, CRITICAL, WARNING and OK have been available since version 1.0.

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

TRACK_VALUE has been available since version 1.0.

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

Stores raw data into a file. Don't forget newlines if passing an array of strings!

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

=head2 SLURP

SLURP provides the simple ability to read in a file and grab all
of its contents. This is something we do often in various check plugins,
so has been frameworked to provide a common codebase. This feature has
been available since 1.15.

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

=head1 AUTHOR

James Hunt C<< jhunt@synacor.com >>

=cut
