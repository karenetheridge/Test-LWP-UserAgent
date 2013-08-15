use strict;
use warnings FATAL => 'all';

BEGIN {
    unless ($ENV{AUTHOR_TESTING}) {
        require Test::More;
        Test::More::plan(skip_all => 'these tests use the network, and are for author testing');
    }
}

use Test::More tests => 4;
use Test::Warnings;
use Test::Deep;
use Test::TempDir;
use Path::Tiny;
use Test::LWP::UserAgent;

# the root problem here was that we were not passing along additional
# arguments to request() to the superclass, e.g. the option to save the
# content to a file.

my $useragent = Test::LWP::UserAgent->new(network_fallback => 1);
my $response = $useragent->get('http://example.com/');
my $expected_content = $response->decoded_content;

{
    # network_fallback case

    my (undef, $tmpfile) = tempfile;

    my $response = $useragent->get('http://example.com/', ':content_file' => $tmpfile);

    my $contents = path($tmpfile)->slurp;
    is($contents, $expected_content, 'response body is saved to file (network responses)');

    is($response->content, '', 'response body is removed');
    cmp_deeply(
        $response,
        methods(
            [ header => 'X-Died' ] => undef,
            [ header => 'Content-Type' ], => re(qr{^text/html}),
            [ header => 'Client-Date' ] => ignore,
        ),
        'response headers look ok',
    );
}

