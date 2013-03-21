use strict;
use warnings FATAL => 'all';

BEGIN {
    unless ($ENV{AUTHOR_TESTING}) {
        require Test::More;
        Test::More::plan(skip_all => 'these tests use the network, and are for author testing');
    }
}

use Test::More tests => 2;
use Test::NoWarnings 1.04 ':early';
use Test::TempDir;
use Path::Tiny;
use Test::LWP::UserAgent;

# the root problem here was that we were not passing along additional
# arguments to request() to the superclass, e.g. the option to save the
# content to a file.

{
    # network_fallback case

    my $useragent = Test::LWP::UserAgent->new(network_fallback => 1);

    my (undef, $tmpfile) = tempfile;

    my $response = $useragent->get('http://example.com/');
    my $expected_content = $response->decoded_content;

    $useragent->get('http://example.com/', ':content_file' => $tmpfile);

    my $contents = path($tmpfile)->slurp;
    is($contents, $expected_content, 'response body is saved to file (network responses)');
}

