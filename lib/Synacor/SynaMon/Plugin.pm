package Synacor::SynaMon::Plugin;

use strict;
use warnings;
use Synacor::SynaMon::Plugin::Base;

our $VERSION = "1.0";

use Exporter;
use base qw(Exporter);

sub import {
	my $class = shift;

	warnings->import;
	strict->import;

	my %tags = map { $_ => 1 } @_;
	if (exists $tags{':easy'}) {
		use Synacor::SynaMon::Plugin::Easy;
		Synacor::SynaMon::Plugin::Easy->export_to_level(1);
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
  TRACK "age" => $age;

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
a string in the format "<long>|<short>[=<type>]".  For flags that
are either on or off (like --debug), the "=<type>" part should be
omitted.  For arguments, the B<<type>> identifies the type of data to
be expected with that argument.  Valid type values are B<s> for text,
and B<i> for numbers.

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

=head1 TRACKING PERFORMANCE DATA

Performance data is what the monitoring system uses to generate trending
graphs.  This data is collected by check plugins, via the B<TRACK> function.

For each data point, the plugin must specify a label and the value:

  TRACK "loadSys",  $load_sys;
  TRACK "loadUser", $load_user;

A plugin can track as many data points as it wants, within reason.

=head1 TIMEOUTS

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
