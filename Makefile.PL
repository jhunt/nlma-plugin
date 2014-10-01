use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Synacor::SynaMon::Plugin',
    AUTHOR              => q{James Hunt <jhunt@synacor.com>},
    VERSION_FROM        => 'lib/Synacor/SynaMon/Plugin.pm',
    ABSTRACT_FROM       => 'lib/Synacor/SynaMon/Plugin.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Synacor-SynaMon-Plugin-*' },
    INSTALLVENDORLIB    => $ENV{INSTALLVENDORLIB},
);
