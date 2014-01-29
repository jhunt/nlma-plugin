#!perl

BEGIN {
	# don't try this at home, kids
	my $__TIME_snapshot = time;
	my $__TIME_override = undef;
	*CORE::GLOBAL::time = sub { $__TIME_override || $__TIME_snapshot };
	*CORE::GLOBAL::time = sub { $__TIME_override };
	sub OVERRIDE_TIME { $__TIME_override = shift; }
}

use Test::More;
require "t/common.pl";

ok_plugin(0, "OVERTIME OK - time is now 123456789", undef, "Time Overrides", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "OVERTIME"; START;

	OVERRIDE_TIME(123456789);
	OK "time is now ".time();

	DONE;
});

my $JAN23_9AM = 1390485600;
my $JAN23_MID = 1390453200;

# there is no sa24 file
my $JAN24_MID = 1390539600;
# there is no sa25 file
my $JAN25_MID = 1390626000;

my $LOGS;
my $OS = PLATFORM();
if ($OS eq 'centos4') { ############################################### CentOS 4.x

      ######  ######## ##    ## ########  #######   ######  ##
     ##    ## ##       ###   ##    ##    ##     ## ##    ## ##    ##
     ##       ##       ####  ##    ##    ##     ## ##       ##    ##
     ##       ######   ## ## ##    ##    ##     ##  ######  ##    ##
     ##       ##       ##  ####    ##    ##     ##       ## #########
     ##    ## ##       ##   ###    ##    ##     ## ##    ##       ##
      ######  ######## ##    ##    ##     #######   ######        ##

	$LOGS = "t/data/sar/centos4";

	ok_plugin(0, "SAR OK - rd_sec/s: 0 tps: 0.25 wr_sec/s: 3.48",
		undef, "SAR -d works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-d", samples => 1,
			                    logs => $LOGS;

			my $dev = $sar->{'dev8-6'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - rd_sec/s: 0.00 tps: 0.24 wr_sec/s: 3.67",
		undef, "SAR -d works (15 samples)", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-d", samples => 15,
			                    logs => $LOGS;

			my $dev = $sar->{'dev8-6'};
			OK sprintf("%s: %0.2f", $_, $dev->{$_}) for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - rd_sec/s: 0.00 tps: 0.23 wr_sec/s: 3.41",
		undef, "SAR -d works (midnight rollover)", sub {

			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_MID + 300; # 5 after midnight
			my $sar = SAR "-d", samples => 10, # 10 minutes worth of data
			                    logs => $LOGS;

			my $dev = $sar->{'dev8-6'};
			OK sprintf("%s: %0.2f", $_, $dev->{$_}) for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - rxbyt/s: 2733.14 rxcmp/s: 0 rxmcst/s: 0 rxpck/s: 45.37 txbyt/s: 496.9 txcmp/s: 0 txpck/s: 1.04",
		undef, "SAR -n DEV works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-n DEV", samples => 1,
				                    logs => $LOGS;

			my $dev = $sar->{'eth0'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - coll/s: 0 rxdrop/s: 0 rxerr/s: 0 rxfifo/s: 0 rxfram/s: 0 txcarr/s: 0 txdrop/s: 0 txerr/s: 0 txfifo/s: 0",
		undef, "SAR -n EDEV works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-n EDEV", samples => 1,
									 logs => $LOGS;

			my $dev = $sar->{'eth0'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - %idle: 96.45 %iowait: 0.27 %nice: 0 %system: 1.2 %user: 2.07",
		undef, "SAR -u -P ALL works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-u -P ALL", samples => 1,
									   logs => $LOGS;

			my $dev = $sar->{'all'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - %dquot-sz: 0 %rtsig-sz: 0 %super-sz: 0 dentunusd: 13308 dquot-sz: 0 file-sz: 1600 inode-sz: 5276 rtsig-sz: 0 super-sz: 0",
		undef, "SAR -v works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-v", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - bread/s: 1.07 bwrtn/s: 142.14 rtps: 0.15 tps: 1.47 wtps: 1.32",
		undef, "SAR -b works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-b", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - ldavg-1: 0.06 ldavg-15: 0.06 ldavg-5: 0.05 plist-sz: 141 runq-sz: 2",
		undef, "SAR -q works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-q", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - fault/s: 830.37 majflt/s: 0 pgpgin/s: 0.54 pgpgout/s: 71.07",
		undef, "SAR -B works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-B", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - %memused: 33.83 %swpused: 6.95 kbbuffers: 43804 kbcached: 134304 kbmemfree: 684568 kbmemused: 349928 kbswpcad: 97492 kbswpfree: 1950660 kbswpused: 145780",
		undef, "SAR -r works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-r", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - bufpg/s: 0.42 campg/s: 16.98 frmpg/s: -16.6",
		undef, "SAR -R works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-R", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - pswpin/s: 0 pswpout/s: 0",
		undef, "SAR -W works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-W", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - no data",
		undef, "SAR won't die on no data file at midnight file", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN24_MID;
			my $sar = SAR "-d", samples => 1,
			                    logs => $LOGS;

			my $dev = $sar->{'dev8-6'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(2, "SAR CRITICAL - No sar data found via /usr/bin/sadf -- -d",
		undef, "SAR dies on no data", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN25_MID;
			my $sar = SAR "-d", samples => 15,
			                    logs => $LOGS;

			OK "no bail!";
			DONE;
	});

} elsif ($OS eq 'centos5') { ########################################## CentOS 5.x

     ######  ######## ##    ## ########  #######   ######  ########
    ##    ## ##       ###   ##    ##    ##     ## ##    ## ##
    ##       ##       ####  ##    ##    ##     ## ##       ##
    ##       ######   ## ## ##    ##    ##     ##  ######  #######
    ##       ##       ##  ####    ##    ##     ##       ##       ##
    ##    ## ##       ##   ###    ##    ##     ## ##    ## ##    ##
     ######  ######## ##    ##    ##     #######   ######   ######

	$LOGS = "t/data/sar/centos5";

	ok_plugin(0, "SAR OK - %util: 0.69 avgqu-sz: 0.02 avgrq-sz: 8 await: 1.58 rd_sec/s: 2.94 svctm: 0.63 tps: 10.9 wr_sec/s: 84.24",
		undef, "SAR -d works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-d", samples => 1,
			                    logs => $LOGS;

			my $dev = $sar->{'dev253-1'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - %util: 0.31 avgqu-sz: 0.23 avgrq-sz: 8.00 await: 13.38 rd_sec/s: 0.28 svctm: 0.50 tps: 5.64 wr_sec/s: 44.80",
		undef, "SAR -d works (15 samples)", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-d", samples => 15,
			                    logs => $LOGS;

			my $dev = $sar->{'dev253-1'};
			OK sprintf("%s: %0.2f", $_, $dev->{$_}) for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - %util: 0.38 avgqu-sz: 0.34 avgrq-sz: 8.00 await: 18.79 rd_sec/s: 0.43 svctm: 0.55 tps: 6.32 wr_sec/s: 50.15",
		undef, "SAR -d works (midnight rollover)", sub {

			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_MID + 300; # 5 after midnight
			my $sar = SAR "-d", samples => 10, # 10 minutes worth of data
			                    logs => $LOGS;

			my $dev = $sar->{'dev253-1'};
			OK sprintf("%s: %0.2f", $_, $dev->{$_}) for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - rxbyt/s: 3281.8 rxcmp/s: 0 rxmcst/s: 0 rxpck/s: 49.76 txbyt/s: 1854.09 txcmp/s: 0 txpck/s: 4.45",
		undef, "SAR -n DEV works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-n DEV", samples => 1,
				                    logs => $LOGS;

			my $dev = $sar->{'eth0'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - coll/s: 0 rxdrop/s: 0 rxerr/s: 0 rxfifo/s: 0 rxfram/s: 0 txcarr/s: 0 txdrop/s: 0 txerr/s: 0 txfifo/s: 0",
		undef, "SAR -n EDEV works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-n EDEV", samples => 1,
									 logs => $LOGS;

			my $dev = $sar->{'eth0'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - %idle: 93.48 %iowait: 0.55 %nice: 0 %steal: 0 %system: 0.75 %user: 5.21",
		undef, "SAR -u -P ALL works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-u -P ALL", samples => 1,
									   logs => $LOGS;

			my $dev = $sar->{'all'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(0, "SAR OK - %dquot-sz: 0 %rtsig-sz: 0 %super-sz: 0 dentunusd: 56585 dquot-sz: 0 file-sz: 2040 inode-sz: 23969 rtsig-sz: 0 super-sz: 0",
		undef, "SAR -v works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-v", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - bread/s: 8.83 bwrtn/s: 284.81 rtps: 1.1 tps: 29.62 wtps: 28.51",
		undef, "SAR -b works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-b", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - ldavg-1: 0.04 ldavg-15: 0.01 ldavg-5: 0.07 plist-sz: 190 runq-sz: 2",
		undef, "SAR -q works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-q", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - fault/s: 1761.62 majflt/s: 0 pgpgin/s: 1.47 pgpgout/s: 47.47",
		undef, "SAR -B works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-B", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - %memused: 72.03 %swpused: 19.1 kbbuffers: 65824 kbcached: 213132 kbmemfree: 287220 kbmemused: 739668 kbswpcad: 94172 kbswpfree: 1624564 kbswpused: 383552",
		undef, "SAR -r works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-r", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - bufpg/s: 0.5 campg/s: 0.52 frmpg/s: -2.62",
		undef, "SAR -R works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-R", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - pswpin/s: 0 pswpout/s: 0",
		undef, "SAR -W works", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN23_9AM;
			my $sar = SAR "-W", samples => 1,
			                    logs => $LOGS;

			OK "$_: $sar->{$_}" for sort keys %$sar;
			DONE;
	});

	ok_plugin(0, "SAR OK - %util: 0.69 avgqu-sz: 0.02 avgrq-sz: 8 await: 1.58 rd_sec/s: 2.94 svctm: 0.63 tps: 10.9 wr_sec/s: 84.24",
		undef, "SAR won't die on no data file at midnight", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN24_MID;
			my $sar = SAR "-d", samples => 1,
			                    logs => $LOGS;

			my $dev = $sar->{'dev253-1'};
			OK "$_: $dev->{$_}" for sort keys %$dev;
			DONE;
	});

	ok_plugin(2, "SAR CRITICAL - No sar data found via /usr/bin/sadf -- -d",
		undef, "SAR dies on no data", sub {
			use Synacor::SynaMon::Plugin qw(:easy);
			PLUGIN name => "SAR"; START;

			OVERRIDE_TIME $JAN25_MID;
			my $sar = SAR "-d", samples => 15,
			                    logs => $LOGS;

			OK "no bail!";
			DONE;
	});

} else { ############################################################## UNKNOWN
	diag "Skipping SAR tests; unhandled platform $OS detected";
}

done_testing;
