use strict;
use warnings FATAL => 'all';

do 'examples/application_client_test.t';
die $@ if $@;
