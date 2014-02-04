#!perl

use Test::More;
use Test::Deep;
use t::override_time;
require "t/common.pl";

###################################################################

my $plugin = Synacor::SynaMon::Plugin::Base->new;
isa_ok($plugin, 'Synacor::SynaMon::Plugin::Base');

###################################################################


ok_plugin(1, "RATE WARNING - Need a store file to get previous data", undef, "Calculate rate without params", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	CALC_RATE;
	OK "good";
	DONE;
});

ok_plugin(1, "RATE WARNING - Need data to parse", undef, "Calculate rate without stats", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	CALC_RATE store => 'rate_data';
	OK "good";
	DONE;
});

unlink "t/data/tmp/mon_dne_rate_data" if -f "t/data/tmp/mon_dne_rate_data";
ok_plugin(1, "RATE WARNING - No historic data found; rate calculation deferred", undef, "Calculate rate without previous data", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/tmp";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	CALC_RATE
		store => 'dne_rate_data',
		data => {'some_stat' => 'none' };
	OK "good";
	DONE;
});

ok_plugin(1, "RATE WARNING - Service restart detected (values reset to near-zero)", undef, "Check for rollover", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/c_rate";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	my $calculated = CALC_RATE
		store => 'rollover',
		data => {
			stat1 => 100,
			stat2 => 125,
			stat3 => 150
		};
	OK "good";
	DONE;
});

OVERRIDE_TIME 300;
ok_plugin(0, "RATE OK - stat1: 10 stat2: 10 stat3: 20", undef, "Default params", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/c_rate";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	my $calculated = CALC_RATE
		store => 'rollover',
		data => {
			stat1 => 100,
			stat2 => 200,
			stat3 => 300
		};
	OK "$_: $calculated->{$_}" for sort keys %$calculated;
	DONE;
});

ok_plugin(0, "RATE OK - stat1: 10", undef, "Default params, only want 1", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/c_rate";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	my $calculated = CALC_RATE
		store => 'rollover',
		want => [ 'stat1' ],
		data => {
			stat1 => 100,
			stat2 => 200,
			stat3 => 300
		};
	OK "$_: $calculated->{$_}" for sort keys %$calculated;
	DONE;
});

ok_plugin(0, "RATE OK - stat1: 10", undef, "Default params, only want 1, missing 1 stat", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/c_rate";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	my $calculated = CALC_RATE
		store => 'rollover',
		want => [ 'stat1' ],
		data => {
			stat1 => 100,
			stat3 => 300
		};
	OK "$_: $calculated->{$_}" for sort keys %$calculated;
	DONE;
});

ok_plugin(0, "RATE OK - stat2: 50", undef, "Default params, want 2, missing 1 stat", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/c_rate";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	my $calculated = CALC_RATE
		store => 'rollover',
		want => [ 'stat1', 'stat2' ],
		data => {
			stat2 => 400,
			stat3 => 300
		};
	OK "$_: $calculated->{$_}" for sort keys %$calculated;
	DONE;
});

ok_plugin(1, "RATE WARNING - Stale data detected; last sample was 5m ago", undef, "Check staleness", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_STATE_FILE_DIR} = "t/data/c_rate";
	$ENV{MONITOR_STATE_FILE_PREFIX} = "mon";
	PLUGIN name => 'rate';
	START;
	my $calculated = CALC_RATE
		store => 'rollover',
		want => 'stat1',
		stale => 100,
		data => {
			stat1 => 100,
			stat2 => 200,
			stat3 => 300
		};
	OK "$_: $calculated->{$_}" for sort keys %$calculated;
	DONE;
});

done_testing;
