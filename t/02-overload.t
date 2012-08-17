use strict;
use warnings FATAL => 'all';

use Test::More tests => 8;
use Test::Deep;
use Test::NoWarnings 1.04 ':early';

use Test::LWP::UserAgent;
use Class::Load 'try_load_class';

{
    package MyRequest;
    use overload '&{}' => sub {
        sub {
            ::isa_ok($_[0], 'HTTP::Request');
            $_[0]->method eq 'GET'
        }
    };
}
{
    package MyResponse;
    use overload '&{}' => sub {
        sub
        {
            ::isa_ok($_[0], 'HTTP::Request');
            HTTP::Response->new(202)
        }
    };
}
{
    package MyHost;
    sub new
    {
        my ($class, $string) = @_;
        bless { _string => $string }, $class;
    }
    use overload '""' => sub {
        my $self = shift;
        $self->{_string};
    };
    use overload 'cmp' => sub {
        my ($self, $other, $swap) = @_;
        $self->{_string} cmp $other;
    };
}


{
    my $useragent = Test::LWP::UserAgent->new;
    $useragent->map_response(bless({}, 'MyRequest'), bless({}, 'MyResponse'));

    my $response = $useragent->get('http://localhost');

    isa_ok($response, 'HTTP::Response');
    is($response->code, 202, 'response from overload');
}

SKIP: {
    try_load_class('HTTP::Message::PSGI')
        or skip('HTTP::Message::PSGI is required for the remainder of these tests', 3);

    my $useragent = Test::LWP::UserAgent->new;
    $useragent->register_psgi(MyHost->new('localhost'),
        sub { [ 200, [], ['home sweet home'] ] });

    my $response = $useragent->get('http://localhost');
    isa_ok($response, 'HTTP::Response');
    cmp_deeply(
        $response,
        methods(
            code => 200,
            content => "home sweet home",
        ),
        'response from string overload',
    );

    $useragent->unregister_psgi(MyHost->new('localhost'));
    $response = $useragent->get('http://localhost');
    is($response->code, 404, 'mapping removed via str overload comparison');
}

