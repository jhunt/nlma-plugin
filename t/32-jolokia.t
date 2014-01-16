#!perl

use Test::More;
use Test::Fake::HTTPD;
use JSON;
use File::Slurp qw/read_file/;
require "t/common.pl";

###################################################################

ok_plugin(3, "JOLO UNKNOWN - Check appears to be broken; JOLOKIA_READ called before JOLOKIA_CONNECT", undef, "Jolokia call sequence tests", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_READ "java.lang:type=Memory";
	OK "looks like we forgot to bail on JOLOKIA_READ";
	DONE;
});

ok_plugin(3, "JOLO UNKNOWN - Check appears to be broken; JOLOKIA_SEARCH called before JOLOKIA_CONNECT", undef, "Jolokia call sequence tests", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_SEARCH qr/Match/;
	OK "looks like we forgot to bail on JOLOKIA_SEARCH";
	DONE;
});

###################################################################

my $HTTPD = run_http_server {
	my $req = shift;
	my $path = $req->uri;

	my $file;

	if ($path =~ m{/jolokia$}) {
		$file = "bad-idx";

	} elsif ($path =~ m{/jolokia/$}) {
		my $payload = decode_json($req->content);

		if (ref($payload) eq 'HASH' && $payload->{type} eq 'list') {
			$file = "list";

		} elsif (ref($payload) eq 'ARRAY') {
			$file = @$payload == 1 ? 'one' : 'multi';
		}
	}

	if (!$file) {
		return [
			400,
			[ 'Content-type' => 'application/json' ],
			[ 'Unknown test request!' ]
		];
	}

	return [
		200,
		[ 'Content-type' => 'application/json' ],
		[ read_file("t/data/jolokia/$file.out") ]
	];
};
$ENV{MONITOR_JOLOKIA_PROXY} = $HTTPD->endpoint;
$ENV{MONITOR_JOLOKIA_PROXY} =~ s|^http://||;
$ENV{MONITOR_JOLOKIA_PROXY} =~ s|/$||;
$ENV{MONITOR_CRED_STORE} = "t/data/jolokia/creds";

ok_plugin(0, "JOLO OK", undef, "Jolokia connection is ok", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT host => 'whatever',
	                port => 12345;
	OK;
	DONE;
});

ok_plugin(2, "JOLO CRITICAL - No 'host' specified for Jolokia/JMX connection", undef, "Need a 'host' for JOLOKIA_CONNECT", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT port => 12345;
	OK;
	DONE;
});

ok_plugin(2, "JOLO CRITICAL - No 'port' specified for Jolokia/JMX connection", undef, "Need a 'port' for JOLOKIA_CONNECT", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT host => 'whatever';
	OK;
	DONE;
});

ok_plugin(0, "JOLO OK", undef, "Missing 'host' is okay under ignore_jolokia_failures", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	SET ignore_jolokia_failures => 'yes';
	JOLOKIA_CONNECT port => 12345;
	OK;
	DONE;
});

ok_plugin(0, "JOLO OK", undef, "Missing 'port' is okay under ignore_jolokia_failures", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	SET ignore_jolokia_failures => 'yes';
	JOLOKIA_CONNECT host => 'whatever';
	OK;
	DONE;
});

ok_plugin(3, "JOLO UNKNOWN - Credentials not found for 'hahahahahah-i-dont-think-so'", undef, "JOLOKIA_CONNECT with bad creds keys", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	SET ignore_jolokia_failures => 'yes';
	JOLOKIA_CONNECT host  => 'whatever',
	                port  => 12345,
	                creds => 'hahahahahah-i-dont-think-so';
	OK;
	DONE;
});


ok_plugin(0, "JOLO OK - Found 63 beans", undef, "MBean search via JOLOKIA_SEARCH", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT host => 'whatever',
	                port => 12345;
	my @beans = JOLOKIA_SEARCH();
	OK "Found ".@beans." beans";
	DONE;
});

ok_plugin(0, "JOLO OK - Found 5 beans", undef, "MBean search with regex", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT host => 'whatever',
	                port => 12345;
	my @beans = JOLOKIA_SEARCH('type=MemoryPool');
	OK "Found ".@beans." beans";
	DONE;
});

ok_plugin(0, "JOLO OK - Found 0 beans", undef, "MBean search with no match", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT host => 'whatever',
	                port => 12345;
	my @beans = JOLOKIA_SEARCH('PerlRulesJavaDrools');
	OK "Found ".@beans." beans";
	DONE;
});

ok_plugin(0, "JOLO OK", undef, "Retrieve data via JOLOKIA_READ", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT host => 'whatever',
	                port => 12345;

	# doesn't matter *what* the bean is since our test server dumps the same
	# response for any 'read' request for only one bean
	my $data = JOLOKIA_READ('a-bean');

	my $MBEAN = 'com.synacor.primetime.services.assets:name=com.synacor.primetime.services.assets.AssetBrowseService,type=AssetBrowseService';

	CRITICAL "Missing '$MBEAN' bean"
		unless $data->{$MBEAN};
	CRITICAL "Unable to parse MBean composite value!"
		unless $data->{$MBEAN}{Health}{checks}{genreTest}{status} eq 'OK';
	OK;
	DONE;
});

ok_plugin(0, "JOLO OK", undef, "Retrieve MULTIPLE via JOLOKIA_READ", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "JOLO";
	START;
	JOLOKIA_CONNECT host => 'whatever',
	                port => 12345;

	# doesn't matter *what* the beans are since our test server dumps the same
	# response for any 'read' request for more than one bean
	my $data = JOLOKIA_READ('bean1', 'bean2');

	CRITICAL "java.lang:type=OperatingSystem.Arch not found!"
		unless $data->{'java.lang:type=OperatingSystem'}{Arch} eq 'amd64';
	CRITICAL "java.lang:type=Runtime.SpecName not found!"
		unless $data->{'java.lang:type=Runtime'}{'SpecName'} eq 'Java Virtual Machine Specification';
	OK;
	DONE;
});

###################################################################

done_testing;
