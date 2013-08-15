use strict;
use warnings FATAL => 'all';

do 'examples/call_psgi.t';
die $@ if $@;
