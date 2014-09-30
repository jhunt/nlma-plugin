#!perl

use strict;
use Test::More;
use Test::Deep;
require "t/common.pl";

my $html = <<'EOF';
<html>
<head><title>Test Synthetic Monitoring Plugin</title></head>
<body><div id="main">This is only a test.</div></body>
</html>
EOF

my $httpd = Test::Fake::HTTPD->new(timeout => 20);
$httpd->run(sub {
	my $req = shift;
	system "touch /tmp/returningcontent";
	return [ 200, [ 'Content-type' => 'text/html' ], [ $html ] ];
});

ok_plugin_exec(0,
	"SYNTHETIC OK",
	undef,
	"Basic fuzz test of synthetic plugins on OK states",
	<<'EOF',
use Synacor::SynaMon::Plugin qw/:synthetic/;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
CRITICAL "Unable to locate '#main'"
	unless WAIT_FOR_IT sub { my $v = VISIBLE "#main"; return $v && $v ne 'false'; };
OK;
DONE;
EOF
	[ "--url", $httpd->host_port ],
);
ok_plugin_exec(1,
	"SYNTHETIC WARNING - Unable to locate '#notmain'",
	undef,
	"Basic fuzz test of synthetic plugins on WARNING states",
	<<'EOF',
use Synacor::SynaMon::Plugin qw/:synthetic/;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
WARNING "Unable to locate '#notmain'"
	unless WAIT_FOR_IT sub { my $v = VISIBLE "#notmain"; return $v && $v ne 'false'; };
OK;
DONE;
EOF
	[ "--url", $httpd->host_port ],
);
ok_plugin_exec(2,
	"SYNTHETIC CRITICAL - Unable to locate '#notmain'",
	undef,
	"Basic fuzz test of synthetic plugins on CRITICAL states",
	<<'EOF',
use Synacor::SynaMon::Plugin qw/:synthetic/;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
CRITICAL "Unable to locate '#notmain'"
	unless WAIT_FOR_IT sub { my $v = VISIBLE "#notmain"; return $v && $v ne 'false'; };
OK;
DONE;
EOF
	[ "--url", $httpd->host_port ],
);
ok_plugin_exec(3,
	"SYNTHETIC UNKNOWN - Unable to locate '#notmain'",
	undef,
	"Basic fuzz test of synthetic plugins on UNKNOWN states",
	<<'EOF',
use Synacor::SynaMon::Plugin qw/:synthetic/;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
UNKNOWN "Unable to locate '#notmain'"
	unless WAIT_FOR_IT sub { my $v = VISIBLE "#notmain"; return $v && $v ne 'false'; };
OK;
DONE;
EOF
	[ "--url", $httpd->host_port ],
);
ok_plugin_exec(0,
	"SYNTHETIC OK",
	undef,
	"Basic fuzz test of synthetic plugins on BAIL OK states",
	<<'EOF',
use Synacor::SynaMon::Plugin qw/:synthetic/;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
BAIL OK
	if WAIT_FOR_IT sub { my $v = VISIBLE "#main"; return $v && $v ne 'false'; };
CRITICAL "Second message shouldn't fire";
DONE;
EOF
	[ "--url", $httpd->host_port ],
);
ok_plugin_exec(1,
	"SYNTHETIC WARNING - Unable to locate '#notmain'",
	undef,
	"Basic fuzz test of synthetic plugins on BAIL WARNING states",
	<<'EOF',
use Synacor::SynaMon::Plugin qw/:synthetic/;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
BAIL WARNING "Unable to locate '#notmain'"
	unless WAIT_FOR_IT sub { my $v = VISIBLE "#notmain"; return $v && $v ne 'false'; };
CRITICAL "Second message shouldn't fire";
DONE;
EOF
	[ "--url", $httpd->host_port ],
);
ok_plugin_exec(2,
	"SYNTHETIC CRITICAL - Unable to locate '#notmain'",
	undef,
	"Basic fuzz test of synthetic plugins on BAIL CRITICAL states",
	<<'EOF',
use Synacor::SynaMon::Plugin qw/:synthetic/;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
BAIL CRITICAL "Unable to locate '#notmain'"
	unless WAIT_FOR_IT sub { my $v = VISIBLE "#notmain"; return $v && $v ne 'false'; };
CRITICAL "Second message shouldn't fire";
DONE;
EOF
	[ "--url", $httpd->host_port ],
);
ok_plugin_exec(2,
	"SYNTHETIC CRITICAL - Bailing out",
	undef,
	"Basic fuzz test of synthetic plugins that prematurely exit",
	<<'EOF',
use Synacor::SynaMon::Plugin qw(:synthetic);
our $MASTER_PID = $$;
PLUGIN name => "SYNTHETIC";
START_SYNTHETIC;
BAIL CRITICAL "Bailing out";
EOF
	[ "--url", $httpd->host_port ],
);

done_testing;
