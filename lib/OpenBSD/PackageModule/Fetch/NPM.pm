package OpenBSD::PackageModule::Fetch::NPM;
use parent 'OpenBSD::PackageModule::Fetch';
use strict;
use warnings;

# NOTE:
# There is a relatively good chance that this should just use "npm"
# to get this information.  I'm not sure yet though.

# Copyright (c) 2013 Andrew Fresh <andrew@afresh1.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use 5.010;

use Carp;

sub base_url {'https://registry.npmjs.org/'}

sub get_dist_info {
    my ( $self, $distribution ) = @_;

    my $di = $self->_get_json($distribution);
    croak($di->{reason}) if $di->{error};
    return $di;
}

sub descr_for_dist {
    my ( $self, $di ) = @_;
    return $di->{readme};
}

sub format_dist {
    my ( $self, $di ) = @_;

    my $port = $self->port_for_dist($di);
    my ($category) = split m{/}x, $port;

    my $latest = $di->{versions}->{ $di->{'dist-tags'}->{'latest'} };

    my ( $master_sites, $distname )
        = $latest->{dist}->{tarball} =~ m{(.*/)([^/]+)$};

    my $comment
        = $latest->{rdescription}
        || $di->{rdescription}
        || $latest->{description}
        || $di->{description};

    my $license = $di->{license};
    $license = $license->{type} if ref $license eq 'HASH';
    $license = join ' ', @{ $license || [] } if ref $license eq 'ARRAY';

    my %formatted = (
        makefile => {
            COMMENT         => $comment,
            NPM_VERSION     => $latest->{version},
            NPM_NAME        => $latest->{name},
            MODULES         => 'lang/node',
            CONFIGURE_STYLE => 'npm',
            CATEGORIES      => $category,

            HOMEPAGE => $di->{homepage},

            PERMIT_PACKAGE_CDROM => 'Yes',    # TODO: decide based on license

            $self->_format_depends($latest),
            },

        distname => $latest->{name} . '-' . $latest->{version},
        license => $license,
        descr   => $self->descr_for_dist($di),

        port => $port,
    );

    # Picked up from elsewhere
    $formatted{MODULES} =~ s/ node//     if $formatted{MODULES};
    $formatted{CATEGORIES} =~ s/ node// if $formatted{CATEGORIES};

    return $self->SUPER::format_dist( \%formatted );
}

sub _format_depends {
    my ($self, $di) = @_;
    #use Data::Dumper 'Dumper'; warn Dumper $di; exit;

    my %depend_map = (
        BUILD_DEPENDS => [ 'devDependencies' ],
        RUN_DEPENDS   => ['dependencies'],
        #TEST_DEPENDS  => ['test'],
    );

    my %depends;
    foreach my $type ( sort keys %depend_map ) {
        my @ports;

        foreach my $key ( @{ $depend_map{$type} } ) {
            next unless $di->{$key};
            my %r = %{ $di->{$key} || {} };

            foreach my $dist ( sort keys %r ) {
                my $port = $self->port_for_dist($dist);

                my $version = $r{$dist};
                $version = '' if $version =~ m{://}; # sometimes URLs?
                $version =~ s/^[~^]/>=/; # because we don't support those
                $version =~ s/^(\d)/=$1/;

                # say ". $port [$dist]";
                $depends{$type}{$port} = {
                    port    => $port,
                    dist    => $dist,
                    version => $version,
                };
            }
        }
    }

    return %depends;
}

sub port_for_dist {
    my ( $self, $dist ) = @_;
    $dist = ref $dist ? $dist->{name} : $dist;

    # Map dist name on NPM to port name
    # TODO: This should not be hardcoded and stored here.
    $dist = {
    }->{$dist} || $dist;

    my ($dir) = glob("/usr/ports/*/node-$dist");
    $dir = "NPM/node-$dist" unless $dir && $dir !~ /\*/;
    $dir =~ s{^/usr/ports/+}{};

    return $dir;
}

1;
