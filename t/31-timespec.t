#!perl

use Test::More;
require "t/common.pl";

###################################################################

ok_plugin(0, "TIME OK", undef, "Basic time spec parsing", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "TIME";
	START;
	my %t;

	%t = (
		'81'   => 81,
		'3m'   => 180,
		'2.5m' => 150,
		'10m'  => 600,
		'1h'   => 3600,
		'2d'   => 86400*2,
		'14d'  => 86400*14,
		'2w'   => 86400*14,
		'1h1m' => 3660,
	);
	for my $s (keys %t) {
		my $b = $t{$s};
		my $x = PARSE_TIME($s);
		BAIL(CRITICAL "PARSE_TIME($s) != $b (== $x)") unless $x == $b;
	}

	%t = (
		'81s'  => 81,
		'10m'  => 600,
		'60m'  => 3600,
		'65m'  => 3900,
		'2h'   => 7290, # close enough
		'2d'   => 86400*2,
		'14d'  => 86400*14,
	);
	for my $s (keys %t) {
		my $b = $t{$s};
		my $x = FORMAT_TIME($b);
		BAIL(CRITICAL "FORMAT_TIME($b) != $s (== $x)") unless $x eq $s;
	}

	OK;
	DONE;
});

ok_plugin(0, "TIME OK", undef, "undefined values", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "TIME";
	START;

	my $want = '<undef>';
	my $out  = FORMAT_TIME(undef);
	BAIL(CRITICAL "FORMAT_TIME(undef) != $want (== $out)") unless $out eq $want;

	$out  = FORMAT_TIME();
	BAIL(CRITICAL "FORMAT_TIME() != $want (== $out)") unless $out eq $want;

	$out = PARSE_TIME(undef);
	BAIL(CRITICAL "PARSE_TIME(undef) != undef (== $out)") if defined $out;

	$out = PARSE_TIME();
	BAIL(CRITICAL "PARSE_TIME() != undef (== $out)") if defined $out;

	$out = PARSE_TIME('');
	BAIL(CRITICAL "PARSE_TIME('') != 0 (== $out)") if !defined $out or $out != 0;

	OK;
	DONE;
});

ok_plugin(0, "TIME OK", undef, "TIME_THOLD handling", sub {
	use NLMA::Plugin qw(:easy);
	PLUGIN name => "TIME";
	START;

	my ($before, $after, $got);

	($before, $after) = ("5m:10m", "300:600");
	$got = TIME_THOLD($before);
	BAIL(CRITICAL "THOLD($before) != $after (eq $got)") unless $after eq $got;

	($before, $after) = ("4k:8", "4k:8"); # no change, these aren't time specs
	$got = TIME_THOLD($before);
	BAIL(CRITICAL "THOLD($before) != $after (eq $got)") unless $after eq $got;

	OK;
	DONE;
});

done_testing;
