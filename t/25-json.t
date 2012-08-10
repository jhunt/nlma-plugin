#!perl

use Test::More;
do "t/common.pl";

###################################################################
# JSON decoding

ok_plugin(0, "JSON OK - decoded normal", undef, "basic JSON decoding", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'JSON';
	START default => 'decoded normal';

	my $json = '{"one":1,"two":2}';
	my $obj  = JSON_DECODE($json);

	$obj->{one} eq 1 or CRITICAL "deserialize of key [one] failed: $obj->{one}";
	$obj->{two} eq 2 or CRITICAL "deserialize of key [two] failed: $obj->{two}";
	DONE;
});

ok_plugin(0, "JSON OK - decoded null", undef, "null JSON", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'JSON';
	START default => 'decoded null';

	JSON_DECODE("");

	DONE;
});

ok_plugin(0, "JSON OK - decoded undef", undef, "undef JSON", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'JSON';
	START default => 'decoded undef';

	JSON_DECODE(undef);

	DONE;
});

ok_plugin(0, "JSON OK - jsonp", undef, "jsonp decode", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => 'JSON';
	START default => 'jsonp';

	my $json = q[jsonpcall({"one":1,"two":2})];
	my $obj  = JSON_DECODE($json);

	$obj->{one} eq 1 or CRITICAL "deserialize of key [one] failed: $obj->{one}";
	$obj->{two} eq 2 or CRITICAL "deserialize of key [two] failed: $obj->{two}";
	DONE;
});

done_testing;
