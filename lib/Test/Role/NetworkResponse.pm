use strict;
use warnings;
package Test::Role::NetworkResponse;
# ABSTRACT: A role to allow simulating and testing network calls
# KEYWORDS: testing useragent networking mock server client
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.030';
use Role::Tiny;
use Scalar::Util qw(blessed reftype);
use Storable 'freeze';
#use HTTP::Request;
#use HTTP::Response;
#use URI;
#use HTTP::Date;
#use HTTP::Status qw(:constants status_message);
use Try::Tiny;
use Safe::Isa;
use Carp;
use namespace::autoclean 0.19 -also => [qw(__isa_coderef)];

my @response_map;
my $network_fallback;
my $last_useragent;

# returns the expected type of the responses being mapped.
# If the type is defined, $response->isa($type) should return true;
# if it is undefined, the response is expected to be an unblessed hashref.
# Test::LWP::UserAgent would return ( 'HTTP::Response' )
# Test::HTTP::Tiny would return ( undef )
requires 'response_type';

sub new
{
    my ($class, %options) = @_;

    my $_network_fallback = delete $options{network_fallback};

    my $self = $class->SUPER::new(%options);
    $self->{__last_http_request_sent} = undef;
    $self->{__last_http_response_received} = undef;
    $self->{__response_map} = [];
    $self->{__network_fallback} = $_network_fallback;

    # strips default User-Agent header added by LWP::UserAgent, to make it
    # easier to define literal HTTP::Requests to match against
    $self->agent(undef) if defined $self->agent and $self->agent eq $self->_agent;

    return $self;
}

sub map_response
{
    my ($self, $request_description, $response) = @_;

    if (not defined $response and blessed $self)
    {
        # mask a global domain mapping
        my $matched;
        foreach my $mapping (@{$self->{__response_map}})
        {
            if ($mapping->[0] eq $request_description)
            {
                $matched = 1;
                undef $mapping->[1];
            }
        }

        push @{$self->{__response_map}}, [ $request_description, undef ]
            if not $matched;

        return;
    }

    my $response_type = $self->response_type;

    if (not $response->$_isa('HTTP::Response') and try { $response->can('request') })
    {
        my $oldres = $response;
        $response = sub { $oldres->request($_[0]) };
    }

    carp 'map_response: response is not a coderef or an HTTP::Response, it\'s a ',
            (blessed($response) || 'non-object')
        unless __isa_coderef($response) or $response->$_isa('HTTP::Response');

    if (blessed $self)
    {
        push @{$self->{__response_map}}, [ $request_description, $response ];
    }
    else
    {
        push @response_map, [ $request_description, $response ];
    }
    return $self;
}

# network_response is specific to the thing being wrapped (e.g.
# LWP::UserAgent), so is left to the consumer to provide.
requires 'network_response';

# register_psgi 

sub unmap_all
{
    my ($self, $instance_only) = @_;

    if (blessed $self)
    {
        $self->{__response_map} = [];
        @response_map = () unless $instance_only;
    }
    else
    {
        carp 'instance-only unmap requests make no sense when called globally'
            if $instance_only;
        @response_map = ();
    }
    return $self;
}

requires 'psgi_to_response';

sub register_psgi
{
    my ($self, $domain, $app) = @_;

    return $self->map_response($domain, undef) if not defined $app;

    carp 'register_psgi: app is not a coderef, it\'s a ', ref($app)
        unless __isa_coderef($app);

    carp 'register_psgi: did you forget to load HTTP::Message::PSGI?'
        unless HTTP::Request->can('to_psgi') and HTTP::Response->can('from_psgi');

    return $self->map_response($domain, $self->psgi_to_response($app));
}

sub unregister_psgi
{
    my ($self, $domain, $instance_only) = @_;

    if (blessed $self)
    {
        @{$self->{__response_map}} = grep { $_->[0] ne $domain } @{$self->{__response_map}};

        @response_map = grep { $_->[0] ne $domain } @response_map
            unless $instance_only;
    }
    else
    {
        @response_map = grep { $_->[0] ne $domain } @response_map;
    }
    return $self;
}

sub __isa_coderef
{
    ref $_[0] eq 'CODE'
        or (reftype($_[0]) || '') eq 'CODE'
        or overload::Method($_[0], '&{}')
}

1;
