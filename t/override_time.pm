use base 'Exporter';
our @EXPORT = qw/ OVERRIDE_TIME /;

BEGIN {
	# don't try this at home, kids
	my $__TIME_snapshot = time;
	my $__TIME_override = undef;
	*CORE::GLOBAL::time = sub { $__TIME_override || $__TIME_snapshot };
	sub OVERRIDE_TIME { $__TIME_override = shift;}
}

