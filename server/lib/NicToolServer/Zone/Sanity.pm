package NicToolServer::Zone::Sanity;
# ABSTRACT: sanity tests for NicTool zones

use strict;

@NicToolServer::Zone::Sanity::ISA = qw(NicToolServer::Zone);

sub new_zone {
    my ( $self, $data ) = @_;

    my $user = $data->{user};

    $self->push_sanity_error( 'nt_group_id',
        'Cannot add zone to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{nt_group_id} );

    if ( $data->{zone} =~ /([^\/a-zA-Z0-9\-\.])/ ) {
        $self->error( 'zone', "invalid character in zone -- $1" );
    }

    if ( $data->{zone} !~ /in-addr.arpa$/i && $data->{zone} =~ /\// ) {
        $self->error( 'zone', 
            "invalid character in zone '/'. Only allowed in reverse-lookup zones"
        );
    }

    $data->{zone} =~ s/\.$//;  # remove any trailing dot

#    if ( $data->{zone} =~ /in-addr.arpa$/ ) {
# TODO - any in-addr.arpa reverse DNS zone checks go here.
# warn users if they try to make a PTR that points to an IP address rather
# than a name. 2001.10.12, --aai
#    }

    if ( $data->{zone} !~ /.+\..+$/ ) {
        $self->error( 'zone', 
            "Zone must be a valid domain name -- something.something"
        );
    }

    $self->valid_label( 'zone', $data->{zone} );

    # check if zone exists
    if ( $self->zone_exists( $data->{zone}, 0 ) ) {
        $self->error( 'zone', 'Zone is already taken' );
    }

    #check subdomains

    # sub-domain checks .. kinda nasty, but I think it has to be.
    my $z = $data->{zone};
    $z =~ tr/A-Z/a-z/;
    my @zparts = split( /\./, $z );
    if ( $z =~ /[a-z0-9\-\/]+\.[a-z0-9\-\/]+$/ ) {  # zone has at least one dot
        my $zstr = pop(@zparts);
        my @zonestocheck;
        while ( my $x = pop(@zparts) ) {
            $zstr = $x . "." . $zstr;
            push @zonestocheck, $zstr;
        }
        foreach my $orig_zone (@zonestocheck) {
            if ( my $zref = $self->zone_exists( $orig_zone, 0 ) ) {

#use new permission-system to check for 'read' access to the zone...XXX 'read' access correct?
                my @error = $self->check_permission( 'nt_zone_id',
                    $zref->{nt_zone_id}, 'read', 'ZONE' );
                if ( defined $error[0] ) {
                    $self->error( 'zone', "Sub-domain creation not allowed: Access to zone $orig_zone denied: $error[1]"
                    );
                }
                if ($self->record_exists_within_zone( $zref->{nt_zone_id}, $z )) {
                    $self->error( 'zone', "A record within $orig_zone named $z already exists. Delete or rename the record and then you can add $z as a sub-domain.\n"
                    );
                }

                # TODO - warn user that they're creating a sub-domain..
            }
        }
    }

    # check the zone's TTL
    $data->{ttl} ||= 86400;

    $self->valid_ttl( $data->{ttl} );

    return $self->throw_sanity_error if ( $self->{errors} );
    $self->SUPER::new_zone($data);
}

sub edit_zone {
    my ( $self, $data ) = @_;

    my $user = $data->{user};

    $self->push_sanity_error( 'nt_zone_id', 'Cannot edit deleted zone!' )
        if $self->check_object_deleted( 'zone', $data->{nt_zone_id} )
            and $data->{deleted} ne '0';

    my $dataobj = $self->get_zone($data);
    return $dataobj if $self->is_error_response($dataobj);

    $self->push_sanity_error( 'nt_zone_id',
        'Cannot edit zone in a deleted group!' )
        if $self->check_object_deleted( 'group', $dataobj->{nt_group_id} );

    # check the zone's TTL
    $self->valid_ttl( $data->{ttl} ) if defined $data->{ttl};

    my $zone = $self->find_zone( $data->{nt_zone_id} );

    if (    $data->{deleted} eq '0'
        and $self->zone_exists( $zone->{zone}, $zone->{nt_zone_id} ) )
    {
        $self->error( 'zone', "Can't undelete the zone '$zone->{zone}' because another zone called '$zone->{zone}' now exists"
        );
    }

    return $self->throw_sanity_error if $self->{errors};
    $self->SUPER::edit_zone($data);
}

sub move_zones {
    my ( $self, $data ) = @_;

    $self->push_sanity_error( 'nt_group_id',
        'Cannot move zones to a deleted group!' )
        if $self->check_object_deleted( 'group', $data->{nt_group_id} );

    if (my @deld = grep { $self->check_object_deleted( 'zone', $_ ) }
        split( /,/, $data->{zone_list} )
        )
    {
        $self->push_sanity_error( 'nt_zone_id',
            'Cannot move deleted zones: ' . join( ",", @deld ) );
    }

    return $self->throw_sanity_error if $self->{errors};

    return $self->SUPER::move_zones($data);
}

sub get_zone_record_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw(action user timestamp name description type address weight) );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_zone_record_log($data);
}

sub get_group_zones_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw/action user timestamp zone description ttl group_name/ );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_group_zones_log($data);
}

sub get_group_zones {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data, qw/ zone group_name description
         queries_successful queries_norecord records /
    );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_group_zones($data);
}

sub get_zone_records {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw/name description type address weight queries/ );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_zone_records($data);
}

sub get_group_zone_query_log {
    my ( $self, $data ) = @_;

    $self->search_params_sanity_check( $data,
        qw/ timestamp nameserver zone query qtype flag ip port / );
    return $self->throw_sanity_error if $self->{errors};
    return $self->SUPER::get_group_zone_query_log($data);
}

sub record_exists_within_zone {
    my ( $self, $zid, $name ) = @_;

    my $base_name = $name;
    $base_name =~ s/\..*$//;
    $name .= '.' if $name !~ /\.$/;
    my $sql = "SELECT * FROM nt_zone_record WHERE deleted=0
        AND nt_zone_id = ? AND ( name = ? OR name = ? )";
    my $zrs = $self->exec_query( $sql, [ $zid, $name, $base_name ] );
    return ref $zrs->[0] ? 1 : 0;
}

1;

__END__

=head1 SYNOPSIS
  

=cut

