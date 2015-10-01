package Test::WWW::UserAgent::History;

use strict;
use warnings;

use Scalar::Util qw(blessed reftype);

use Moo::Role;

my $last_useragent;

sub last_useragent {
    my $self = shift;

    $last_useragent = shift if @_;

    $last_useragent;
}

has _last_http_request_sent => (
    is => 'rw',
);

has _last_http_response_received => (
    is => 'rw',
);

sub last_http_request_sent
{
    my $self = shift;

    $self->_last_http_request_sent(shift) if @_;

    return blessed($self)
        ? $self->_last_http_request_sent
        : $self->last_useragent
            ? $self->last_useragent->last_http_request_sent
            : undef;
}

sub last_http_response_received
{
    my $self = shift;

    $self->_last_http_response_received(shift) if @_;

    return blessed($self)
        ? $self->_last_http_response_received
        : $self->last_useragent
            ? $self->last_useragent->last_http_response_received
            : undef;
}

1;


