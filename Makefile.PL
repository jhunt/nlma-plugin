use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'NLMA::Plugin',
    AUTHOR              => q{James Hunt <jhunt@synacor.com>},
    VERSION_FROM        => 'lib/NLMA/Plugin.pm',
    ABSTRACT_FROM       => 'lib/NLMA/Plugin.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'NLMA-Plugin-*' },
    INSTALLVENDORLIB    => $ENV{INSTALLVENDORLIB},
);
