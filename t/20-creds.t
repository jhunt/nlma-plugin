#!perl

use Test::More;
use Test::Deep;
require "t/common.pl";

###################################################################

chmod 0400, "t/data/creds";
chmod 0400, "t/data/creds.corrupt";

chmod 0000, "t/data/creds.perms";
chmod 0664, "t/data/creds.insecure";

delete $ENV{MONITOR_CRED_STORE};

ok_plugin(0, "CREDS OK - good", undef, "Credentials OK", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	my ($user, $pass);

	($user, $pass) = CREDENTIALS("db");
	unless ($user eq "dbuser" && $pass eq "dbpass") {
		CRITICAL "db: $user/$pass";
	}

	($user, $pass) = CREDENTIALS("passonly");
	unless (!defined $user && $pass eq "secret") {
		CRITICAL "passonly: $user/$pass";
	}

	($user, $pass) = CREDENTIALS("useronly");
	unless ($user eq "monitor_rw" && !defined $pass) {
		CRITICAL "useronly: $user/$pass";
	}

	($user, $pass) = CREDENTIALS("fail", "failagain", "db");
	unless ($user eq "dbuser" && $pass eq "dbpass") {
		CRITICAL "multi-key lookup: $user/$pass";
	}

	OK "good";
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Credentials not found for 'unknown'", undef, "Non-existent key", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("unknown");
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Credentials not found for 'fail1', 'fail2', 'fail3'", undef, "Non-existent key (multi)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	CREDENTIALS(qw/fail1 fail2 fail3/);
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Non-existent key (fail silently)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	SET ignore_credstore_failures => 1;
	START;
	if (CREDENTIALS "unknown") {
		WARNING "got creds for 'unknown' key";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Corrupt credentials key 'corrupt'", undef, "Bad key", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("corrupt");
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Corrupt credentials key 'corrupt'", undef, "Bad key (early)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	# first key does not exist;
	# second key is corrupt
	# last key does exist.
	CREDENTIALS("this-key-does-not-exist", "corrupt", "db");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Bad key (fail silently)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	SET ignore_credstore_failures => 1;
	START;
	if (CREDENTIALS "corrupt") {
		WARNING "got creds for 'corrupt' key";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Could not find credentials file", undef, "Credentials file missing", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.DNE";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Credentials file missing (fail silently)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.DNE";
	PLUGIN name => "creds";
	SET ignore_credstore_failures => 1;
	START;
	if (CREDENTIALS "should-fail") {
		WARNING "got creds from non-existent creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Could not read credentials file", undef, "Credentials file unreadable", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.perms";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Credentials file unreadable (fail silently)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.perms";
	PLUGIN name => "creds";
	SET ignore_credstore_failures => 1;
	START;
	if (CREDENTIALS "should-fail") {
		WARNING "got creds from non-accessible creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Insecure credentials file; mode is 0664 (not 0400)", undef, "Creds file insecure", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.insecure";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Creds file insecure (fail silently)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.insecure";
	PLUGIN name => "creds";
	SET ignore_credstore_failures => 1;
	START;
	if (CREDENTIALS "should-fail") {
		WARNING "got creds from insecure creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Corrupted credentials file", undef, "Creds file corrupted", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.corrupt";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Creds file corrupted (fail silently)", sub {
	use NLMA::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.corrupt";
	PLUGIN name => "creds";
	SET ignore_credstore_failures => 1;
	START;
	if (CREDENTIALS "should-fail") {
		WARNING "got creds from corrupted creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

{ # Credentials Store File Path Detection
  # (these tests are done outside of the ok_plugin(...) framework,
  #  because we can't depend on the contents of /home/ globally,
  #  and there are no mechanisms to directly influence the creation
  #  of the file path...


	my %SAVED_ENV = (
		USER      => $ENV{USER},
		SUDO_USER => $ENV{SUDO_USER},
	);
	delete $ENV{MONITOR_CRED_STORE};
	delete $ENV{USER};

	# THIS TEST MAKES A FEW ASSUMPTIONS:
	#  - icinga is a local user
	#  - ~icinga = /home/icinga
	#  - nlma is a local user
	#  - ~nlma = /home/nlma

	my @whois = getpwnam("icinga");
	ok(@whois, "[test sanity] icinga user exists");
	is($whois[7], "/home/icinga", "[test sanity] ~icinga = /home/icinga");

	@whois = getpwnam("nlma");
	ok(@whois, "[test sanity] nlma user exists");
	is($whois[7], "/home/nlma", "[test sanity] ~nlma = /home/nlma");

	# with apologies to Otis Day...
	@whois = getpwnam("shamalamadingdong");
	ok(!@whois, "[test sanity] shamalamadingdong user does not exist");

	my @pwent = getpwnam(getpwuid($>));
	my $HOME = $pwent[7];

	my $plugin = NLMA::Plugin::Base->new;

	delete $ENV{SUDO_USER};
	is($plugin->_credstore_path, "$HOME/.creds",
		"without \$SUDO_USER, ~\$>/.creds is used");

	$ENV{SUDO_USER} = "nlma";
	is($plugin->_credstore_path, "/home/nlma/.creds",
		"with \$SUDO_USER, ~\$SUDO_USER/.creds is used");

	$ENV{SUDO_USER} = "shamalamadingdong";
	is($plugin->_credstore_path, "$HOME/.creds",
		"Fall-through, no shamalamadingdong user");

	$ENV{MONITOR_CRED_STORE} = "/tmp/creds.public";
	$ENV{SUDO_USER} = "nlma";
	is($plugin->_credstore_path, "/tmp/creds.public",
		"use \$MONITOR_CRED_STORE as-is, if present");

	$ENV{SUDO_USER} = $SAVED_ENV{SUDO_USER} if $SAVED_ENV{SUDO_USER};
	$ENV{USER}      = $SAVED_ENV{USER};
}

{
	my $plugin = NLMA::Plugin::Base->new;

	cmp_deeply([$plugin->cred_keys("TYPE", "role01.dc.example.com")],
		["TYPE/role01.dc.example.com",
		 "TYPE/dc/role",
		 "TYPE/dc/*",
		 "TYPE/*/role",
		 "TYPE" ],
		"Basic role / cluster key breakdown");

	cmp_deeply([$plugin->cred_keys("LDAP", "test23.svcs.dc.example.com")],
		["LDAP/test23.svcs.dc.example.com",
		 "LDAP/svcs.dc/test",
		 "LDAP/svcs.dc/*",
		 "LDAP/*/test",
		 "LDAP" ],
		"Generate LDAP credentials keys");

	cmp_deeply([$plugin->cred_keys("TYPE", "10.10.10.10")],
		["TYPE/10.10.10.10",
		 "TYPE" ],
		"Generate TYPE credentials based on IP");
}

system("chmod 644 t/data/creds*");

done_testing;
