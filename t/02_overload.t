use strict;
use warnings FATAL => 'all';

use Test::More tests => 5;
use Test::NoWarnings 1.04 ':early';

use Test::LWP::UserAgent;

{
    package MyRequest;
    use overload '&{}' => sub {
        sub {
            ::isa_ok($_[0], 'HTTP::Request');
            $_[0]->method eq 'GET'
        }
    }
}
{
    package MyResponse;
    use overload '&{}' => sub {
        sub
        {
            ::isa_ok($_[0], 'HTTP::Request');
            HTTP::Response->new(202)
        }
    }
}

{
    my $useragent = Test::LWP::UserAgent->new;
    $useragent->map_response(bless({}, 'MyRequest'), bless({}, 'MyResponse'));

    my $response = $useragent->get('http://localhost');

    isa_ok($response, 'HTTP::Response');
    is($response->code, 202, 'response from overload');
}

