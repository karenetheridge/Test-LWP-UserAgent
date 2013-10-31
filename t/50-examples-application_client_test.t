use strict;
use warnings FATAL => 'all';

use Test::Requires qw(JSON Moose);

do 'examples/application_client_test.t';
die $@ if $@;
