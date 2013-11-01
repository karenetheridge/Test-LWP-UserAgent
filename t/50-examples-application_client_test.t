use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Requires qw(JSON Moose);

plan skip_all => 'this example requires perl 5.10' if $^V < 5.010;

do 'examples/application_client_test.t';
die $@ if $@;
