#!perl

use Test::More;
do "t/common.pl";

eval "use Test::Fake::HTTPD";
plan skip_all => "Test::Fake::HTTPD required for testing HTTP primitives"
	if $@;

use Test::Fake::HTTPD;
use JSON;

plan skip_all => 'set TEST_ALL to enable HTTP primitive tests' unless TEST_ALL();

## Run a local HTTPD Server
my $httpd = run_http_server {
	my $req = shift;

	my $path = $req->uri;
	if ($path =~ m@^/thing/@) {
		# Incrementally build up a tracer message, based on requested
		# path, method, and headers.  Something like:
		#   "I see you GET-ing that url/space as text/html!"
		my $message = 'I see you '.$req->method.'-ing that ';

		$path =~ s@^/thing/@@;
		$message .= $path;

		my $type = $req->header('Accept');
		if ($type) {
			$message .= " as $type";
		}
		$message .= "!";

		if ($type and $type eq 'application/json') {
			$message = encode_json({m => $message});
		} else {
			$type = 'text/plain';
		}

		return [ 200, [ 'Content-type' => $type ], [ $message ] ];

	} elsif ($path =~ m@^/data/@) {
		$path =~ s@^/data/@@;
		my $content = $req->content || "_nothing_";
		my $message = 'You tried to '.$req->method." $content to $path";
		return [ 200, [ 'Content-type' => 'text/html' ], [ $message ] ];

	} else {
		return [ 404, [ 'Content-type' => 'text/html' ], [ "$path: not found!" ] ];
	}
};

###################################################################
# HTTP requests

ok_plugin(0, "GET OK - no worries", undef, "basic HTTP GET is OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'GET';
	START default => 'no worries';
	HTTP_GET $httpd->endpoint."/thing/doo-dad";
	DONE;
});

ok_plugin(0, "HTTP OK - request handler", undef, "_REQUEST delegates properly", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'HTTP';
	START default => 'request handler';

	my $url = $httpd->endpoint."/thing";
	my $data;

	(undef, $data) = HTTP_REQUEST GET => "$url/doo-dad";
	$data eq "I see you GET-ing that doo-dad!" or CRITICAL "Bad GET response: $data";

	(undef, $data) = HTTP_REQUEST PUT => "$url/whatchamacallit", "data=here";
	$data eq "I see you PUT-ing that whatchamacallit!" or CRITICAL "Bad PUT response: $data";

	(undef, $data) = HTTP_REQUEST POST => "$url/doohickey", "data=here";
	$data eq "I see you POST-ing that doohickey!" or CRITICAL "Bad POST response: $data";

	DONE;
});

ok_plugin(0, "HTTP OK - right response", undef, "Basic HTTP ops", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'HTTP';
	START default => 'right response';

	my $url = $httpd->endpoint."/thing";
	my $data;

	(undef, $data) = HTTP_GET "$url/doo-dad";
	$data eq "I see you GET-ing that doo-dad!" or CRITICAL "Bad GET response: $data";

	(undef, $data) = HTTP_PUT "$url/whatchamacallit", "data=here";
	$data eq "I see you PUT-ing that whatchamacallit!" or CRITICAL "Bad PUT response: $data";

	(undef, $data) = HTTP_POST "$url/doohickey", "data=here";
	$data eq "I see you POST-ing that doohickey!" or CRITICAL "Bad POST response: $data";

	DONE;
});

ok_plugin(0, "HTTP OK - JSON", undef, "JSON HTTP ops", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'HTTP';
	START default => 'JSON';

	my $url = $httpd->endpoint."/thing";
	my $headers = { Accept => 'application/json' };
	my $data;

	(undef, $data) = HTTP_GET "$url/doo-dad", $headers;
	$data eq '{"m":"I see you GET-ing that doo-dad as application/json!"}' or CRITICAL "Bad GET response: $data";

	(undef, $data) = HTTP_PUT "$url/whatchamacallit", "data=here", $headers;
	$data eq '{"m":"I see you PUT-ing that whatchamacallit as application/json!"}' or CRITICAL "Bad PUT response: $data";

	(undef, $data) = HTTP_POST "$url/doohickey", "data=here", $headers;
	$data eq '{"m":"I see you POST-ing that doohickey as application/json!"}' or CRITICAL "Bad POST response: $data";

	DONE;
});

ok_plugin(3, "HTTP UNKNOWN - HTTP_PUT called incorrectly; \$data not a scalar reference", undef, "PUT with bad data ref", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "oops... fell through to OK";

	HTTP_PUT $httpd->endpoint."/thing/whatsit", [qw(array ref here)];
	DONE;
});

ok_plugin(3, "HTTP UNKNOWN - HTTP_POST called incorrectly; \$data not a scalar reference", undef, "POST with bad data ref", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "oops... fell through to OK";

	HTTP_POST $httpd->endpoint."/thing/whatsit", [qw(array ref here)];
	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "POST with data", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_POST $httpd->endpoint."/data/post-bucket", "{data:'yes!'}";
	$data eq "You tried to POST {data:'yes!'} to post-bucket" or CRITICAL "Bad POST Response: '$data'";

	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "PUT with data", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_PUT $httpd->endpoint."/data/put-bucket", "{data:'yes!'}";
	$data eq "You tried to PUT {data:'yes!'} to put-bucket" or CRITICAL "Bad PUT Response: '$data'";

	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "POST without data", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_POST $httpd->endpoint."/data/post-bucket", undef;
	$data eq "You tried to POST _nothing_ to post-bucket" or CRITICAL "Bad POST Response: '$data'";

	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "PUT without data", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_PUT $httpd->endpoint."/data/put-bucket", undef;
	$data eq "You tried to PUT _nothing_ to put-bucket" or CRITICAL "Bad PUT Response: '$data'";

	DONE;
});

done_testing;
