package Notice::C::Security;

use warnings;
use strict;
use lib 'lib';
use base 'Notice';
my %submenu = (
   '1.0' => [
        '2' => { peer => 1, name=> 'Security', rm => 'security', class=> 'navigation'},
    ],
);


=head1 NAME

Template controller subclass for Notice

=head1 ABSTRACT

Template for consistent controller creation.

=head1 DESCRIPTION

Take a wild guess from the name

=head1 METHODS

=head2 SUBCLASSED METHODS

=head3 setup

Override or add to configuration supplied by Notice::cgiapp_init.

=cut

sub setup {
    my ($self) = @_;
    $self->authen->protected_runmodes(':all');
    $self->tt_params({submenu => \%submenu});
}

=head2 RUN MODES

=head3 main

This displays data about the security of Notice, how often certain things are accessed
and by whom

=cut

sub main: StartRunmode {
    my ($self) = @_;
    my $q = \%{ $self->query() };
    my ($username,$message,@sec_stats,@people,@acl);
       $username = $self->authen->username;
    if($username && $username ne 'a@b.com'){
        $self->tt_params({ warning => 'I will not warn you again! You are not meant to be in here.' });
        return $self->tt_process('sec_error.tmpl');
    }

    my $pe_id; # person that we are sooping on
    our $user_details; # everyone

    # we change the stat depending on what the administrator wants to view
    my %stat = ();
    if(defined $q->param('min_tally')){
       %stat = ( tally => {">", $q->param('$min_tally')});
    }else{
       %stat = ( tally => {">", '1'});
    }
    #        user => "$pe_id",
    #        action => "$action",
    #        description => "$desc",
    #  );

    if($pe_id && $pe_id=~m/^\d+$/){
        @people = $self->resultset('People')->search();
    }else{
        @people = $self->resultset('People')->search();
    }
    eval {
        @acl = $self->resultset('ActivityAcl')->search();
        @sec_stats = $self->resultset('ActivityLog')->search({
            %stat,
            -or => [
                -and => [
                    period => {'=' => 'd'},
                    start => {'=' => \'CURDATE()'},
                    end =>   {'<=' => \' CURDATE()+1'},
                ],
                -and => [
                    period => {'=' => 'y'},
                    start => {'=' => \'concat(date_format(NOW(), "%Y"), "-01-01")'},
                    end =>   {'<=' => \'concat(date_format(NOW(), "%Y"), "-12-31")'},

                ],
                # select date_sub(concat(date_format(date_add( curdate(), interval 1 month), '%Y-%m'), '-01'), INTERVAL 1 DAY) ;
                #
                # NTS have to add m,w,H,M,S
            ],
        });
    };

    $self->tt_params({sec_stats => \@sec_stats, acl => \@acl, message => $message, ppl => \@people });
    return $self->tt_process();
}

1;

__END__

=head1 BUGS AND LIMITATIONS

There are no known problems with this module.
Please fix any bugs or add any features you need. 
You can report them through GitHub or CPAN.

=head1 SEE ALSO

L<Notice>, L<CGI::Application>

=head1 SUPPORT AND DOCUMENTATION

You could look for information at:

    Notice@GitHub
        http://github.com/alexxroche/Notice

=head1 AUTHOR

Alexx Roche, C<alexx@cpan.org>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Alexx Roche

This program is free software; you can redistribute it and/or modify it
under the following license: Eclipse Public License, Version 1.0
or the Artistic License.

See http://www.opensource.org/licenses/ for more information.

=cut

