use strict;
use warnings FATAL => 'all';

BEGIN {
  unless ($ENV{RELEASE_TESTING}) {
    require Test::More;
    Test::More::plan(skip_all => 'these tests are for release candidate testing');
  }
}

use Test::More;
use Test::Requires 'Test::CleanNamespaces';
all_namespaces_clean;
done_testing;
