#!perl

use Test::More;
use Test::MockModule;
use Test::Deep;
require "t/common.pl";

qx(rm -rf t/tmp/*);
system "rrdtool create t/tmp/test.rrd --step 60  --start n-1yr DS:datum:GAUGE:1800:U:U RRA:AVERAGE:0.5:1:43200 RRA:AVERAGE:0.5:60:9480 RRA:MIN:0.5:60:9480 RRA:MAX:0.5:60:9480";

# Verify default settings
ok_plugin(0, "RRD OK", undef, "Default RRD settings are set", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "rrd";

	my $settings = $NLMA::Plugin::Easy::plugin->{settings};

	CRITICAL "Bad default rrdtool setting: '$settings->{rrdtool}'."
		unless $settings->{rrdtool} eq "/usr/bin/rrdtool";
	CRITICAL "Bad default rrds setting: '$settings->{rrds}'."
		unless $settings->{rrds} eq "/srv/monitor/rrd";
	CRITICAL "Bad default rrdcached setting: '$settings->{rrdcached}'."
		unless $settings->{rrdcached} eq "unix:/var/run/rrdcached/rrdcached.sock";
	CRITICAL "Bad default on_rrd_failure setting: '$settings->{on_rrd_failure}'."
		unless $settings->{on_rrd_failure} == 2;
	CRITICAL "Bad default bail_on_rrd_failure setting: '$settings->{bail_on_rrd_failure}'."
		unless $settings->{bail_on_rrd_failure} == 1;

	OK;
	DONE;
});

# Verify settings can be overridden
ok_plugin(0, "RRD OK", undef, "RRD settings can be overridden", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "rrd";

	my $settings = $NLMA::Plugin::Easy::plugin->{settings};

	SET rrdtool             => "t/tmp/rrdtool";
	SET rrds                => "t/tmp";
	SET rrdcached           => "unix:t/tmp/rrdcached.sock";
	SET on_rrd_failure      => "WARNING";
	SET bail_on_rrd_failure => 0;

	CRITICAL "Bad overridden rrdtool setting: '$settings->{rrdtool}'."
		unless $settings->{rrdtool} eq "t/tmp/rrdtool";
	CRITICAL "Bad overridden rrds setting: '$settings->{rrds}'."
		unless $settings->{rrds} eq "t/tmp";
	CRITICAL "Bad overridden rrdcached setting: '$settings->{rrdcached}'."
		unless $settings->{rrdcached} eq "unix:t/tmp/rrdcached.sock";
	CRITICAL "Bad overridden on_rrd_failure setting: '$settings->{on_rrd_failure}'."
		unless $settings->{on_rrd_failure} == 1;
	CRITICAL "Bad overridden rrd_on_fail_bail setting: '$settings->{bail_on_rrd_failure}'."
		unless $settings->{bail_on_rrd_failure} == 0;

	OK;
	DONE;
});

# Verify RRD works under nominal circumstances
ok_plugin(0, "RRD OK", undef, "RRD can fetch data", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "rrd";

	SET rrds      => "t/tmp";
	SET rrdcached => "unix:t/tmp/nosckethere.sock";

	my $data = RRD info => "test";
	CRITICAL "No data returned from RRD" unless $data;

	OK;
	DONE;
});

# Verify RRD calls set up the RRDCACHED_ADDRESS env variable
ok_plugin(0, "RRD OK", undef, "RRD sets RRDCACHED_ADDRESS environment variable", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "rrd";

	SET rrds      => "t/tmp";
	SET rrdcached => "unix:t/tmp/nosockethere.sock";

	RRD info => "test";
	CRITICAL "RRDCACHED_ADDRESS=$ENV{RRDCACHED_ADDRESS} - that's bad"
		unless $ENV{RRDCACHED_ADDRESS} eq "unix:t/tmp/nosockethere.sock";

	OK;
	DONE;
});

# Verify Multiple RRD calls don't cause problems. (RRDp will croak)
ok_plugin(0, "RRD OK", undef, "multiple RRD calls don't cause failure", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "rrd";

	SET rrds      => "t/tmp";
	SET rrdcached => "unix:t/tmp/nosckethere.sock";

	RRD info => "test";
	RRD info => "test";

	OK;
	DONE;
});

# Verify Errors are caught/handled appropriately
ok_plugin(2, "RRD CRITICAL - ERROR: opening 't/tmp/norrdhere.rrd': No such file or directory.",
	undef,
	"RRD errors are handled appropriately", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD info => "norrdhere";

		UNKNOWN "Shouldn't get here, as RRD will bail";
		DONE;
});

# Setting fail_bail = 0 allows scripts to continue
ok_plugin(2,
	"RRD CRITICAL - ERROR: opening 't/tmp/norrdhere.rrd': No such file or directory. Second message",
	undef, "RRD fail_bail = 0 allows continued execution", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds                => "t/tmp";
		SET bail_on_rrd_failure => 0;

		RRD info => "norrdhere";

		CRITICAL "Second message";
		DONE;
});

# Customizing on_failure affects status messages
ok_plugin(1, "RRD WARNING - ERROR: opening 't/tmp/norrdhere.rrd': No such file or directory.",
	undef, "RRD on_failure adjusts status properly", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds           => "t/tmp";
		SET on_rrd_failure => "WARNING";

		RRD info => "norrdhere";

		UNKNOWN "Shouldn't get here, as RRD will bail";
		DONE;
});

ok_plugin(0, "RRD OK", undef, "RRD info returns scalar ref data", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "rrd";

	SET rrds => "t/tmp";
	my $data = RRD info => "test";
	CRITICAL unless ref($data) eq "SCALAR";
	OK;

	DONE;
});

ok_plugin(0, "RRD OK",
	undef, "RRD create command", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";
		!-f "t/tmp/simple.rrd" or UNKNOWN "RRD already exists!";

		RRD create => "simple.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		-f "t/tmp/simple.rrd" or UNKNOWN "RRD not created! (-f)";
		OK;
		DONE;
});

ok_plugin(0, "RRD OK",
	undef, "RRD create handles missing parent directories", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";
		!-d "t/tmp/missing" or CRITICAL "parent dirs already exist!";

		RRD create => "missing/parent/dirs.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		-f "t/tmp/missing/parent/dirs.rrd" or UNKNOWN "RRD not created! (-f)";
		OK;
		DONE;
});

ok_plugin(2, "RRD CRITICAL - ERROR: you must define at least one Round Robin Archive.",
	undef, "RRD create handles bad definition", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD create => "baddef.rrd",
		              "DS:datum:GAUGE:1800:U:U"; # NO RRAs!
		-f "t/tmp/baddef.rrd" or UNKNOWN "RRD baddef.rrd created mistakenly";

		OK;
		DONE;
});

ok_plugin(2, "RRD CRITICAL - ERROR: creating '/root/test.rrd': Permission denied.",
	undef, "RRD create handles bad perms on destination", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		RRD create => "/root/test.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";
		-f "/root/test.rrd" or UNKNOWN "RRD /root/test.rrd created mistakenly";

		OK;
		DONE;
});

ok_plugin(2, "RRD CRITICAL - ERROR: creating 't/tmp/a.rrd/b.rrd': Not a directory.",
	undef, "RRD create handles ENOTDIR parent dirs", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD create => "a.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";
		-f "t/tmp/a.rrd" or UNKNOWN "RRD t/tmp/a.rrd NOT created";

		RRD create => "a.rrd/b.rrd", # a.rrd is ENOTDIR!
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";
		!-f "t/tmp/a.rrd/b.rrd" or UNKNOWN "RRD t/tmp/a.rrd/b.rrd created mistakenly";

		OK;
		DONE;
});

ok_plugin(3, "RRD UNKNOWN - RRD foobar.rrd already exists",
	undef, "RRD create handles pre-existing files", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD create => "foobar.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";
		-f "t/tmp/foobar.rrd" or UNKNOWN "RRD t/tmp/foobar.rrd NOT created";

		RRD create => "foobar.rrd",
		              { preexisting => "UNKNOWN" },
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		OK;
		DONE;
});

ok_plugin(0, "RRD OK",
	undef, "RRD create normally doesn't care about pre-existing files", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD create => "xyzzy.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		RRD create => "xyzzy.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		OK;
		DONE;
});

ok_plugin(1, "RRD WARNING - RRD foo/bar/quux.rrd already exists",
	undef, "RRD create can warn about pre-existing files", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD create => "foo/bar/quux.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		RRD create => "foo/bar/quux.rrd",
		              { preexisting => "WARN" },
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		OK;
		DONE;
});

ok_plugin(0, "RRD OK",
	undef, "RRD create can explicitly not care about pre-existing files", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD create => "foo/xyzzy.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		RRD create => "foo/xyzzy.rrd",
		              { preexisting => "ok" },
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		OK;
		DONE;
});

ok_plugin(2, "RRD CRITICAL - RRD default.rrd already exists",
	undef, "RRD create defaults to CRITICAL for unknown preexisting option", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "rrd";

		SET rrds => "t/tmp";

		RRD create => "default.rrd",
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		RRD create => "default.rrd",
		              { preexisting => "Fall Over And Die" },
		              "DS:datum:GAUGE:1800:U:U",
		              "RRA:AVERAGE:0.5:1:43200";

		OK;
		DONE;
});


my $rrd = Test::MockModule->new("RRDp");
$rrd->mock('cmd', sub (@) {} );
$rrd->mock('read', sub () {
	# NOTE: values in here are hand-crafted to test our number parsing regex, skipping non-numbers.
	my $str = <<EOF;
                          datum

1410381060: -1.340000000000e-40
1410381120: 13.003400000000e323
1410381240: +nan
1410381300: -nan
1410381360: 0.0000000000e00
1410381420: 340.443100000000e-00

EOF
	return \$str;
});
ok_plugin(0, "RRD_FETCH OK", undef, "RRD fetch returns expected datastructure", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "rrd_fetch";

	SET rrds => "t/tmp";
	my $data = RRD fetch => "rrd", qw/fake args/;
	CRITICAL "unexpected output from RRD fetch" unless eq_deeply $data, {
		1410381060 => -1.340000000000e-40,
		1410381120 => 13.003400000000e323,
		1410381240 => undef,
		1410381300 => undef,
		1410381360 => 0.0000000000e00,
		1410381420 => 340.443100000000e-00,
	};
	OK;

	DONE;
});

qx(rm -rf t/tmp/* t/tmp/.rrd);
done_testing;
