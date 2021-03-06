#!perl

use Test::More;
require "t/common.pl";

###################################################################
# option support

ok_plugin(3, "OPTION UNKNOWN - Option spec drops%PIPE%D=s conflicts with built-in debug%PIPE%D option", undef, "override -D", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "drops|D=s";
	START default => "good";
	DONE;
});

ok_plugin(3, "OPTION UNKNOWN - Option spec debug conflicts with built-in debug%PIPE%D option", undef, "override --debug", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "debug";
	START default => "good";
	DONE;
});

ok_plugin(3, "OPTION UNKNOWN - Option spec host%PIPE%h conflicts with built-in help%PIPE%h option", undef, "override -h", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "host|h", help => 'host to connect to';
	START default => "good";
	DONE;
});

ok_plugin(3, "OPTION UNKNOWN - Option spec usage%PIPE%U conflicts with built-in usage%PIPE%? option", undef, "override -h", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "usage|U", help => 'usage';
	START default => "good";
	DONE;
});

ok_plugin(3, "OPTION UNKNOWN - Option spec what%PIPE%? conflicts with built-in usage%PIPE%? option", undef, "override -h", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "what|?", help => 'what???';
	START default => "good";
	DONE;
});

ok_plugin(3, "OPTION UNKNOWN - Option spec noop conflicts with built-in noop option", undef, "override --noop", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "noop";
	START default => "good";
	DONE;
});

ok_plugin(3, "OPTION UNKNOWN - Option spec noperf conflicts with built-in noperf option", undef, "override --noperf", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "OPTION";
	OPTION "noperf";
	START default => "good";
	DONE;
});

ok_plugin(0, "OPTION OK - done", undef, "option processing", sub {
	use NLMA::Plugin qw(:easy);
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
			fd_pct   => { warn => undef, crit => undef,   perf => 'fd_pct'},
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
		"-C", 'fd_pct',
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
		use NLMA::Plugin qw(:easy);
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
		use NLMA::Plugin qw(:easy);
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
		use NLMA::Plugin qw(:easy);
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
		use NLMA::Plugin qw(:easy);
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
		use NLMA::Plugin qw(:easy);
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
		use NLMA::Plugin qw(:easy);
		PLUGIN(name => "OPTION", summary => "Test % subkey parsing");
		OPTION('check|C=%',
			help => '% supports only warn,crit,perf keys');
		START default => 'done';
		DONE;
	}, ['-C', 'mem:warn=1,crit=2,', '-C' ,'cpu:myfakesubopt,warn=1']);
}

done_testing;
