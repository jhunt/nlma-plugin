#!/usr/bin/perl

use Synacor::SynaMon::Plugin qw(:easy);

PLUGIN(name => "STDERRTEST");

print "STDOUT 1\n";
print STDERR "STDERR 1\n";
START;
print "STDOUT 2\n";
print STDERR "STDERR 2\n";
OK;
DONE;
