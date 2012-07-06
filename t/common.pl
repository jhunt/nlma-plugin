sub ok_plugin
{
	my ($exit, $summary, $perfdata, $message, $sub) = @_;

	my ($e, $s, $p, $output);
	pipe my ($parent, $child);
	my $pid = fork;

	if ($pid) {
		close $child;

		$output = <$parent>;
		close $parent;

		wait;
		$e = $? >> 8; # FIXME: be more explicit

	} elsif ($pid == 0) {
		close $parent;
		open(STDOUT, ">&=" . fileno($child));
		$sub->();
		exit 42; # jus tin case

	} else {
		fail "$message - Couldn't fork: $!";
	}

	($s, $p) = map { s/^\s+//; s/\s$//; $_ } split /\|/, $output;

	is($s, $summary, "$message: expected summary output");
	is($p, $perf,    "$message: expected perfdata output") if $perf;
	is($e, $exit,    "$message: expect exit code $exit");
}
