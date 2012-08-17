use strict;
use warnings FATAL => 'all';

use Test::More tests => 3;
use Test::NoWarnings 1.04 ':early';

use Test::LWP::UserAgent;

{
    my $useragent = Test::LWP::UserAgent->new;
    $useragent->map_response('bar.com', HTTP::Response->new(200));
    Test::LWP::UserAgent->map_response('foo.com', HTTP::Response->new(201));
    $useragent->map_response('foo.com', undef);

    my $response = $useragent->get('http://foo.com');
    is($response->code, 404, 'global mapping is masked on the instance');
}

{
    my $useragent = Test::LWP::UserAgent->new;

    $useragent->map_response('bar.com', HTTP::Response->new(200));
    $useragent->map_response('foo.com', HTTP::Response->new(201));
    $useragent->map_response('foo.com', undef);

    # send request - it should hit a 404.
    my $response = $useragent->get('http://foo.com');
    is($response->code, 404, 'previous mapping is masked');
}

