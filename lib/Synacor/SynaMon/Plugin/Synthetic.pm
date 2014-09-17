package Synacor::SynaMon::Plugin::Synthetic;

# author:  Dan Molik <dmolik@synacor.com>
# created: 2014-06-02

use strict;
use Socket;
use Time::HiRes qw/sleep/;
use POSIX qw/sys_wait_h/;
use base qw/Exporter/;

my $MASTER_PID = $$;

my $TRACE = 0;
my %PIDS;
my $DRIVER;

sub START_SYNTHETIC
{
	my (%options) = @_;

	OPTION "url|u=s",
		help     => "The initial url to check against.",
		required => 1;

	OPTION "useragent|U=s",
		help => "Set the phantomjs useragent.";

	OPTION "mobile",
		help => "Give phantomjs a 'mobile' useragent";

	START;

	eval 'use Synacor::Test::Selenium::Utils; 1'
		or BAIL("Synacor::Test::Selenium::Utils Missing, Bailing Check!");
	eval 'use Synacor::Test::Selenium::Driver::Phantom; 1'
		or BAIL("Synacor::Test::Selenium::Driver::Phantom Missing, Bailing Check!");

	my $url = OPTION->url;
	   $url = "http://$url" if $url !~ m/^https?:\/\//;
	return $DRIVER if $DRIVER;
	my @DEBUG_LOG = ("--webdriver-loglevel=NONE");
	if (OPTION->debug) {
		$ENV{DEBUG} = 1;
		DEBUG "Saving ghostdriver logs to /tmp/phantomjs.$$.debug.log";
		@DEBUG_LOG  = (
			"--webdriver-loglevel=DEBUG",
			"--webdriver-logfile=/tmp/phantomjs.$$.debug.log"
		);
	}
	my @PHANTOM = qw|/usr/bin/phantomjs --ignore-ssl-errors=yes|;
	push @PHANTOM, @DEBUG_LOG;
	BAIL(CRITICAL "$PHANTOM[0] does not exist")    unless -e $PHANTOM[0];
	BAIL(CRITICAL "$PHANTOM[0] is not executable") unless -x $PHANTOM[0];

	socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
	setsockopt($sock, SOL_SOCKET, SO_REUSEADDR, 1) || die "$!";
	bind($sock, sockaddr_in(0, INADDR_LOOPBACK)) || die "$!";
	my $port = (sockaddr_in(getsockname($sock)))[0];
	close $sock;

	push @PHANTOM, "--webdriver=127.0.0.1:$port";
	TRACE "Running: ".join ' ', @PHANTOM;
	my $pid = fork;
	if ($pid) {
		DEBUG "Spawned '$pid' to run phantomjs on $port";
		$PIDS{$pid} = "phantom";
	} else {
		close STDERR;
		close STDOUT;
		exec {$PHANTOM[0]} @PHANTOM or die UNKNOWN "Unable to start phantomjs: $!";
		exit;
	}

	START_TIMEOUT 3, "Phantomjs is not responding on port: $port";
	for (1..8) {
		# Going to squeeze out 5 tries before timeout
		# Never seen an active webdriver take more than 2
		my ($res, undef) = HTTP_GET "http://localhost:$port/sessions";
		last if $res->is_success;
		sleep .5;
	}
	STOP_TIMEOUT;

	BIND_LOGGING(
		debug => sub {
			DEBUG("PHANTOM DRIVER: $_[0]");
		},
		dump  => sub {
			TRACE "PHANTOM DRIVER:";
			TDUMP  $_[0];
		},
		error => sub {
			CRITICAL("PHANTOM DRIVER: $_[0]");
		});

	my $ua = "linux firefox";
	if (OPTION->mobile) {
		$ua = "apple iphone";
	} elsif (OPTION->useragent) {
		if (OPTION->useragent =~ m/^mobile$/i) {
			$ua = "apple iphone"
		} else {
			$ua = OPTION->useragent;
		}
	}

	STAGE "Starting Phantomjs Driver";
	$DRIVER = Synacor::Test::Selenium::Driver::Phantom->new(
		browser            => "phantomjs",
		platform           => "LINUX",
		protocol           => "http",
		site               => $url,
		host               => "localhost",
		port               => $port,
		ua                 => $ua,
		connection_timeout => 5,
	);

	$DRIVER->connect();

	return $DRIVER;
}


sub STOP_SYNTHETIC
{
	STAGE "Stopping Phantomjs Driver";
	$DRIVER->disconnect;
	STAGE "Tearing down Phantomjs";
	if ($MASTER_PID == $$) {
		for my $pid (keys %PIDS) {
			DEBUG "Term killing pid: $pid";
			kill "TERM", $pid;
		}
		sleep 1;
		for my $pid (keys %PIDS) {
			if (waitpid($pid, WNOHANG) < 0 ) {
				DEBUG "Removing pid: $pid, from run list";
				delete $PIDS{$pid};
			}
		}
		sleep 1;
		for my $pid (keys %PIDS) {
			DEBUG "Falling back and killing pid: $pid";
			kill "KILL", $pid;
		}
	}
	undef $DRIVER;
	DONE;
}

END {
	STOP_SYNTHETIC
		if $DRIVER;
}

sub SCREENSHOT
{
	my ($status, $msg) = @_;
	my $filename = STATE_FILE_PATH($msg, in => '/tmp').".png";
	$DRIVER->screenshot($filename)
		if OPTION->debug;
	DEBUG "Saving screenshot to $filename";
	return ($status, $msg);
}

my @FUNCTIONS = qw /
	SOURCE
	TITLE URL
	WINDOW_NAMES
	CLICK MOUSEOVER DROPDOWN
	PRESENT VISIBLE
	WAIT_FOR_IT
	OPEN_WINDOW SELECT_WINDOW VISIT CLOSE_WINDOW WINDOW_SIZE
/;

for my $sub (@FUNCTIONS) {
	no strict 'refs';
	my $name = lc $sub;
	*$sub = sub { $DRIVER->$name(@_) };
}

push @FUNCTIONS, qw/
	TEXT_OF VALUE_OF HTML_OF TYPE
	RUNJS REFRESH_PAGE
	START_SYNTHETIC STOP_SYNTHETIC
	SCREENSHOT CHECKBOX UNCHECKBOX
	WAIT_FOR_PAGE FOCUS_FRAME
/;

no warnings 'once';
*TYPE          = sub { $DRIVER->type(@_, clear => 1) };
*RUNJS         = sub { $DRIVER->run(js => join(" ", @_)) };
*HTML_OF       = sub { $DRIVER->html(@_) };
*TEXT_OF       = sub { $DRIVER->text(@_) };
*VALUE_OF      = sub { $DRIVER->value(@_) };
*REFRESH_PAGE  = sub { $DRIVER->refresh(@_) };
*CHECKBOX      = sub { $DRIVER->check(@_) };
*UNCHECKBOX    = sub { $DRIVER->uncheck(@_) };
*WAIT_FOR_PAGE = sub { $DRIVER->_wait_for_page(@_) };
*FOCUS_FRAME   = sub { $DRIVER->frame(@_) };
use warnings;

our @EXPORT = @FUNCTIONS;

=pod

=head1 NAME

Synacor::SynaMon::Plugin::Synthetic

=head1 SYNOPSIS

Synacor SynaMon Plugin Synthetic is an extension of the more generically scoped SynaMon Plugin
framework. The purpose of this framework extension is to provide a functional interface into
the Synacor Selenium Driver.

=head1 SYNTHETIC MONITORING

Synthetic Monitoring is a scripted web browser to model user behavior thus testing website
functionality. This is different from user tracking or real user monitoring in transactions
are fully scripted and controlled and do not change from test run to test run, ensuring a
smaller failure scope.

=head2 WHAT IT IS

=over

=item

Synthetic monitoring is a fully armed and operational web browser scripted via the
Synacor::Test::Selenium::Driver, which means javascript is supported in the tests.

=item

We can hit a website's major components just like our users even when they are asleep.
IE we can continue to hit a website even without production traffic.

=back

=head2 WHAT IT IS NOT

=over

=item

Synthetic monitoring is not a replacement for Quality Assuarance Testing. We do not have the
resources nor the time to test the full functionality of a website.

=item

It is not selenium testing, neither code from the selenium group nor the selenium server are
used or contacted in production.

=back


=head1 FUNCTIONS

=head2 SOURCE

Return the current page's source code including javascript modified code.

This function has to parameters.

=head2 TITLE

Return the title of the currently selected webpage.

This function has to parameters.

=head2 URL

Return the url of the currently selected webpage.

This function has to parameters.

=head2 WINDOW_NAMES

Return an array of all the currently open webage titles

This function has to parameters.

=head2 CLICK

Click on a DOM element.

Usage:

    CLICK
        selector => 'div.class1',
        timeout  => 5,
        x => 5, y => 5;

=head2 TYPE

Type a string into an input field.

Usage:

    TYPE
        selector => 'div.class1',
        timeout  => 5,
        value    => 'some text';

=head2 MOUSEOVER

Move the virtual cursor over a DOM element.

Usage:

    MOUSEOVER
        selector => $selector,
        timeout  => $timeout,
        x => $x, y => $y;

=head2 DROPDOWN

Select a option from a dropdown list, when no value is presented,
an array of values or labels is return, depending on which method
is passed.

Usage:

    DROPDOWN
        selector => $selector,
        timeout  => $timeout,
        method   => 'label|value',
        value    => $label_name;

=head2 PRESENT

Determine if a DOM element is present.

Usage:

    PRESENT
        selector => $selector,
        timeout  => 5;

=head2 VISIBLE

Determine if a present DOM element is visible.

Usage:

    VISIBILE
        selector => $selector,
        timeout  => 5;

=head2 OPEN_WINDOW

Open a new window with and go to the specified url.

Usage:

    OPEN_WINDOW
       url     => 'www.synacor.com',
       timeout => 5;

=head2 SELECT_WINDOW

Close a window by 4 different, first, last, num/order, title.

=over

=item first

Select the first window.

=item last

Select the last window.

=item num

Select the nth window.

=item title

Select the widow with matching title, selected by using the value
parameter.

=back

Usage:

    SELECT_WINDOW
        method  => 'first|last|num|title',
        value   => 1|2|red|blue,
        timeout => 5;

=head2 VISIT

Go to a new URL in the currently selected window.

Usage:

    VISIT
       url     => 'www.synacor.com',
       timeout => 5;

=head2 CLOSE_WINDOW

Close a window by 4 different, first, last, num/order, title.

=over

=item first

Close the first window.

=item last

Close the last window.

=item num

Close the nth window.

=item title

Close the widow with matching title, selected by using the value
parameter.

=back

Usage:

    CLOSE_WINDOW
        method  => 'first|last|num|title',
        value   => number or regex,
        timeout => 5;

=head2 REFRESH_PAGE

Reload the current page.

This function has no parameters.

=head2 WINDOW_SIZE

Set the size of the virtual window, with out parameters
this function defaults to 1920x1080.

Usage:

    WINDOW_SIZE
        width  => $width
        height => $height;

=head2 TEXT_OF

Get the text of a DOM element.

Usage:

    TEXT_OF
        selector => $selector,
        timeout  => 5;

=head2 VALUE_OF

Get the value of a DOM element.

Usage:

    VALUE_OF
        selector => $selector,
        timeout  => 5;

=head2 HTML_OF

Get the html of a DOM element.

Usage:

    HTML_OF
        selector => $selector,
        timeout  => 5;

=head2 RUNJS

Run arbitrary javascript code on the current site.

Usage:

    RUNJS
        "var arg1 = somefunction();",
        "return arg1;";

=head2 WAIT_FOR_PAGE

Wait for the current page to load (ie: to come back interactive).

This function has no parameters.

=head2 CHECKBOX

Select a checkbox in a form.

Usage:

    CHECKBOX
        selector => 'CSS SELECTOR';

=head2 UNCHECKBOX

Unselect a checkbox in a form.

Usage:

    UNCHECKBOX
        selector => 'CSS SELECTOR';


=head2 FOCUS_FRAME

Change the DOM context to a different iframe, a selector value of default 
will reset the 'frame' context to the original DOM, rather the starting page.
When switching frames, the entire DOM context is switched to the newly selected iframe.
You will have to reset your context to go to select any elements outside of the current iframe.

Usage:

    FOCUS_FRAME
        selector => "CSS SELECTOR|default";

=head2 WAIT_FOR_IT

A generic looping function to evaluate a boolean and keep going until timeout if
it is false.

Usage:

    WAIT_FOR_IT
        sub { TEXT_OF 'div.class1' eq 'THIS IS TEXT' },
        5;

Return false if timeout or value is never met.

=head2 START_SYNTHETIC

START the Naigios plugin.

Spool up phantomjs and connect to it with a newly instantiated Driver.

The keyed parameters are ua (user agent) and site (the website to test).

Usage:

    START_SYNTHETIC
        ua   => 'linux - firefox',
        site => 'www.google.com';

=head2 STOP_SYNTHETIC

Teardown phantomjs and free up the driver space, finalize the Nagios Plugin.

This function has no parameters.

=head2 SCREENSHOT

While in debugging mode save a screenshot of the current webpage to /tmp

Usage:

    SCREENSHOT(CRITICAL "There was an errors")
        unless TEXT_OF "div.class1" =~ m/found\s+text/;

=head1 WRITING A SYNTHETIC PLUGIN

Here is a basic synthetic plugin, see Synacor::SynaMon::Plugin for details
of writing basic plugins.

    #!/usr/bin/perl

    use Synacor::SynaMon::Plugin::Synthetic;

    PLUGIN
        name    => 'example',
        summary => 'do the example';

    OPTION 'host|H',
        help => "host to connect to";

    START; START_SYNTHETIC
        ua   => 'linux - firefox',
        site => OPTION->host;

    SCREENSHOT(CRITICAL "Missing element: 'dorp'")
        unless PRESENT 'div#dorp.longsynacorclassname';

    STOP_SYNTHETIC;

=head1 REFERENCES

=head2 Man Pages

=over

=item Synacor::Test::Selenium::Driver

=item Synacor::SynaMon::Plugin

=item Synacor::SynaMon::Plugin::Base

=back

=head2 Webpages

=over

=item http://code.google.com/p/selenium/wiki/JsonWireProtocol

=item http://phantomjs.org/documentation/

=item https://github.com/detro/ghostdriver

=item http://en.wikipedia.org/wiki/Synthetic_monitoring

=back

=head1 AUTHOR

Written by Dan Molik <dmolik@synacor.com>

=cut

1;
