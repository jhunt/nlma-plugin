#!perl

use Test::More;
do "t/common.pl";

sub test_outputs
{
	my ($cmd, $test, $opts) = @_;
	BAIL_OUT("No stdout file specified") unless $opts->{stdout}->{file};
	BAIL_OUT("No stderr file specified") unless $opts->{stderr}->{file};
	BAIL_OUT("No stdout expect specified") unless $opts->{stdout}->{expect};
	BAIL_OUT("No stderr expect specified") unless $opts->{stderr}->{expect};

	my $fullcmd = "$cmd > " . $opts->{stdout}->{file} . " 2> " . $opts->{stderr}->{file};
	print "Executing: $fullcmd\n";
	system $fullcmd;

	open FILE, $opts->{stdout}->{file};
	my @one_stdout = <FILE>;
	close FILE;
	
	open FILE, $opts->{stderr}->{file};
	my @one_stderr = <FILE>;
	close FILE;
	unlink $opts->{stderr}->{file};
	unlink $opts->{stdout}->{file};
	
	is_string_nows(join("\n",@one_stdout), $opts->{stdout}->{expect}, "$test - STDOUT as expected");
	is_string_nows(join("\n",@one_stderr), $opts->{stderr}->{expect}, "$test - STDERR as expected");
}

{
	my $stdout_expect = <<EOF
STDOUT 1
STDOUT 2
STDERRTEST OK
EOF
	;
	my $stderr_expect = <<EOF
STDERR 1
STDERR 2
EOF
	;
	my ($stdout, $stderr) = ("t/tmp/1.stdout", "t/tmp/1.stderr");
	test_outputs("perl t/stderr-test.pl", "Standard pipe handling", {
		stdout => {file => $stdout, expect => $stdout_expect},
		stderr => {file => $stderr, expect => $stderr_expect},
	});
}

{
	my $stdout_expect = <<EOF
STDOUT 1
Unknown option: asdf
stderr-test.pl -h|--help
stderr-test.pl
EOF
	;
	my $stderr_expect = <<EOF
STDERR 1
EOF
	;
	my ($stdout, $stderr) = ("t/tmp/2.stdout", "t/tmp/2.stderr");
	test_outputs("perl t/stderr-test.pl --asdf", "STDERR from GetOpts goes to STDOUT", {
		stdout => {file => $stdout, expect => $stdout_expect},
		stderr => {file => $stderr, expect => $stderr_expect},
	});
}

done_testing;
