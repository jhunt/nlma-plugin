#!perl

use Test::More;
require "t/common.pl";

###################################################################

ok_plugin(0, "BYTES OK", undef, "Basic size spec parsing", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "BYTES";
	START;
	my %t;

	%t = (
		'4K'   => 4096,
		'2kb'  => 2048,
		'1.5k' => 1536,
		'1MB'  => 1024*1024,
		'1GB'  => 1024*1024*1024,
		'1TB'  => 1024*1024*1024*1024,
		'1PB'  => 1024*1024*1024*1024*1024,
		'1EB'  => 1024*1024*1024*1024*1024*1024,
		'1YB'  => 1024*1024*1024*1024*1024*1024*1024,
		'1ZB'  => 1024*1024*1024*1024*1024*1024*1024*1024,
	);
	for my $s (keys %t) {
		my $b = $t{$s};
		my $x = PARSE_BYTES($s);
		BAIL(CRITICAL "PARSE_BYTES($s) != $b (== $x)") unless $x == $b;
	}

	%t = (
		'4.00KB'  => 4096,
		'2.00KB'  => 2048,
		'1.50KB'  => 1536,
		'1.00MB'  =>     1024*1024,
		'1.00GB'  =>     1024*1024*1024,
		'1.00TB'  =>     1024*1024*1024*1024,
		'1.00PB'  =>     1024*1024*1024*1024*1024,
		'1.00EB'  =>     1024*1024*1024*1024*1024*1024,
		'1.00YB'  =>     1024*1024*1024*1024*1024*1024*1024,
		'1.20ZB'  => 1.2*1024*1024*1024*1024*1024*1024*1024*1024,
	);
	for my $s (keys %t) {
		my $b = $t{$s};
		my $x = FORMAT_BYTES($b);
		BAIL(CRITICAL "FORMAT_BYTES($b) != $s (== $x)") unless $x eq $s;
	}

	OK;
	DONE;
});

ok_plugin(0, "BYTES OK", undef, "undefined values", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "BYTES";
	START;

	my $want = '<undef>';
	my $out  = FORMAT_BYTES(undef);
	BAIL(CRITICAL "FORMAT_BYTES(undef) != $want (== $out)") unless $out eq $want;

	$out  = FORMAT_BYTES();
	BAIL(CRITICAL "FORMAT_BYTES() != $want (== $out)") unless $out eq $want;

	$out = PARSE_BYTES(undef);
	BAIL(CRITICAL "PARSE_BYTES(undef) != undef (== $out)") if defined $out;

	$out = PARSE_BYTES();
	BAIL(CRITICAL "PARSE_BYTES() != undef (== $out)") if defined $out;

	$out = PARSE_BYTES('');
	BAIL(CRITICAL "PARSE_BYTES('') != 0 (== $out)") if !defined $out or $out != 0;

	OK;
	DONE;
});

ok_plugin(0, "BYTES OK", undef, "BYTES_THOLD handling", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "BYTES";
	START;

	my ($before, $after, $got);

	($before, $after) = ("4kB:8kB", "4096:8192");
	$got = BYTES_THOLD($before);
	BAIL(CRITICAL "THOLD($before) != $after (eq $got)") unless $after eq $got;

	($before, $after) = ("4k:8k", "4k:8k"); # no change, these aren't strict enough
	$got = BYTES_THOLD($before);
	BAIL(CRITICAL "THOLD($before) != $after (eq $got)") unless $after eq $got;

	OK;
	DONE;
});

done_testing;
