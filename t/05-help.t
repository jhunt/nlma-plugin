#!perl

use Test::More;
do "t/common.pl";

###################################################################
# help option
{
	my $SCRIPT = "05-help.t";
	my $USAGE = "$SCRIPT -R|--required <string>\n";
	my $expect = <<EOF;
$SCRIPT 1.4

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY. 
It may be used, redistributed and/or modified under the terms of the GNU 
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

This is the help test-driver check plugin.  It is useless.

$USAGE
 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][\@file]
   Read options from an ini file. See http://nagiosplugins.org/extra-opts for usage
 -R, --required <string>
   A required option
 -d, --default <number>
   A default option (default: 45)
 -N, --nousage
   Option with no usage
 --nousage-default=STRING
   Default / no usage
 --debug, -D
   Turn on debug mode
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 22)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
EOF

	sub help_plugin
	{
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN name => "help", version => "1.4",
			summary => "This is the help test-driver check plugin.  It is useless.";

		OPTION "required|R=s",
			usage => "-R, --required <string>",
			help  => "A required option",
			required => 1;

		OPTION "default|d=i",
			usage => "-d, --default <number>",
			help  => "A default option",
			default => 45;

		OPTION "nousage|N",
			help => "Option with no usage";

		OPTION "timeout|t=i",
			usage => "-t, --timeout <seconds>",
			help  => "How long before timing out",
			default => 22;

		OPTION "nousage-default=s",
			help => "Default / no usage",
			default => 'the-default';

		START;
		DONE;
	}

	ok_plugin_help($expect, "--help (Help) output", \&help_plugin, ["--help"]);
	ok_plugin_help($expect, "-h (Help) output",     \&help_plugin, ["-h"]);
	ok_plugin_help($USAGE,  "-? (Usage) output",    \&help_plugin, ["-?"]);
}


## once more, without a default timeout ########################################33

{
	my $SCRIPT = "05-help.t";
	my $USAGE = "$SCRIPT -R|--required <string>\n";
	my $expect = <<EOF;
$SCRIPT 1.4

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY. 
It may be used, redistributed and/or modified under the terms of the GNU 
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

This is the help test-driver check plugin.  It is useless.

$USAGE
 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][\@file]
   Read options from an ini file. See http://nagiosplugins.org/extra-opts for usage
 -R, --required <string>
   A required option
 -d, --default <number>
   A default option (default: 45)
 -N, --nousage
   Option with no usage
 --nousage-default=STRING
   Default / no usage
 --debug, -D
   Turn on debug mode
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 15)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
EOF

	sub help_plugin_no_default
	{
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN name => "help", version => "1.4",
			summary => "This is the help test-driver check plugin.  It is useless.";

		OPTION "required|R=s",
			usage => "-R, --required <string>",
			help  => "A required option",
			required => 1;

		OPTION "default|d=i",
			usage => "-d, --default <number>",
			help  => "A default option",
			default => 45;

		OPTION "nousage|N",
			help => "Option with no usage";

		OPTION "timeout|t=i",
			usage => "-t, --timeout <seconds>",
			help  => "How long before timing out";

		OPTION "nousage-default=s",
			help => "Default / no usage",
			default => 'the-default';

		START;
		DONE;
	}

	ok_plugin_help($expect, "--help (Help) output", \&help_plugin_no_default, ["--help"]);
}

done_testing;
