#!perl

use strict;
use Test::More;
use Test::MockModule;
use Test::Deep;

#FIXME: mock out Net::SSH::Perl's new, login, cmd commands
my $sshmodule = Test::MockModule->new("Net::SSH::Perl");
$sshmodule->mock('new', sub {
	my ($class, $host, %opts) = @_;
	return if $host eq "invalidhost";
	die "Invalid hostname: $host" if $host eq "badhost";
	return bless(
		{
			host  => $host,
			port  => $opts{port},
			debug => $opts{debug},
			opts  => \%opts,
		},
		$class
	);
});
$sshmodule->mock('login', sub {
	my ($self, $user, $pass) = @_;
	return $pass eq "badpass" ? 0 : 1;
});

require "t/common.pl";

# Test debug is passed to ssh
# test new returning true
# test login returning true
# Test hostname w/port options being processed
ok_plugin(0,
	"SSH OK - ssh obj created properly",
	undef,
	"debug on turns on debugging in ssh module",
	sub {
		open STDERR, ">", "/dev/null";
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "myhost:22", "myuser", "mypass", { ssh_opt => "asdf"};
		CRITICAL "Debug mode was not enabled" unless $ssh->{debug} == 1;
		CRITICAL "Hostname not parsed properly" unless $ssh->{host} eq "myhost";
		CRITICAL "Port not parsed properly" unless $ssh->{port} == 22;
		OK "ssh obj created properly";
	},
	[ "-D" ],
);

# test new returning false
ok_plugin(2,
	"SSH CRITICAL - Couldn't connect to invalidhost",
	undef,
	"Net::SSH::Perl->new() returning false triggers crit",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "invalidhost", "myuser", "mypass", { ssh_opt => "asdf"};
		OK "this should not return ok";
	}
);

# test login returning false
ok_plugin(2,
	"SSH CRITICAL - Could not log in to myhost as myuser",
	undef,
	"Net::SSH::Perl->login() returning false triggers crit",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "myhost", "myuser", "badpass", { ssh_opt => "asdf"};
		OK "this should not return ok";
	}
);

# test new/login dying
ok_plugin(2,
	"SSH CRITICAL - Could not ssh to badhost as myuser: Invalid hostname: badhost.",
	undef,
	"die during new()/login() triggers crit",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "badhost", "myuser", "badpass", { ssh_opt => "asdf"};
		OK "this should not return ok";
	}
);

# test new returning false using failok
ok_plugin(0,
	"SSH OK",
	undef,
	"Net::SSH::Perl->new() returning false using failok doesn't trigger crit",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "invalidhost", "myuser", "mypass", { ssh_opt => "asdf", failok => 1 };
		OK unless defined $ssh;
	}
);

# test login returning false using failok
ok_plugin(0,
	"SSH OK",
	undef,
	"Net::SSH::Perl->login() returning false using failok doesn't trigger crit",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "myhost", "myuser", "badpass", { ssh_opt => "asdf", failok => 1 };
		OK unless defined $ssh;
	}
);

# test new/login dying using failok
ok_plugin(0,
	"SSH OK",
	undef,
	"die during new()/login() using failok doesn't trigger crit",
	sub {
		use NLMA::Plugin qw(:easy);
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "badhost", "myuser", "badpass", { ssh_opt => "asdf", failok => 1 };
		OK unless defined $ssh;
	}
);

# verify we set default identity files
ok_plugin(0,
	"SSH OK",
	undef,
	"identity_files default is set",
	sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "myhost", "myuser", "mypass";
		OK if (eq_deeply $ssh->{opts}{identity_files},
				bag(
					re("\/.ssh\/id_rsa\$"),
					re("\/.ssh\/id_dsa\$"),
					re("\/.ssh\/identity\$"),
				));
	}
);

# verify that string identity files are translated to arrayrefs of one
ok_plugin(0,
	"SSH OK",
	undef,
	"identity_files forces arrayref",
	sub {
		use NLMA::Plugin qw/:easy/;
		PLUGIN name => "SSH";
		START;
		my $ssh = SSH "myhost", "myuser", "mypass", { identity_files => "myfile" };
		OK if (eq_deeply $ssh->{opts}{identity_files}, [ 'myfile' ]);
	}
);

done_testing;
