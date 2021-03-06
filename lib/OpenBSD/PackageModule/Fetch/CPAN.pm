package OpenBSD::PackageModule::Fetch::CPAN;
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

sub base_url {'https://fastapi.metacpan.org/'}

sub get_dist_info {
    my ( $self, $distribution ) = @_;

    $distribution = $self->get_dist_for_module($distribution)
        if $distribution =~ /::/x;

    return $self->_get_json("release/$distribution");
}

sub get_dist_for_module {
    my ( $self, $module ) = @_;
    return $self->_get_json("module/$module?fields=distribution")
        ->{distribution};
}

sub descr_for_dist {
    my ( $self, $di ) = @_;

    my @readme   = split /\n/x, $self->get_readme_for_dist($di);
    my $descr    = q{};
    my $in_descr = 0;

    foreach (@readme) {
        if (/^(\S+)/x) {
            last if $in_descr;

            $in_descr = $1 eq 'DESCRIPTION';
            next;
        }

        if ($in_descr) {
            s/^\s+//x;
            $descr .= "$_\n";
        }
    }

    return $descr;
}

sub get_readme_for_dist {
    my ( $self, $di ) = @_;

    my $path = join '/', 'source', @{$di}{qw( author name )}, 'README';
    return eval { $self->_get($path) } || 'XXX - NO README FOUND - XXX';
}

sub format_dist {
    my ( $self, $di ) = @_;

    my $port = $self->port_for_dist($di);
    my ($category) = split m{/}x, $port;

    my $distname = $di->{archive};
    my $suffix;
    if ( $distname =~ s/\.tar\.gz$//x ) {

        # do nothing
        # Eventually, if we strip other types
        # TODO: It could become an EXTRACT_SUFX
    }
    elsif ( $distname =~ s/(\.tar.[^.]+)$// or $distname =~ s/(\.[^.]+)$// ) {
	$suffix = $1;
    }

    my $license = join ' ',
        ref $di->{license} ? @{ $di->{license} || [] } : ( $di->{license} );

    my %formatted = (
        makefile => {
            COMMENT     => "$di->{abstract}",
            DISTNAME    => $distname,
            MODULES     => "cpan",
            CATEGORIES  => "$category",
            CPAN_AUTHOR => "$di->{author}",
            PKG_ARCH    => "*",

            PERMIT_PACKAGE_CDROM => 'Yes',    # TODO: decide based on license

            $self->_format_depends($di),
        },

        distname => $distname,
        license  => $license,
        descr    => $self->descr_for_dist($di),

        #CONFIGURE_STYLE=>modbuild

        port => $port,
    );

    $formatted{makefile}{EXTRACT_SUFX} = $suffix if $suffix;

    delete $formatted{HOMEPAGE}
        if $formatted{HOMEPAGE}
        && $formatted{HOMEPAGE} =~ /search\.cpan\.org/x;

    # Picked up from elsewhere
    $formatted{MODULES} =~ s/ perl//     if $formatted{MODULES};
    $formatted{CATEGORIES} =~ s/ perl5// if $formatted{CATEGORIES};

    return $self->SUPER::format_dist( \%formatted );
}

sub _format_depends {
    my ( $self, $di ) = @_;

    my %prereqs = %{ $di->{metadata}->{prereqs} || {} };

    my %depend_map = (
        BUILD_DEPENDS => [ 'configure', 'build' ],
        RUN_DEPENDS   => ['runtime'],
        TEST_DEPENDS  => ['test'],
    );

    my %depends;
    foreach my $type ( sort keys %depend_map ) {
        my @ports;

        foreach my $key ( @{ $depend_map{$type} } ) {
            next unless $prereqs{$key};

            foreach my $want (qw( requires recommends )) {
                my $t = $want eq 'recommends' ? 'TEST_DEPENDS' : $type;
                my %r = %{ $prereqs{$key}{$want} || {} };

                foreach my $module ( sort keys %r ) {
                    next if $self->module_is_in_base($module);

                    my $dist = $self->get_dist_for_module($module);
                    my $port = $self->port_for_dist($dist);

                    # say ". $port [$module]";
                    my %details = (
                        port    => $port,
                        dist    => $dist,
                    );
                    # assume >=
                    $details{version} = '>=' . $r{$module} if $r{$module};
                    $depends{$t}{$port} = \%details;
                }
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
    $dist = ref $dist ? $dist->{distribution} : $dist;

    # Map dist name on CPAN to port name
    # TODO: This should not be hardcoded and stored here.
    $dist = {
	'Date-Manip'   => 'DateManip',
        MailTools      => 'Mail-Tools',
	'Template-Toolkit' => 'Template',
        TimeDate       => 'Time-TimeDate',
        'YAML-LibYAML' => 'YAML-XS',
        Mojolicious    => 'Mojo',
        'libwww-perl'  => 'libwww',
        'Net-SSLeay'   => 'Net_SSLeay',
	'UNIVERSAL-require' => 'Univeral-require',
    }->{$dist} || $dist;

    my ($dir) = glob("/usr/ports/*/p5-$dist");
    $dir = "CPAN/p5-$dist" unless $dir && $dir !~ /\*/;
    $dir =~ s{^/usr/ports/+}{};

    return $dir;
}

sub module_is_in_base {
    my ( $self, $module ) = @_;

    return 1 if $module eq 'perl';

    my $module_path = $module . '.pm';
    $module_path =~ s{::}{/}gx;

    foreach (@INC) {
        next unless m{/usr/libdata/}x;
        return 1 if -e "$_/$module_path";
    }

    return 0;
}

1;
