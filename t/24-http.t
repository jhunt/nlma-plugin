#!perl

use Test::More;
require "t/common.pl";

BEGIN {
	eval "use Test::Fake::HTTPD";
	plan skip_all => "Test::Fake::HTTPD required for testing HTTP primitives"
		if $@;
};

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
		my $cookie = $req->header('Cookie');
		if ($cookie and $cookie =~ /testcookie=(\S+);?/) {
			$message .= " with testcookie=$1";
		}

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

	} elsif ($path =~ m@^/cookie/@) {
                $path =~ s@^/cookie/@@;                                                                                      #  Yeah, sorry, but if we reach this time, you can punch me in the face..
                return [ 302, [ 'Location' => '/thing/set-cookie', 'set-cookie' => "testcookie=$path; Domain=127.0.0.1; Path=/; Expires=Wed, 13-Jan-2021 22:23:01 GMT;"], []];
	} else {
		return [ 404, [ 'Content-type' => 'text/html' ], [ "$path: not found!" ] ];
	}
};

###################################################################
# HTTP requests

ok_plugin(0, "GET OK - no worries", undef, "basic HTTP GET is OK", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => 'GET';
	START default => 'no worries';
	HTTP_GET $httpd->endpoint."/thing/doo-dad";
	DONE;
});

ok_plugin(0, "HTTP OK - request handler", undef, "_REQUEST delegates properly", sub {
	use NLMA::Plugin qw(:easy);
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
	use NLMA::Plugin qw(:easy);
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

ok_plugin(0, "HTTP OK - handle lack of encoding header properly", undef, "Encoding", sub {
	use NLMA::Plugin qw(:ewasy);
	PLUGIN name => 'HTTP';
	START  default => 'handle lack of encoding header properly';

	my $url = $httpd->endpoint."/thing";
	my ($res, $data);
	{   # override decoded_content to return undef, simulating no encoding specified on Cent-6
		no warnings 'redefine';
		*HTTP::Message::decoded_content = sub { undef };
		($res, $data) = HTTP_REQUEST GET => "$url/unencoded-content";
	}
	$data eq "I see you GET-ing that unencoded-content!" or CRITICAL "Bad GET response: $data.";
	! defined $res->decoded_content or CRITICAL "decoded_content() did not return undef - test invalid.";
	$data eq $res->content or CRITICAL "HTTP_REQUEST returned content() when decoded_content() returns undef";

	DONE;
});

ok_plugin(0, "HTTP OK - JSON", undef, "JSON HTTP ops", sub {
	use NLMA::Plugin qw(:easy);
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

ok_plugin(3, "HTTP UNKNOWN - HTTP_PUT called incorrectly; %DOLLAR%data not a scalar reference", undef, "PUT with bad data ref", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "oops... fell through to OK";

	HTTP_PUT $httpd->endpoint."/thing/whatsit", [qw(array ref here)];
	DONE;
});

ok_plugin(3, "HTTP UNKNOWN - HTTP_POST called incorrectly; %DOLLAR%data not a scalar reference", undef, "POST with bad data ref", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "oops... fell through to OK";

	HTTP_POST $httpd->endpoint."/thing/whatsit", [qw(array ref here)];
	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "POST with data", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_POST $httpd->endpoint."/data/post-bucket", "{data:'yes!'}";
	$data eq "You tried to POST {data:'yes!'} to post-bucket" or CRITICAL "Bad POST Response: '$data'";

	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "PUT with data", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_PUT $httpd->endpoint."/data/put-bucket", "{data:'yes!'}";
	$data eq "You tried to PUT {data:'yes!'} to put-bucket" or CRITICAL "Bad PUT Response: '$data'";

	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "POST without data", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_POST $httpd->endpoint."/data/post-bucket", undef;
	$data eq "You tried to POST _nothing_ to post-bucket" or CRITICAL "Bad POST Response: '$data'";

	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "PUT without data", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;

	(undef, $data) = HTTP_PUT $httpd->endpoint."/data/put-bucket", undef;
	$data eq "You tried to PUT _nothing_ to put-bucket" or CRITICAL "Bad PUT Response: '$data'";

	DONE;
});

ok_plugin(0, "HTTP OK - looks good", undef, "Redirect URI sets cookie, that is used on redirection, and next request", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "HTTP";
	START default => "looks good";

	my $data;
	(undef, $data) = HTTP_GET($httpd->endpoint."/cookie/testvalue1");
	DUMP($data);
	$data eq "I see you GET-ing that set-cookie with testcookie=testvalue1!" or CRITICAL "Did not see cookie in response! Got $data";
	(undef, $data) = HTTP_GET($httpd->endpoint."/thing/cookiechecker");
	DUMP($data);
	$data eq "I see you GET-ing that cookiechecker with testcookie=testvalue1!" or CRITICAL "Did not see cookie in second response! Got $data";
	DONE;
});

subtest "Persistent cookies" => sub {
	system "cp t/data/mon_cookietest.cookies t/tmp/mon_cookietest.cookies";
	ok -f "t/tmp/mon_cookietest.cookies";

	ok_plugin(0, "HTTP OK", undef, "persistent cookie jar loads in a cookie, uses it, and stores properly", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "HTTP";
		START;

		$ENV{MONITOR_STATE_FILE_DIR} = "t/tmp";
		MECH({ cookie_jar => "cookietest" });
		my $data;
		(undef, $data) = HTTP_GET($httpd->endpoint."/thing/cookiechecker");
		$data eq "I see you GET-ing that cookiechecker with testcookie=testpersistence!"
			or CRITICAL "Did not get cookie from cookiejar.";

		(undef, $data) = HTTP_GET($httpd->endpoint."/cookie/persistme");
		$data eq "I see you GET-ing that set-cookie with testcookie=persistme!"
			or CRITICAL "Did not set cookie into cookiejar.";

		OK;
		DONE;
	});

	open my $fh, "t/tmp/mon_cookietest.cookies";
	local $/; my $data = <$fh>;
	close $fh;

	is $data, <<EOF, "Cookie file is correct";
#LWP-Cookies-1.0
Set-Cookie3: testcookie=persistme; path="/"; domain=127.0.0.1; path_spec; expires="2021-01-13 22:23:01Z"; version=0
EOF

	unlink "t/tmp/mon_cookietest.cookies";

	ok ! -f "t/tmp/mon_cookietest.cookies", "Cookiejar file doesn't exist";
	ok_plugin(0, "HTTP OK", undef, "persistent cookie jar is created if doesnt exist", sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "HTTP";
		START;

		$ENV{MONITOR_STATE_FILE_DIR} = "t/tmp";
		MECH({ cookie_jar => "cookietest" });

		my $data;
		(undef, $data) = HTTP_GET($httpd->endpoint."/cookie/persistme");
		$data eq "I see you GET-ing that set-cookie with testcookie=persistme!"
			or CRITICAL "Did not set cookie into cookiejar.";

		OK;
		DONE;
	});

	ok -f "t/tmp/mon_cookietest.cookies", "Cookiejar was created by the plugin framework";
	unlink "t/tmp/mon_cookietest.cookies";
};

done_testing;
