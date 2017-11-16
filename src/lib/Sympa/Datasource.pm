# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4

# This file is part of Sympa, see top-level README.md file for details

package Sympa::Datasource;

use strict;
use warnings;
use Digest::MD5 qw();

use Sympa::Log;
use Sympa::Regexps;

my $log = Sympa::Log->instance;

############################################################
#  constructor
############################################################
#  Create a new datasource object. Handle SQL source only
#  at this moment.
#
# IN : -$type (+): the type of datasource to create
#         'SQL' or 'MAIN' for main sympa database
#      -$param_ref (+): ref to a Hash of config data
#
# OUT : instance of Datasource
#     | undef
#
##############################################################
sub new {
    my ($pkg, $param) = @_;
    $log->syslog('debug', '');
    my $self = $param;
    ## Bless Message object
    bless $self, $pkg;
    return $self;
}

# Returns a unique ID for an include datasource
sub _get_datasource_id {
    my ($source) = shift;
    $log->syslog('debug2', 'Getting datasource id for source "%s"', $source);
    # Not in case.
    #if (ref($source) eq 'Sympa::Datasource') {
    #    $source = shift;
    #}

    if (ref($source)) {
        ## Ordering values so that order of keys in a hash don't mess the
        ## value comparison
        ## Warning: Only the first level of the hash is ordered. Should a
        ## datasource
        ## be described with a hash containing more than one level (a hash of
        ## hash) we should transform
        ## the following algorithm into something that would be recursive.
        ## Unlikely it happens.
        my @orderedValues =
            map { (defined $source->{$_}) ? ($_, $source->{$_}) : () }
            sort keys %$source;
        return substr(Digest::MD5::md5_hex(join('/', @orderedValues)), -8);
    } else {
        return substr(Digest::MD5::md5_hex($source), -8);
    }

}

sub is_allowed_to_sync {
    #my $self   = shift;
    #my $ranges = $self->{'nosync_time_ranges'};
    my $ranges = shift;

    return 1 unless defined $ranges and length $ranges;

    $ranges =~ s/^\s+//;
    $ranges =~ s/\s+$//;
    my $rsre = Sympa::Regexps::time_ranges();
    return 1 unless ($ranges =~ /^$rsre$/);

    $log->syslog('debug', "Checking whether sync is allowed at current time");

    my ($sec, $min, $hour) = localtime(time);
    my $now = 60 * int($hour) + int($min);

    foreach my $range (split(/\s+/, $ranges)) {
        next
            unless ($range =~
            /^([012]?[0-9])(?:\:([0-5][0-9]))?-([012]?[0-9])(?:\:([0-5][0-9]))?$/
            );
        my $start = 60 * int($1) + int($2);
        my $end   = 60 * int($3) + int($4);
        $end += 24 * 60 if ($end < $start);

        $log->syslog('debug',
                  "Checking for range from "
                . sprintf('%02d', $start / 60) . "h"
                . sprintf('%02d', $start % 60) . " to "
                . sprintf('%02d', ($end / 60) % 24) . "h"
                . sprintf('%02d', $end % 60));

        next if ($start == $end);

        if ($now >= $start && $now <= $end) {
            $log->syslog('debug', 'Failed, sync not allowed');
            return 0;
        }

        $log->syslog('debug', "Pass ...");
    }

    $log->syslog('debug', "Sync allowed");
    return 1;
}

1;
