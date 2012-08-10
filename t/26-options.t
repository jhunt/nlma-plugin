#!perl

use Test::More;
do "t/common.pl";

###################################################################
# option support

ok_plugin(0, "OPTION OK - done", undef, "option processing", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "warning|w=i",
		usage => "-w, --warning <rate>",
		help  => "rate to warn for";
	OPTION "critical|c=i",
		help => "rate to critical for";
	OPTION "default|d=i",
		usage => "-d, --default <n>",
		default => 45;

	START default => "done";

	OPTION->default  == 45 or CRITICAL "default value didn't take";
	OPTION->warning  == 5  or CRITICAL "-w was not 5";
	OPTION->critical == 10 or CRITICAL "--critical was not 10";

	DONE;
}, ["-w", 5, "--critical", 10]);

done_testing;
