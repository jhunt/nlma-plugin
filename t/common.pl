use strict;
use warnings;
use Test::LongString;
use POSIX qw(WEXITSTATUS WTERMSIG WIFEXITED WIFSIGNALED);

sub TEST_ALL
{
	if (!exists $ENV{TEST_ALL}) {
		chomp(my $hostname = qx(hostname -f));
		$ENV{TEST_ALL} = ($hostname =~ m/\.opal\./) ? 1 : 0;
	}
	$ENV{TEST_ALL};
}

sub PLATFORM
{
	open my $pipe, "-|", "/usr/bin/lsb_release -a"
		or return 'unknown';

	# LSB Version:    :core-3.0-ia32:core-3.0-noarch:graphics-3.0-ia32:graphics-3.0-noarch
	# Distributor ID: CentOS
	# Description:    CentOS release 4.7 (Final)
	# Release:        4.7
	# Codename:       Final

	my ($dist, $ver);
	while (<$pipe>) {
		$dist = $1 if m/Distributor ID:\s+(.*)/i;
		$ver  = $1 if m/Release:\s+(.*)/i;
	}
	close $pipe;

	local $_ = "$dist-$ver";
	return 'centos4' if m/^centos-4/i;
	return 'centos5' if m/^centos-5/i;
	return 'centos6' if m/^centos-6/i;
	return 'unknown';
}

sub ok_plugin
{
	my ($exit, $summary, $perf, $message, $sub, $args, %opts) = @_;
	$args = $args || [];
	$opts{output} ||= "";

	my ($e, $s, $p, @output);
	pipe my ($parent, $child);
	my $pid = fork;

	if ($pid) {
		close $child;
		
		# treat output as array, then parse only first line, otherwise
		# multi-line output may cause exit code 13's unexpectedly
		@output = <$parent>;
		close $parent;

		wait;
		my $rc = $?;
		if (WIFEXITED($rc)) {
			$e = WEXITSTATUS($rc);
		} elsif (WIFSIGNALED($rc)) {
			$e = WTERMSIG($rc);
		} else {
			$e = sprintf("0x%04x", $rc);
		}

	} elsif ($pid == 0) {
		close $parent;
		open(STDOUT, ">&=" . fileno($child));
		@ARGV = @$args;
		$sub->();
		exit 42; # just in case

	} else {
		fail "$message - Couldn't fork: $!";
	}

	if ($opts{output} eq 'all') {
		$s = join('', @output);
		is($s, $summary, "$message: expected summary output");
		is($e, $exit,    "$message: expect exit code $exit");
	} else {
		($s, $p) = map { s/^\s+//; s/\s$//; $_ } split /\|/, $output[0];

		is($s, $summary, "$message: expected summary output");
		is($p, $perf,    "$message: expected perfdata output") if $perf;
		is($e, $exit,    "$message: expect exit code $exit");
	}
}

sub ok_plugin_help
{
	my ($expect, $message, $sub, $args) = @_;
	pipe my ($parent, $child);
	my $pid = fork;
	my ($e, $output);

	if ($pid) {
		close $child;

		$output = do { local $/ = undef; <$parent> };
		wait;

		my $rc = $?;
		if (WIFEXITED($rc)) {
			$e = WEXITSTATUS($rc);
		} elsif (WIFSIGNALED($rc)) {
			$e = WTERMSIG($rc);
		} else {
			$e = sprintf("0x%04x", $rc);
		}

	} elsif ($pid == 0) {
		close $parent;
		open(STDOUT, ">&=" . fileno($child));
		@ARGV = @$args;
		$sub->();
		exit 42;
	} else {
		fail "$message - Couldn't fork: $!";
	}

	# Important: _nows will ignore whitespace
	is_string_nows($output, $expect, "$message: expected help output");
	my $exit = 3; # always 3...
	is($e, $exit, "$message: expect exit code $exit");
}

1;
