#!perl

use lib "t";
use lib "lib";
use Test::More;
use IO::Prompt;
require"common.pl";

plan(skip_all => 'set TEST_ALL to enable SSH testing') unless TEST_ALL();

print "##########################\n";
print "# These tests are very finicky with key authentication.\n";
print "# Ensure you don't have an agent or key forwarding currently set up, as that may skew tests.\n";
print "##########################\n";
my $host = prompt("Hostname to test SSH against: ");
my $closed_port = prompt("Enter a closed port on $host: ");
my $user = prompt("Username to authenticate with: ");
my $pass = prompt("Password to authenticate with: ", -e => '*');
my $bad_pass = $pass . "blahblahblah";
my $key_file = prompt("Valid Identity file to authenticate with: ");
my $bad_key_file = prompt("Bogus Identity file to authenticate with: ");


#correct passwd OKs
ok_plugin(0, "SSH OK - Command successfully executed", undef, "SSH Password Authentication Succeeded", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name=> "SSH";
	START;
	my $ssh = SSH($host, $user, password => $pass);
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh);
	chomp $stdout;
	chomp $stderr;
	if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
		OK("Command successfully executed");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
	DONE;
});

sub test {
        use Synacor::SynaMon::Plugin qw(:easy);
        PLUGIN name=> "SSH";
        START;
        my $ssh = SSH($host, $user, identity_file => $key_file);
        my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh);
        chomp $stdout;
        chomp $stderr;
        if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
                OK("Command successfully executed");
        } else {
                CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
        }
        DONE;
};
#correct key OKs
ok_plugin(0, "SSH OK - Command successfully executed", undef, "SSH Public Key Authentication Succeeded", \&test, ["--debug", "-t", "60"]);
#sub {
#	use Synacor::SynaMon::Plugin qw(:easy);
#	PLUGIN name=> "SSH";
#	START;
#	my $ssh = SSH($host, $user, identity_file => $key_file);
#	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh);
#	chomp $stdout;
#	chomp $stderr;
#	if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
#		OK("Command successfully executed");
#	} else {
#		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
#	}
#	DONE;
#}, ["--debug", '-t', '60']);

#bad password CRITs
ok_plugin(2, "SSH CRITICAL - Failed to authenticate via ssh as user '$user' to $host.", undef, "SSH Bad Password returns CRITICAL", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name=> "SSH";
	START;
	my $ssh = SSH($host, $user, password => $bad_pass);
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh);
	chomp $stdout;
	chomp $stderr;
	if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
		OK("Command successfully executed");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
	DONE;
});

#bad password OKs on failok
ok_plugin(0, "SSH OK - Got undefined values on failed connection", undef, "SSH Bad Password returns OK for failok", sub {
        use Synacor::SynaMon::Plugin qw(:easy);
        PLUGIN name=> "SSH";
	START;
        my $ssh = SSH($host, $user, password => $bad_pass, failok => 1);
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh, failok => 1);
	if (!defined $stdout && ! defined $stderr && ! defined $exit) {
		OK("Got undefined values on failed connection");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
        DONE;
});

#bad key CRITs
ok_plugin(2, "SSH CRITICAL - Failed to authenticate via ssh as user '$user' to $host.", undef, "SSH Bad Identity File returns CRITICAL", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name=> "SSH";
	START;
	my $ssh = SSH($host, $user, identity_file => $bad_key_file);
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh);
	chomp $stdout;
	chomp $stderr;
	if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
		OK("Command successfully executed");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
	DONE;
});

#bad key OKs on failok
ok_plugin(0, "SSH OK - Got undefined values on failed connection", undef, "SSH BAD Identity File returns OK on failok", sub {
        use Synacor::SynaMon::Plugin qw(:easy);
        PLUGIN name=> "SSH";
	START;
        my $ssh = SSH($host, $user, identity_file => $bad_key_file, failok => 1);
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh, failok => 1);
	if (!defined $stdout && ! defined $stderr && ! defined $exit) {
		OK("Got undefined values on failed connection");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
        DONE;
});

#no username UNKNOWNs
ok_plugin(3, "SSH UNKNOWN - No SSH username provided", undef, "Empty username causes UNKNOWN", sub {
        use Synacor::SynaMon::Plugin qw(:easy);
        PLUGIN name=> "SSH";
	START;
        my $ssh = SSH($host, '', identity_file => $bad_key_file, failok => 1);
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh);
	if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
		OK("Command successfully executed");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
        OK;
        DONE;
});


#no pass/key UNKNOWNs
ok_plugin(3, "SSH UNKNOWN - No password or identity file provided", undef, "No Password/Identity file causes UNKNOWN", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name=> "SSH";
	START;
	my $ssh = SSH($host, $user, ());
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test", ssh_connection => $ssh);
	chomp $stdout;
	chomp $stderr;
	if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
		OK("Command successfully executed");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
	OK;
	DONE;
});

#connection refused CRITs
ok_plugin(2, "SSH CRITICAL - SSH Connection error: Can't connect to $host, port $closed_port: Connection refused.", undef, "SSH Connection refused returns CRITIAL", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name=> "SSH";
	START;
        my $ssh = SSH($host, $user, password => $pass, port => $closed_port);
	OK("Shouldn't get this far without failok");
	DONE;
});

#connection refused OKs on failok
ok_plugin(0, 'SSH OK - $ssh is undefined as expected.', undef, "SSH Connection refused returns OK on failok", sub {
        use Synacor::SynaMon::Plugin qw(:easy);
        PLUGIN name=> "SSH";
	START;
        my $ssh = SSH($host, $user, password => $pass, port => $closed_port, failok => 1);
	if (defined $ssh) {
		CRITICAL("\$ssh should be undefined, but is defined.");	
	} else {
		OK("\$ssh is undefined as expected.");
	}
        DONE;
});

#ssh option gets set correctly
ok_plugin(0, "SSH OK", undef, "SSH Options get passed properly", sub {
        use Synacor::SynaMon::Plugin qw(:easy);
        PLUGIN name=> "SSH";
	START;
        my $ssh = SSH($host, $user, identity_file => $pass, ssh_options => ["UserKnownHostsFile no"]);
        OK if $ssh->{config}->{o}->{user_known_hosts} eq "no";
        DONE;
});

#run_ssh storage works porperly
ok_plugin(0, "SSH OK - Command successfully executed", undef, "run_ssh handles saving ssh properly", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "SSH";
	START;
	# create bad connection, overwrite with new connection, then test
	SSH($host, $user, password => $bad_pass);
	SSH($host, $user, password => $pass);
	my ($stdout, $stderr, $exit) = RUN_SSH("echo test");
	chomp $stdout;
	chomp $stderr;
	if ($stdout eq "test" && $stderr eq "" && $exit == 0) {
		OK("Command successfully executed");
	} else {
		CRITICAL("Unexpected CMD output (stdout, stderr, exit): ('$stdout', '$stderr', '$exit')");
	}
	DONE;
});

#missing ssh parameter causes unknown
ok_plugin(3, "SSH UNKNOWN - No ssh connection defined", undef, "run_ssh causes UNKNOWN if missing default ssh object", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "SSH";
	RUN_SSH("echo test");
	OK;
	DONE;
});

#missing ssh parameter causes unknown
ok_plugin(3, "SSH UNKNOWN - No ssh connection defined", undef, "run_ssh causes UNKNOWN if missing explicit ssh object", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	PLUGIN name => "SSH";
	my $ssh = undef;
	RUN_SSH("echo test", ssh_connection => $ssh);
	OK;
	DONE;
});

done_testing;
