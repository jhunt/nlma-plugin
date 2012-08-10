#!perl

use Test::More;
do "t/common.pl";

###################################################################

chmod 0400, "t/data/creds";
chmod 0400, "t/data/creds.corrupt";

chmod 0000, "t/data/creds.perms";
chmod 0664, "t/data/creds.insecure";

ok_plugin(0, "CREDS OK - good", undef, "Credentials OK", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
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

	OK "good";
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Credentials key 'unknown' not found", undef, "Non-existent key", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("unknown");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Non-existent key (fail silently)", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	if (CREDENTIALS("unknown", "FAILOK")) {
		WARNING "got creds for 'unknown' key";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Corrupt credentials key 'corrupt'", undef, "Bad key", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("corrupt");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Bad key (fail silently)", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds";
	PLUGIN name => "creds";
	START;
	if (CREDENTIALS("corrupt", "FAILOK")) {
		WARNING "got creds for 'corrupt' key";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Could not find credentials file", undef, "Credentials file missing", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.DNE";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Credentials file missing (fail silently)", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.DNE";
	PLUGIN name => "creds";
	START;
	if (CREDENTIALS("should-fail", "FAILOK")) {
		WARNING "got creds from non-existent creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Could not read credentials file", undef, "Credentials file unreadable", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.perms";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Credentials file unreadable (fail silently)", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.perms";
	PLUGIN name => "creds";
	START;
	if (CREDENTIALS("should-fail", "FAILOK")) {
		WARNING "got creds from non-accessible creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Insecure credentials file; mode is 0664 (not 0400)", undef, "Creds file insecure", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.insecure";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Creds file insecure (fail silently)", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.insecure";
	PLUGIN name => "creds";
	START;
	if (CREDENTIALS("should-fail", "FAILOK")) {
		WARNING "got creds from insecure creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

ok_plugin(3, "CREDS UNKNOWN - Corrupted credentials file", undef, "Creds file corrupted", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.corrupt";
	PLUGIN name => "creds";
	START;
	CREDENTIALS("should-fail");
	DONE;
});

ok_plugin(0, "CREDS OK - failed silently", undef, "Creds file corrupted (fail silently)", sub {
	use Synacor::SynaMon::Plugin qw(:easy);
	$ENV{MONITOR_CRED_STORE} = "t/data/creds.corrupt";
	PLUGIN name => "creds";
	START;
	if (CREDENTIALS("should-fail", "FAILOK")) {
		WARNING "got creds from corrupted creds file";
	} else {
		OK "failed silently";
	}
	DONE;
});

system("chmod 644 t/data/creds*");

done_testing;
