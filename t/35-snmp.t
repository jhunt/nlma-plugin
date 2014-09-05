#!perl

use Test::More;
use Test::Deep;
use t::override_time;
require "t/common.pl";

###################################################################

my $plugin = Synacor::SynaMon::Plugin::Base->new;
isa_ok($plugin, 'Synacor::SynaMon::Plugin::Base');

###################################################################


ok_plugin(0, "SNMP OK - looks good", undef, "Basic SNMP usage", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	SNMP_SESSION '127.0.0.1', community => 'v7015e49'
		or BAIL(CRITICAL "Failed to connect to 127.0.0.1 via SNMP (UDP/161)");

	SNMP_GET '[sysName].0'
		or BAIL(CRITICAL "Unable to retrieve sysName.0 from 127.0.0.1");

	OK "looks good";
	DONE;
});

ok_plugin(1, "SNMP WARNING - connect failed", undef, "Failed SNMP connections", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	SNMP_SESSION '127.0.0.1',
	  community => 'no-way-jose',
	  port      => 17787,
	  timeout   => 1
		or BAIL(WARNING "connect failed");
	OK "succeeded unexpectedly";
	DONE;
});

ok_plugin(3, "SNMP UNKNOWN - Unknown MIB: SYNACOR-UNKNOWN-MIB", undef, "Unknown MIB", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SYNACOR-UNKNOWN-MIB';
	OK "looks good";
	DONE;
});

ok_plugin(0, "SNMP OK - sysName is 1.3.6.1.2.1.1.5", undef, "OID lookup", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	OK "sysName is ".OID('[sysName]');
	DONE;
});

ok_plugin(0, "SNMP OK - [sysName].0 is 1.3.6.1.2.1.1.5.0 [sysLocation].0 is 1.3.6.1.2.1.1.6.0", undef, "OIDS lookup", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	my @orig = qw/[sysName].0 [sysLocation].0/;
	my $oids = OIDS @orig;

	while (@orig) {
		my $n = shift @orig;
		my $i = shift @$oids;
		OK "$n is $i";
	}
	DONE;
});

ok_plugin(0, "SNMP OK - looks good", undef, "SNMP TREE usage", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	SNMP_SESSION '127.0.0.1', community => 'v7015e49'
		or BAIL(CRITICAL "Failed to connect to 127.0.0.1 via SNMP (UDP/161)");

	my $t = SNMP_TREE '[system]'
		or BAIL(CRITICAL "Unable to retrieve sysName.0 from 127.0.0.1");

	if (!$t->{'5.0'}) { # sysName.0
		CRITICAL "Didn't find OID system.5.0 (sysName.0) in output from SNMP_TREE";
		DUMP $t;
	} else {
		OK "looks good";
	}
	DONE;
});

ok_plugin(0, "SNMP OK - looks good", undef, "SNMP_TABLE usage", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	SNMP_MIB 'IF-MIB';

	SNMP_SESSION '127.0.0.1', community => 'v7015e49'
		or BAIL(CRITICAL "Failed to connect to 127.0.0.1 via SNMP (UDP/161)");

	my $t = SNMP_TABLE qw/ ifIndex ifMtu ifSpeed ifDescr /;
	DUMP $t;

	for (keys %$t) {
		my $if = $t->{$_};
		exists $if->{ifIndex} or CRITICAL "No ifIndex found for $_";
		exists $if->{ifMtu}   or CRITICAL "No ifMtu found for $_";
		exists $if->{ifSpeed} or CRITICAL "No ifSpeed found for $_";
		exists $if->{ifDescr} or CRITICAL "No ifDescr found for $_";

		!exists $if->{ifType} or CRITICAL "ifType found in $_, but should not be!";
	}

	OK "looks good";
	DONE;
});

ok_plugin(3, "SNMP UNKNOWN - SNMP::MIB::Compiler not installed; SNMP functionality disabled", undef, "SNMP::MIB::Compiler dependency", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	delete $INC{'SNMP/MIB/Compiler.pm'}; # don't try this at home, kids
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	OK "succeeded, against our best estimates";
	DONE;
});

ok_plugin(3, "SNMP UNKNOWN - Net::SNMP not installed; SNMP functionality disabled", undef, "Net::SNMP dependency", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	delete $INC{'Net/SNMP.pm'}; # don't try this at home, kids
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	OK "succeeded, against our best estimates";
	DONE;
});


ok_plugin(0, "SNMP OK - up up(1) ethernetCsmacd(6) down:down:down! 1/other literal string UNKNOWN UNKNOWN", undef, "ENUM / TC lookups", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_MIBS} = "t/data/mibs";
	PLUGIN name => 'SNMP';
	START;

	SNMP_MIB 'SNMPv2-MIB';
	SNMP_MIB 'IF-MIB';
	SNMP_MIB 'IANAifType-MIB';

	OK SNMP_ENUM(1, 'ifOperStatus');
	OK SNMP_ENUM(1, 'ifOperStatus', '%s(%i)');

	OK SNMP_TC(6, 'IANAifType', '%s(%i)');

	OK SNMP_ENUM(2, 'ifOperStatus', '%s:%s:%s!');

	OK SNMP_TC(1, 'IANAifType', '%i/%s');
	OK SNMP_TC(1, 'IANAifType', 'literal string');

	OK SNMP_TC(42, 'NOT-LOADED');
	OK SNMP_ENUM(42, 'NOT-LOADED');
	DONE;
});

END {
	system "rm -rf /var/tmp/mibc.cache";
}
done_testing;
