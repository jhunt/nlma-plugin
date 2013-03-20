#!perl

use Test::More;
do "t/common.pl";

###################################################################
# option support

ok_plugin(0, "OPTION OK - done", undef, "option processing", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	use Test::Deep::NoTest;
	use Data::Dumper;

	PLUGIN name => "OPTION";
	OPTION "warning|w=i",
		usage => "-w, --warning <rate>",
		help  => "rate to warn for";
	OPTION "critical|c=i",
		help => "rate to critical for";
	OPTION "default|d=i",
		usage => "-d, --default <n>",
		default => 45;
	OPTION "check|C=%",
		help => 'ITM-2141 support for % parsing';

	START default => "done";

	OPTION->default  == 45 or CRITICAL "default value didn't take";
	OPTION->warning  == 5  or CRITICAL "-w was not 5";
	OPTION->critical == 10 or CRITICAL "--critical was not 10";

	my $expect = {
			cpu      => { warn => 10,    crit => 20,      perf => 'cpu'},
			io_in    => { warn => ':10', crit => '20:',   perf => 'asdf'},
			io_out   => { warn => 10,    crit => '20:30', perf => 0},
			mem      => { warn => 10,    crit => '~:20',  perf => 0},
			perf     => { warn => undef, crit => undef,   perf => 'perf'},
		};

	unless (eq_deeply($expect, OPTION->check)) {
		CRITICAL "--check's % style argument parsing failed.";
		print STDERR "Got:\n" . Dumper(OPTION->check);
		print STDERR "Expected:\n" . Dumper($expect);
	}


	DONE;
},	[
		"-w", 5,
		"--critical", 10,
		"--check", 'cpu:warn=10,crit=20',
		"--check", 'io_in:warn=:10,crit=20:,perf=asdf',
		"-C", 'io_out:warn=10,crit=20:30,perf=0',
		"-C", 'mem:warn=10,crit=~:20,perf=no',
		"-C", 'perf:warn,crit,perf',
	]
);

{
	my $expect = <<EOF
Unknown option: v
26-options.t -h|--help
26-options.t
EOF
;
	ok_plugin_help($expect, "Ensure lack of -v", sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN(name => "OPTION", summary => "Test option deletion");
		START default => 'done';
		DONE;
	}, ["-v"]);
}

{
	my $expect = <<EOF
Unknown option: V
26-options.t -h|--help
26-options.t
EOF
;
	ok_plugin_help($expect, "Ensure lack of -V", sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN(name => "OPTION", summary => "Test option deletion");
		START default => 'done';
		DONE;
	}, ["-V"]);
}

{
	my $expect = <<EOF
Unknown option: verbose
26-options.t -h|--help
26-options.t
EOF
;
	ok_plugin_help($expect, "Ensure lack of --verbose", sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN(name => "OPTION", summary => "Test option deletion");
		START default => 'done';
		DONE;
	}, ["--verbose"]);
}

{
	my $expect = <<EOF
Unknown option: version
26-options.t -h|--help
26-options.t
EOF
;
	ok_plugin_help($expect, "Ensure lack of --version", sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN(name => "OPTION", summary => "Test option deletion");
		START default => 'done';
		DONE;
	}, ["--version"]);
}

{
	my $expect = <<EOF
Unknown option: extra-opts
26-options.t -h|--help
26-options.t
EOF
;
	ok_plugin_help($expect, "Ensure lack of --extra-opts", sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN(name => "OPTION", summary => "Test option deletion");
		START default => 'done';
		DONE;
	}, ["--extra-opts"]);
}

{
	my $expect = <<EOF
Invalid sub-option: --check=cpu:myfakesubopt
Sub-option keys must be one of '(warn|crit|perf)'.
26-options.t -h|--help
26-options.t
EOF
;
	ok_plugin_help($expect, "Ensure % parses suboptions properly", sub {
		use Synacor::SynaMon::Plugin qw(:easy);
		PLUGIN(name => "OPTION", summary => "Test % subkey parsing");
		OPTION('check|C=%',
			help => '% supports only warn,crit,perf keys');
		START default => 'done';
		DONE;
	}, ['-C', 'mem:warn=1,crit=2,', '-C' ,'cpu:myfakesubopt,warn=1']);
}

done_testing;
