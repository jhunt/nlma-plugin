#!perl

use Test::More;
use Test::MockModule;
use Test::Deep;
require "t/common.pl";

ok_plugin(0, "DB OK", undef, "Default DB settings", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";

	my $settings = $NLMA::Plugin::Easy::plugin->{settings};

	CRITICAL "Bad default on_db_failure setting: '$settings->{on_db_failure}'."
		unless $settings->{on_db_failure} == 2;
	CRITICAL "Bad default bail_on_db_failure setting: '$settings->{bail_on_db_failure}'."
		unless $settings->{bail_on_db_failure} == 1;

	OK;
	DONE;
});

ok_plugin(0, "DB OK", undef, "DB settings can be overridden", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";

	my $settings = $NLMA::Plugin::Easy::plugin->{settings};

	SET on_db_failure      => "WARNING";
	SET bail_on_db_failure => 0;

	CRITICAL "Bad overridden on_db_failure setting: '$settings->{on_db_failure}'."
		unless $settings->{on_db_failure} == 1;
	CRITICAL "Bad overridden db_on_fail_bail setting: '$settings->{bail_on_db_failure}'."
		unless $settings->{bail_on_db_failure} == 0;

	OK;
	DONE;
});

ok_plugin(2, "DB CRITICAL - Can't connect to MySQL server on '127.86.86.86' (111); dbi:mysql:database=foo;host=127.86.86.86;port=8686 as username with a password", undef, "Bad connection = bail by default", sub {
	use NLMA::Plugin qw/:eay/;
	PLUGIN name => "db";

	DB_CONNECT "dbi:mysql:database=foo;host=127.86.86.86;port=8686", "username", "password";
	CRITICAL "should have bailed but didn't!";

	OK;
	DONE;
});

ok_plugin(1, "DB WARNING - Can't connect to MySQL server on '127.86.86.86' (111); dbi:mysql:database=foo;host=127.86.86.86;port=8686 as username with a password", undef, "on_db_failure controls BAIL status", sub {
	use NLMA::Plugin qw/:eay/;
	PLUGIN name => "db";

	SET on_db_failure => 'WARNING';

	DB_CONNECT "dbi:mysql:database=foo;host=127.86.86.86;port=8686", "username", "password";
	CRITICAL "should have bailed but didn't!";

	OK;
	DONE;
});

ok_plugin(1, "DB WARNING - connect failed", undef, "bail_on_db_failure is honored", sub {
	use NLMA::Plugin qw/:eay/;
	PLUGIN name => "db";

	SET bail_on_db_failure => 'no';
	SET      on_db_failure => 'OK';

	DB_CONNECT "dbi:mysql:database=foo;host=127.86.86.86;port=8686", "username", "password"
		or WARNING "connect failed";

	OK;
	DONE;
});

sub db_setup {
	my $suffix = shift;
qx{mkdir -p t/tmp; rm -f t/tmp/db$suffix; sqlite3 t/tmp/db$suffix <<EOF
CREATE TABLE weekdays (
  number  INTEGER,
  name    VARCHAR(40),
  weekend INTEGER
);
INSERT INTO weekdays (number, name, weekend) VALUES (0, 'Sunday',    1);
INSERT INTO weekdays (number, name, weekend) VALUES (1, 'Monday',    0);
INSERT INTO weekdays (number, name, weekend) VALUES (2, 'Tuesday',   0);
INSERT INTO weekdays (number, name, weekend) VALUES (3, 'Wednesday', 0);
INSERT INTO weekdays (number, name, weekend) VALUES (4, 'Thursday',  0);
INSERT INTO weekdays (number, name, weekend) VALUES (5, 'Friday',    0);
INSERT INTO weekdays (number, name, weekend) VALUES (6, 'Saturday',  1);
EOF};
}

ok_plugin(0, "DB OK - 5 days in the week", undef, "General DB_QUERY", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";
	db_setup 1;

	DB_CONNECT "dbi:SQLite:dbname=t/tmp/db1";
	my $weekdays = DB_QUERY "SELECT name FROM weekdays WHERE weekend = 0";
	OK scalar(@$weekdays) . " days in the week";
	DONE;
});

ok_plugin(0, "DB OK - 5 days in the week (list version)", undef, "General DB_QUERY", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";
	db_setup 2;

	DB_CONNECT "dbi:SQLite:dbname=t/tmp/db2";
	my @weekdays = DB_QUERY "SELECT name FROM weekdays WHERE weekend = 0";
	OK scalar(@weekdays) . " days in the week (list version)";
	DONE;
});

ok_plugin(0, "DB OK - Friday is a weekend now", undef, "General DB_QUERY", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";
	db_setup 3;

	DB_CONNECT "dbi:SQLite:dbname=t/tmp/db3";
	DB_EXEC "UPDATE weekdays SET weekend = 1 WHERE name = 'Friday'"
		or BAIL(CRITICAL "Failed to make Friday into a weekend.  Darn.");

	my @weekdays = DB_QUERY "SELECT name FROM weekdays WHERE weekend = 0";
	if (@weekdays == 4) {
		OK "Friday is a weekend now";
	} else {
		WARNING "Still ".scalar(@weekdays)." in the week...";
	}
	OK;
	DONE;
});

ok_plugin(2, "DB CRITICAL - Error near %QUOT%ALL%QUOT%: syntax error, while parsing %QUOT%UPDATE ALL THE THINGS%QUOT%", undef, "Syntax error in SQL", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";
	db_setup 4;

	DB_CONNECT "dbi:SQLite:dbname=t/tmp/db3";
	DB_EXEC "UPDATE ALL THE THINGS";
	CRITICAL "should have bailed but didn't!";

	OK;
	DONE;
});

ok_plugin(1, "DB WARNING - Error near %QUOT%ALL%QUOT%: syntax error, while parsing %QUOT%UPDATE ALL THE THINGS%QUOT%", undef, "Syntax error in SQL (WARNING only)", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";
	db_setup 5;

	SET on_db_failure => 'warn';

	DB_CONNECT "dbi:SQLite:dbname=t/tmp/db3";
	DB_EXEC "UPDATE ALL THE THINGS";
	CRITICAL "should have bailed but didn't!";

	OK;
	DONE;
});

ok_plugin(2, "DB CRITICAL - Error no such table: weeeeeeeeekdays, while parsing %QUOT%DELETE FROM weeeeeeeeekdays%QUOT%", undef, "Semantic error in SQL", sub {
	use NLMA::Plugin qw/:easy/;
	PLUGIN name => "db";
	db_setup 4;

	DB_CONNECT "dbi:SQLite:dbname=t/tmp/db3";
	DB_EXEC "DELETE FROM weeeeeeeeekdays";
	CRITICAL "should have bailed but didn't!";

	OK;
	DONE;
});

qx(rm -f t/tmp/db*);

done_testing;
