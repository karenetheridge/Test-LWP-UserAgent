use strict;
use warnings FATAL => 'all';

use Test::Requires 'HTTP::Message::PSGI';

do 'examples/call_psgi.t';
die $@ if $@;
