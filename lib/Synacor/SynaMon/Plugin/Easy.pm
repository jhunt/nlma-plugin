package Synacor::SynaMon::Plugin::Easy;

use strict;
use warnings;

use Synacor::SynaMon::Plugin::Base;

use Exporter;
use base qw(Exporter);

our @EXPORT = qw/
	PLUGIN OPTION

	STATUS BAIL EVALUATE
	OK WARNING CRITICAL UNKNOWN

	START DONE

	CHECK_VALUE TRACK_VALUE

	STAGE START_TIMEOUT STOP_TIMEOUT

	STORE RETRIEVE CREDENTIALS

	DEBUG DUMP
/;

my $plugin;

sub PLUGIN  { $plugin = Synacor::SynaMon::Plugin::Base->new(@_); }
sub OPTION  { $plugin->option(@_); }

sub STATUS   { $plugin->status(@_); }
sub BAIL     { $plugin->bail(@_); }
sub ALERT    { $plugin->alert(@_); }

sub OK       { $plugin->OK(@_); }
sub WARNING  { $plugin->WARNING(@_); }
sub CRITICAL { $plugin->CRITICAL(@_); }
sub UNKNOWN  { $plugin->UNKNOWN(@_); }

sub CHECK_VALUE { $plugin->check_value(@_); }
sub TRACK_VALUE { $plugin->track_value(@_); }

sub START { $plugin->start(@_); }
sub DONE  { $plugin->done(@_); }

sub STAGE { $plugin->stage(@_); }
sub START_TIMEOUT { $plugin->start_timeout(@_); }
sub STOP_TIMEOUT  { $plugin->stop_timeout(@_); }

sub STORE { $plugin->store(@_); }
sub RETRIEVE { $plugin->retrieve(@_); }
sub CREDENTIALS { $plugin->credentials(@_); }

sub DEBUG { $plugin->debug(@_); }
sub DUMP  { $plugin->dump(@_); }

END {
	$plugin->done if $plugin && !$Synacor::SynaMon::Plugin::Base::ALL_DONE;
}

"Booyah!";

=head1 NAME

Synacor::SynaMon::Plugin::Easy - Simple Plugin API

=head1 DESCRIPTION

The B<Plugin::Easy> interface is an alternative to the object-oriented
B<Plugin> package.  It operates on a global plugin object, and helps
writer cleaner scripts.  It is not as flexible as the OO interface, but
should suffice for most check plugins.

It is also easier to read a B<Plugin::Easy> check than an OO check.

In general, procedures map directly to methods in the B<Plugin> package,
except that the procedural varieties are in upper case.  For example,
B<STORE(...)> is the same as B<$plugin->store(...)>.

See B<Synacor::SynaMon::Plugin> for in-depth documentation.

=head1 METHODS

=head2 PLUGIN

Sets up the global plugin context.  This B<must> be called first, as
soon as possible.  None of the other functions will work otherwise.

Arguments are identical to B<Synacor::SynaMon::Plugin::new>

=head2 OPTION

Wrapper around B<Synacor::SynaMon::Plugin::option>.

=head2 STATUS

Wrapper around B<Synacor::SynaMon::Plugin::status>.

=head2 BAIL

Wrapper around B<Synacor::SynaMon::Plugin::bail>.

=head2 ALERT

Wrapper around B<Synacor::SynaMon::Plugin::alert>.

=head2 OK

Wrapper around B<Synacor::SynaMon::Plugin::OK>.

=head2 WARNING

Wrapper around B<Synacor::SynaMon::Plugin::WARNING>.

=head2 CRITICAL

Wrapper around B<Synacor::SynaMon::Plugin::CRITICAL>.

=head2 UNKNOWN

Wrapper around B<Synacor::SynaMon::Plugin::UNKNOWN>.

=head2 CHECK_VALUE

=head2 EVALUATE

Wrapper around B<Synacor::SynaMon::Plugin::evaluate>.

=head2 TRACK_VALUE

Wrapper around B<Synacor::SynaMon::Plugin::track_value>.

=head2 START

Wrapper around B<Synacor::SynaMon::Plugin::start>.

=head2 DONE

Wrapper around B<Synacor::SynaMon::Plugin::done>.

=head2 STAGE

Wrapper around B<Synacor::SynaMon::Plugin::stage>.

=head2 START_TIMEOUT

Wrapper around B<Synacor::SynaMon::Plugin::start_timer>.

=head2 STOP_TIMEOUT

Wrapper around B<Synacor::SynaMon::Plugin::stop_timer>.

=head2 STORE

Wrapper around B<Synacor::SynaMon::Plugin::store>.

=head2 RETRIEVE

Wrapper around B<Synacor::SynaMon::Plugin::retrieve>.

=head2 CREDENTIALS

Wrapper around B<Synacor::SynaMon::Plugin::credentials>.

=head2 DEBUG

Wrapper around B<Synacor::SynaMon::Plugin::debug>.

=head2 DUMP

Wrapper around B<Synacor::SynaMon::Plugin::dump>.

=head1 AUTHOR

James Hunt, C<< <jhunt at synacor.com> >>

=cut

