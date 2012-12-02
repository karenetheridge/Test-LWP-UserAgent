use strict;
use warnings;

# This example demonstrates how one might go about writing some tests for a
# client library that interacts with a RESTful API. At a minimum, we want to
# test when we receive a network timeout (which is quite common and all
# clients must be able to handle), a failed query and a successful query.

# Note that *we are not testing the network*, but testing the code that
# interacts with the network. Therefore, we need to make the network behave in
# different ways so we can test how we interact with it.

use Test::More tests => 4;
use Test::Warn;
#use MyApp::Client; (included inline below)
use Test::LWP::UserAgent;

my $useragent = Test::LWP::UserAgent->new;
# this is what LWP::UserAgent effectively does when it encounters a timeout
$useragent->map_response(qr{user/timeout}, sub { die 'read timeout' });
$useragent->map_response(
    qr{user/fred},
    HTTP::Response->new(404, HTTP::Status::status_message(404),
        [ 'Content-Type' => 'text/plain' ],
        'user fred does not exist',
    ),
);
$useragent->map_response(
    qr{user/barney},
    HTTP::Response->new(200, HTTP::Status::status_message(200),
        [ 'Content-Type' => 'application/json' ],
        '{"user":"barney","userid":"50","blog_posts":"1","post_ids":["76"]}',
    ),
);

my $client = MyApp::Client->new(useragent => $useragent);

my @ids;
warning_like { @ids = $client->get_indexes(user => 'timeout') }
    qr{network timeout when fetching http://.*user/timeout},
    'warning issued on network timeout';
is_deeply(\@ids, [], 'no ids returned on network timeout');

@ids = $client->get_indexes(user => 'fred');
is_deeply(\@ids, [], 'no ids returned for non-existent user');

@ids = $client->get_indexes(user => 'barney');
is_deeply(\@ids, [ 76 ], 'one id returned for regular user');


package MyApp::Client;
use strict;
use warnings;

use Moose;
use LWP::UserAgent;
use JSON;

has useragent => (
    is => 'ro', isa => 'LWP::UserAgent',
    lazy => 1,
    default => sub { LWP::UserAgent->new },
);

sub get_indexes
{
    my ($self, %args) = @_;

    my $user = $args{user};

    # call our server to get the data
    my $url = "http://myserver.com/user/$user";
    my $response = $useragent->get($url);

    if ($response->code ne '200'
        or $response->headers->content_type ne 'application/json')
    {
        warn "network timeout when fetching $url" if $response->decoded_content =~ /^read timeout/;
        return;
    }

    # parse JSON data from response
    my $data = decode_json($response->decoded_content);
    return @{$data->{post_ids} // []};
}

