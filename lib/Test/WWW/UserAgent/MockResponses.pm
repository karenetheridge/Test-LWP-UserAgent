package Test::WWW::UserAgent::MockResponses;
# ABSTRACT: Provide response mapping methods for Test::WWW::UserAgent classes

use strict;
use warnings;

use Moo::Role;

use Try::Tiny;
use Scalar::Util qw(blessed reftype);
use Safe::Isa;
use Carp;
use Storable 'freeze';

my @response_map;
my $network_fallback;

has _response_map => (
    is => 'rw',
    default => sub { [] },
);

# behavior changed: won't check each time,
# but is set at object creation time
has network_fallback => (
    is => 'rw',
    default => sub { $network_fallback },
);

sub _all_response_map {
    my $self = shift;
    return @{$self->_response_map}, @response_map;
}

sub match_response_map {
    my( $self, $request ) = @_;

    my $uri = $request->uri;

    foreach my $entry ( grep { defined } $self->_all_response_map )
    {
        my ($request_desc, $response) = @$entry;

        if ($request_desc->$_isa('HTTP::Request'))
        {
            local $Storable::canonical = 1;
            return $response
                if freeze($request) eq freeze($request_desc);
        }

        if (__is_regexp($request_desc))
        {
            return $response if $uri =~ $request_desc;
        }

        if (__isa_coderef($request_desc))
        {
            return $response if $request_desc->($request);
        }

        $uri = URI->new($uri) if not $uri->$_isa('URI');
        return $response if $uri->host eq $request_desc;
    }

    return;
}

sub map_response
{
    my ($self, $request_specification, $response) = @_;

    if (not defined $response and blessed $self)
    {
        # mask a global domain mapping
        my $matched;
        foreach my $mapping (@{$self->_response_map})
        {
            if ($mapping->[0] eq $request_specification)
            {
                $matched = 1;
                undef $mapping->[1];
            }
        }

        push @{$self->_response_map}, [ $request_specification, undef ]
            if not $matched;

        return;
    }

    my ($isa_response, $error_message) = __isa_response($response);
    if (not $isa_response)
    {
        if (try { $response->can('request') })
        {
            my $oldres = $response;
            $response = sub { $oldres->request($_[0]) };
        }
        else
        {
            carp 'map_response: ', $error_message;
        }
    }

    if (blessed $self)
    {
        push @{$self->_response_map}, [ $request_specification, $response ];
    }
    else
    {
        push @response_map, [ $request_specification, $response ];
    }
    return $self;
}

sub map_network_response
{
    my ($self, $request_specification) = @_;

    push (
        @{ blessed($self) ? $self->_response_map : \@response_map },
        [ $request_specification, $self->_response_send_request ],
    );

    return $self;
}

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

sub register_psgi
{
    my ($self, $domain, $app) = @_;

    return $self->map_response($domain, undef) if not defined $app;

    carp 'register_psgi: app is not a coderef, it\'s a ', ref($app)
        unless __isa_coderef($app);

    return $self->map_response($domain, $self->_psgi_to_response($app));
}

sub unregister_psgi
{
    my ($self, $domain, $instance_only) = @_;

    if (blessed $self)
    {
        $self->_response_map( [
            grep { $_->[0] ne $domain } @{$self->_response_map}
        ]);

        @response_map = grep { $_->[0] ne $domain } @response_map
            unless $instance_only;
    }
    else
    {
        @response_map = grep { $_->[0] ne $domain } @response_map;
    }
    return $self;
}

# turns a PSGI app into a subref returning an HTTP::Response
sub _psgi_to_response
{
    my ($self, $app) = @_;

    carp 'register_psgi: did you forget to load HTTP::Message::PSGI?'
        unless HTTP::Request->can('to_psgi') and HTTP::Response->can('from_psgi');

    return sub { HTTP::Response->from_psgi($app->($_[0]->to_psgi)) };
}

# returns a subref that returns an HTTP::Response from a real network request
sub _response_send_request
{
    my $self = shift;

    # we cannot call ::request here, or we end up in an infinite loop
    return sub { $self->SUPER::send_request($_[0]) } if blessed $self;
    return sub { LWP::UserAgent->new->send_request($_[0]) };
}

sub __isa_coderef
{
    ref $_[0] eq 'CODE'
        or (reftype($_[0]) || '') eq 'CODE'
        or overload::Method($_[0], '&{}')
}

sub __is_regexp
{
    re->can('is_regexp') ? re::is_regexp(shift) : ref(shift) eq 'Regexp';
}

# returns true if is expected type for all response mappings,
# or (false, error message);
sub __isa_response
{
    __isa_coderef($_[0]) || $_[0]->$_isa('HTTP::Response')
        ? (1)
        : (0, 'response is not a coderef or an HTTP::Response, it\'s a '
                . (blessed($_[0]) || ( ref($_[0]) ? 'unblessed ' . ref($_[0]) : 'non-reference' )));
}

1;


