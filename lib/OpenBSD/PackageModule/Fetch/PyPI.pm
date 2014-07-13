package OpenBSD::PackageModule::Fetch::PyPI;
use parent 'OpenBSD::PackageModule::Fetch';
use strict;
use warnings;

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

use OpenBSD::PackageModule::Utils qw( port_value make_in_port );

use IPC::Open2;

sub base_url {'https://pypi.python.org/pypi?:action=json&name='}

sub get_dist_info {
    my ( $self, $distribution ) = @_;
    return $self->_get_json($distribution);
}

sub descr_for_dist {
    my ( $self, $di ) = @_;
    return $di->{info}->{description};
}

sub format_dist {
    my ( $self, $di ) = @_;

    my $port = $self->port_for_dist($di);
    my ($category) = split m{/}x, $port;

    my ( $master_sites, $distname )
        = $di->{urls}->[0]->{url} =~ m{(.*/)([^/]+)$};

    if ( $distname =~ s/\.tar\.gz$//x ) {

        # do nothing
        # Eventually, if we strip other types
        # TODO: It could become an EXTRACT_SUFX
    }

    my %formatted = (
        makefile => {
            COMMENT      => $di->{info}->{summary},
            DISTNAME     => $distname,
            MASTER_SITES => $master_sites,
            MODULES      => "lang/python",
            CATEGORIES   => $category,
            HOMEPAGE     => $di->{info}->{home_page},

            PERMIT_PACKAGE_CDROM => 'Yes',    # TODO: decide based on license

            MODPY_SETUPTOOLS => 'Yes',

            $self->_format_depends($di),
        },

        distname => $distname,
        license  => $di->{info}->{license},
        descr    => $self->descr_for_dist($di),

        port => $port,
    );

    return $self->SUPER::format_dist( \%formatted );
}

# XXX Why python, why?  so ugly!
sub _python_requires {
    my ($self, $di) = @_;

    $di->{port} ||= $self->port_for_dist( $di );

    make_in_port( $di, 'patch' );
    my $wrksrc = port_value($di, 'WRKSRC') or die "Couldn't find WRKSRC";

    # XXX This is a terrible hack!
    # XXX Instead this should ask the package system for an installed ver
    # XXX for now though, need to see if I can make it work.
    my ($python) = glob('/usr/local/bin/python[0-9].[0-9]');

    # this may be worse.
    my ($chld_out, $chld_in);
    my $pid = open2( $chld_out, $chld_in, "cd '$wrksrc' && $python" );

    print $chld_in <<'EOL';
import distutils.core
import re

def _setup(**kwargs):
    for name, value in kwargs.items():
        if re.match(r".*require", name):
            print '{0} = {1}'.format(name, value)

distutils.core.setup = _setup
import setup
EOL
    
    close $chld_in;

    my (@requires) = <$chld_out>;

    waitpid( $pid, 0 );
    my $chld_exit_status = $? >> 8;

    die "Python died unexpectedly with exit status: $chld_exit_status"
        if $chld_exit_status;

    my %requires;

    # at least these should be well formatted.
    foreach my $line (@requires) {
        chomp $line;
        my ($type, $requires) = split /\s+=\s+/, $line, 2;

        $requires =~ s/^\[(.*)\]$/$1/;
        $requires =~ s/'//g;
        my @d = split /\s*,\s*/, $requires;

        foreach (@d) {
            my ($d, $v) = /^([^=]+?)(\W?=.*)?$/;
            $requires{$type}{$d} = $v || '';
        }
    }

    return %requires;
}

sub _format_depends {
    my ( $self, $di ) = @_;

    my %prereqs = $self->_python_requires( $di );

    my %depend_map = (
        BUILD_DEPENDS => ['setup_requires'],
        RUN_DEPENDS   => ['install_requires', 'requires'],
        TEST_DEPENDS  => ['tests_require'],
        # ['extras_require'] ???
    );

    my %depends;
    foreach my $type ( sort keys %depend_map ) {
        my @ports;

        foreach my $key ( @{ $depend_map{$type} } ) {
            next unless $prereqs{$key};
            my %r = %{ $prereqs{$key} || {} };

            foreach my $dist ( sort keys %r ) {
                my $port = $self->port_for_dist($dist);

                # say ". $port [$module]";
                $depends{$type}{$port} = {
                    port    => $port,
                    dist    => $dist,
                    version => $r{$dist},
                };
            }
        }
    }

    # People like to hide test depends in build depends because
    # some tools don't make the distinction.
    #$depends{TEST_DEPENDS} = delete $depends{BUILD_DEPENDS}
    #    if grep {/Test/} keys %{ $depends{BUILD_DEPENDS} || {} };

    return %depends;
}

sub port_for_dist {
    my ( $self, $dist ) = @_;
    $dist = ref $dist ? $dist->{info}->{name} : $dist;

    # Map dist name on PyPI to port name
    # TODO: This should not be hardcoded and stored here.
    #$dist = {
    #}->{$dist} || $dist;mo

    my ($dir) = glob("/usr/ports/*/py-$dist");
    $dir = "PyPI/py-$dist" unless $dir && $dir !~ /\*/;
    $dir =~ s{^/usr/ports/+}{};

    return $dir;
}

1;
